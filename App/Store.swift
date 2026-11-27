import Foundation
import Observation
import SwiftUI
import UserNotifications
import LocalAuthentication
import Network

enum Phase { case launching, login, onboarding, ready }
enum Tab: String, CaseIterable { case home, messages, clients, payments, more }
enum ThemeMode: String { case system, light, dark }

enum Route: Hashable {
    case chat(String)          // id переписки
    case profile(String)       // id клиента
    case editContact(String)   // id клиента
    case archive
    case notifications
    case schedule
    case folders
    case lists
    case staff
    case account
    case security
}

enum SheetKind: Identifiable, Equatable {
    case newPay(contactId: String?)
    case newClient
    case invite
    case staff(String)
    case classItem(String?)
    case subject(Int?)
    case folder(String?)
    case lesson(String)
    case addLesson(editId: String?)
    case forward(conv: String, mids: [String])
    case attach(conv: String)
    case schedSend(conv: String, text: String)
    case scheduledList(conv: String)
    case password

    var id: String {
        switch self {
        case .newPay(let c): return "pay" + (c ?? "")
        case .newClient: return "newclient"
        case .invite: return "invite"
        case .staff(let s): return "staff" + s
        case .classItem(let s): return "class" + (s ?? "")
        case .subject(let i): return "subj\(i ?? -1)"
        case .folder(let f): return "folder" + (f ?? "")
        case .lesson(let l): return "lesson" + l
        case .addLesson(let e): return "addlesson" + (e ?? "")
        case .forward(let c, let m): return "fwd" + c + m.joined()
        case .attach(let c): return "attach" + c
        case .schedSend(let c, _): return "sched" + c
        case .scheduledList(let c): return "schedlist" + c
        case .password: return "password"
        }
    }
}

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
    let undo: Bool
}

struct TypingInfo: Equatable {
    let at: Date
    let kind: String
}

struct SubjectItem: Codable, Hashable {
    var name: String
    var color: String
}

/// Уведомление в списке «Уведомления» (собирается из данных кабинета).
struct NoteItem: Identifiable {
    enum Kind { case msg, pay, rem, les }
    let id: String
    let kind: Kind
    let title: String
    let sub: String
    let at: Date
    let convId: String?
}

/// Состояние для снимков демо-режима: загрузка, пусто, ошибка, нет сети.
enum DemoState: String { case normal, loading, empty, error, offline }

/// Всё состояние приложения. Данные — с сервера (/api/state), действия — через /api/actions и отдельные адреса,
/// живые обновления — SSE /api/events (delta, typing, presence). Локально — тема, предметы, телефонная книга.
@MainActor
@Observable
final class Store {
    var phase: Phase = .launching
    var user: User?
    var state: AppState = .empty
    var account: AccountInfo?
    var toast: Toast?
    var loading = false
    var loaded = false
    var lastError: String?
    var offline = false
    var tab: Tab = .home
    var homePath: [Route] = []
    var messagesPath: [Route] = []
    var clientsPath: [Route] = []
    var paymentsPath: [Route] = []
    var morePath: [Route] = []
    var sheet: SheetKind?
    var fullHistory: [String: [Message]] = [:]
    var historyMore: [String: Bool] = [:]
    var serverDrafts: [String: String] = [:]
    var typing: [String: TypingInfo] = [:]
    var presence: [String: Presence] = [:]
    var scheduled: [String: [ScheduledMessage]] = [:]
    var lessons: [Lesson] = []
    var lessonsWeek: Date = Store.monday(of: Date())
    var lessonsError: String?
    var findings: [PaymentFinding] = []
    var suggestions: [LinkSuggestion] = []
    var locked = false
    var fixture = false
    var demo: DemoState = .normal
    /// для снимков: какой экран открыть внутри (меню сообщения, запись)
    var demoChatOverlay: String?
    var messagesFilter = "all"
    var showArchiveRow = false
    var bookNames: [String: String] = [:]
    var bookAccess: Bool? = nil
    var pushToken: String? = UserDefaults.standard.string(forKey: "pushToken")
    var notifSeen: Date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "notifSeen"))

    // локальные настройки
    var theme: ThemeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
    var contactsOn: Bool = UserDefaults.standard.object(forKey: "contactsOn") as? Bool ?? true
    var pushOn: Bool = UserDefaults.standard.object(forKey: "push") as? Bool ?? false
    var remindersOn: Bool = UserDefaults.standard.object(forKey: "reminders") as? Bool ?? true
    var faceOn: Bool = UserDefaults.standard.object(forKey: "face") as? Bool ?? false
    var onboarded: Bool = UserDefaults.standard.bool(forKey: "onboarded")
    var subjects: [SubjectItem] = Store.loadSubjects()
    var lessonSubject: [String: String] = UserDefaults.standard.dictionary(forKey: "lessonSubject") as? [String: String] ?? [:]
    var extraClasses: [String] = UserDefaults.standard.stringArray(forKey: "extraClasses") ?? []
    var unreadLocal: Set<String> = []

    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var reloadPending = false
    @ObservationIgnored var toastUndo: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, !self.fixture else { return }
                let off = path.status != .satisfied
                if off != self.offline { withAnimation { self.offline = off } }
                if !off && self.phase == .ready { await self.loadState() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net"))
    }

    // MARK: - выборки

    var folders: [Folder] { state.folders }
    func folder(_ id: String?) -> Folder? { state.folders.first { $0.id == id } }
    func contact(_ id: String?) -> Contact? { state.contacts.first { $0.id == id } }
    func conversation(_ id: String?) -> Conversation? { state.conversations.first { $0.id == id } }
    func conversations(of contactId: String) -> [Conversation] { state.conversations.filter { $0.contactId == contactId } }
    func mainConversation(of contactId: String) -> Conversation? {
        conversations(of: contactId).max { ($0.last?.date ?? .distantPast) < ($1.last?.date ?? .distantPast) }
    }
    func deals(of contactId: String) -> [Deal] { state.deals.filter { $0.contactId == contactId } }
    var openReminders: [Reminder] { state.reminders.filter { !$0.done } }
    func reminder(for contactId: String) -> Reminder? { openReminders.filter { $0.contactId == contactId }.min { $0.date < $1.date } }
    var currency: String? { state.workspace?.currency }
    func money(_ v: Double) -> String { Fmt.money(v, currency: currency) }
    func member(_ id: String) -> TeamMember? { state.team.first { $0.id == id } }

    var liveChats: [Conversation] { state.conversations.filter { !$0.isArchived } }
    var archivedChats: [Conversation] { sortChats(state.conversations.filter { $0.isArchived }) }
    var totalUnread: Int { liveChats.filter { !$0.isMuted }.reduce(0) { $0 + unread($1) } }
    func unread(_ c: Conversation) -> Int { max(c.unread, unreadLocal.contains(c.id) ? 1 : 0) }
    func waiting(_ c: Conversation) -> Bool { c.last.map { !$0.isOut } ?? false }

    func sortChats(_ list: [Conversation]) -> [Conversation] {
        list.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned, let pa = a.pinnedAt, let pb = b.pinnedAt, pa != pb { return pa > pb }
            return lastDate(a) > lastDate(b)
        }
    }
    func lastDate(_ c: Conversation) -> Date { c.last?.date ?? contact(c.contactId)?.first ?? .distantPast }

    func messages(_ convId: String) -> [Message] {
        let recent = conversation(convId)?.messages ?? []
        guard let full = fullHistory[convId] else { return recent }
        var ids = Set(full.map(\.id))
        var merged = full
        for m in recent where !ids.contains(m.id) { merged.append(m); ids.insert(m.id) }
        let fresh = Dictionary(recent.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return merged.map { fresh[$0.id] ?? $0 }.sorted { $0.date < $1.date }
    }

    // MARK: имена и телефонная книга

    /// Имя клиента: для номеров WhatsApp и MAX — из телефонной книги, если включено.
    func name(_ c: Contact?) -> String {
        guard let c else { return "Клиент" }
        if let b = bookName(c) { return b }
        return c.name
    }

    func bookName(_ c: Contact) -> String? {
        guard contactsOn, bookAccess == true, isPhoneContact(c), let p = phoneOf(c) else { return nil }
        return bookNames[PhoneBook.key(p)]
    }

    func inBook(_ c: Contact) -> Bool {
        guard bookAccess == true, let p = phoneOf(c) else { return false }
        return bookNames[PhoneBook.key(p)] != nil
    }

    func isPhoneContact(_ c: Contact) -> Bool {
        Net.phoneOnly(c.source) || (c.networks ?? []).contains(where: { Net.phoneOnly($0) })
    }

    func phoneOf(_ c: Contact) -> String? {
        if let p = c.phone, !p.isEmpty { return p }
        if PhoneBook.looksLikePhone(c.name) { return c.name }
        if let h = c.handle, PhoneBook.looksLikePhone(h) { return h }
        return nil
    }

    /// Имя для аватарки: номер без имени показываем значком человека.
    func avatarName(_ c: Contact?) -> String {
        guard let c else { return "?" }
        let n = name(c)
        return PhoneBook.looksLikePhone(n) ? "+" : n
    }

    // MARK: - запуск

    func bootstrap() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fixture") {
            fixture = true
            Fixture.apply(self)
            return
        }
        #endif
        if faceOn { locked = true }
        let started = Date()
        do {
            let me = try await API.get(MeResponse.self, "/api/auth/me/")
            user = me.user
            await loadState(force: true)
            await splashPause(started)
            phase = onboarded ? .ready : .onboarding
            afterLogin()
        } catch let e as APIError where e.status == 401 {
            await splashPause(started)
            phase = .login
        } catch {
            await splashPause(started)
            // нет сети: если кука есть — пускаем в кабинет и пробуем позже
            if !API.cookies.isEmpty {
                phase = .ready
                lastError = friendly(error)
                startLive()
            } else {
                phase = .login
            }
        }
    }

    /// Заставка видна хотя бы 1,2 с, чтобы не мигала.
    private func splashPause(_ started: Date) async {
        let left = 1.2 - Date().timeIntervalSince(started)
        if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
    }

    func didLogin() async {
        do { user = try await API.get(MeResponse.self, "/api/auth/me/").user } catch {}
        etag = nil
        await loadState(force: true)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = onboarded ? .ready : .onboarding }
        afterLogin()
    }

    private func afterLogin() {
        startLive()
        Task { await loadAccount() }
        Task { await loadDrafts() }
        Task { await loadPresence() }
        Task { await loadFindings() }
        Task { await loadSuggestions() }
        refreshBook()
        if pushOn { Push.register() }
    }

    func finishOnboarding() {
        onboarded = true
        UserDefaults.standard.set(true, forKey: "onboarded")
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { phase = .ready }
    }

    func logout() async {
        stopLive()
        if !fixture {
            if let t = pushToken { _ = try? await API.send("DELETE", "/api/push/device/", json: ["token": t]) }
            _ = try? await API.send("POST", "/api/auth/logout/")
        }
        resetAll()
        withAnimation { phase = .login }
    }

    /// Полный сброс: следующий аккаунт на этом телефоне не увидит ничего от прошлого.
    func resetAll() {
        API.clearCookies()
        URLCache.shared.removeAllCachedResponses()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        let tmp = FileManager.default.temporaryDirectory
        for f in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
        let d = UserDefaults.standard
        for k in ["lastEmail", "face", "lessonSubject", "extraClasses", "notifSeen"] { d.removeObject(forKey: k) }
        user = nil; state = .empty; account = nil; loaded = false
        fullHistory = [:]; historyMore = [:]; serverDrafts = [:]; typing = [:]; presence = [:]; scheduled = [:]
        lessons = []; findings = []; suggestions = []; unreadLocal = []
        lessonSubject = [:]; extraClasses = []
        faceOn = false; locked = false; lastError = nil; etag = nil
        homePath = []; messagesPath = []; clientsPath = []; paymentsPath = []; morePath = []
        sheet = nil; tab = .home
        toastTask?.cancel(); toast = nil
    }

    // MARK: - данные

    func loadState(force: Bool = false) async {
        if fixture { return }
        if loading && !force { reloadPending = true; return }
        loading = true
        defer { loading = false }
        do {
            var req = URLRequest(url: API.url("/api/state/"))
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if !force, let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let (data, resp) = try await API.session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 304 { lastError = nil; return }
            if http.statusCode == 401 { await logout(); return }
            if http.statusCode >= 400 { throw APIError(status: http.statusCode, message: API.errorText(data, status: http.statusCode)) }
            let r = try API.decode(StateResponse.self, data)
            etag = http.value(forHTTPHeaderField: "Etag")
            apply(r.state)
            if let u = r.user { user = u }
            lastError = nil
            loaded = true
        } catch {
            lastError = friendly(error)
        }
        if reloadPending {
            reloadPending = false
            Task { await loadState() }
        }
    }

    /// Дельта: изменились только эти диалоги (/api/state?conv=…).
    func loadPartial(_ ids: [String]) async {
        guard !fixture, !ids.isEmpty else { return }
        do {
            let r = try await API.get(PartialState.self, "/api/state/", query: [URLQueryItem(name: "conv", value: ids.joined(separator: ","))])
            var s = state
            for c in r.conversations ?? [] {
                if let i = s.conversations.firstIndex(where: { $0.id == c.id }) { s.conversations[i] = c }
                else if s.contacts.contains(where: { $0.id == c.contactId }) { s.conversations.append(c) }
                else { await loadState(force: true); return }
                typing[c.id] = nil
            }
            let gone = Set(r.gone ?? [])
            s.conversations.removeAll { gone.contains($0.id) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { state = s }
        } catch {
            await loadState()
        }
    }

    private func apply(_ s: AppState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { state = s }
        scheduleReminderNotifications()
    }

    func loadAccount() async {
        if fixture { return }
        account = try? await API.get(AccountInfo.self, "/api/account/")
    }

    func loadHistory(_ convId: String) async {
        guard !fixture, (conversation(convId)?.older ?? 0) > 0, fullHistory[convId] == nil else { return }
        if let r = try? await API.get(HistoryResponse.self, "/api/history/", query: [URLQueryItem(name: "c", value: convId), URLQueryItem(name: "limit", value: "80")]) {
            fullHistory[convId] = r.messages
            historyMore[convId] = r.hasMore ?? false
        }
    }

    /// Старые сообщения при прокрутке вверх.
    func loadOlder(_ convId: String) async {
        guard !fixture, historyMore[convId] == true, let first = messages(convId).first else { return }
        historyMore[convId] = false
        if let r = try? await API.get(HistoryResponse.self, "/api/history/", query: [URLQueryItem(name: "c", value: convId), URLQueryItem(name: "limit", value: "40"), URLQueryItem(name: "before", value: first.id)]) {
            fullHistory[convId] = r.messages + (fullHistory[convId] ?? [])
            historyMore[convId] = r.hasMore ?? false
        }
    }

    func loadDrafts() async {
        guard !fixture, let r = try? await API.get(DraftsResponse.self, "/api/drafts/") else { return }
        serverDrafts = r.drafts.mapValues { $0.text }
    }

    func saveDraft(_ convId: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (serverDrafts[convId] ?? "") != t else { return }
        serverDrafts[convId] = t.isEmpty ? nil : t
        guard !fixture else { return }
        Task { _ = try? await API.send("PUT", "/api/drafts/", json: ["conversationId": convId, "text": t]) }
    }

    func loadPresence() async {
        guard !fixture, let r = try? await API.get(PresenceResponse.self, "/api/presence/") else { return }
        presence = r.presence
    }

    func loadScheduled(_ convId: String) async {
        guard !fixture else { return }
        if let r = try? await API.get(ScheduledList.self, "/api/scheduled-messages/", query: [URLQueryItem(name: "conversationId", value: convId)]) {
            scheduled[convId] = r.items
        }
    }

    func loadFindings() async {
        guard !fixture, let r = try? await API.get(FindingsResponse.self, "/api/payment-findings/") else { return }
        findings = r.items
    }

    func loadSuggestions() async {
        guard !fixture, let r = try? await API.get(LinkSuggestions.self, "/api/link-suggestions/") else { return }
        suggestions = r.items
    }

    nonisolated static func monday(of d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        let start = cal.startOfDay(for: d)
        let wd = cal.component(.weekday, from: start)
        let back = (wd + 5) % 7
        return cal.date(byAdding: .day, value: -back, to: start) ?? start
    }

    func loadLessons(week: Date? = nil) async {
        if let week { lessonsWeek = Store.monday(of: week) }
        guard !fixture else { return }
        let from = lessonsWeek
        let to = Calendar.current.date(byAdding: .day, value: 7, to: from) ?? from
        do {
            let r = try await API.get(LessonsResponse.self, "/api/schedule/", query: [URLQueryItem(name: "from", value: dayStamp(from)), URLQueryItem(name: "to", value: dayStamp(to))])
            lessons = r.lessons
            lessonsError = nil
        } catch let e as APIError where e.status == 403 {
            lessons = []
            lessonsError = "Расписание ведёт владелец кабинета"
        } catch {
            lessonsError = friendly(error)
        }
    }

    // MARK: - действия кабинета

    /// Действие (/api/actions): сервер возвращает новое состояние целиком.
    @discardableResult
    func act(_ body: [String: Any], ok: String? = nil) async -> Bool {
        if fixture { if let ok { show(ok) }; return true }
        do {
            let r = try await API.post(ActionResponse.self, "/api/actions/", json: body)
            apply(r.state)
            etag = nil
            if let ok { show(ok) }
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    /// Запрос, который возвращает {state}.
    @discardableResult
    func stateCall(_ method: String, _ path: String, _ json: [String: Any], ok: String? = nil) async -> Bool {
        if fixture { if let ok { show(ok) }; return true }
        do {
            let r = try await API.call(ActionResponse.self, method, path, json: json)
            apply(r.state)
            etag = nil
            if let ok { show(ok) }
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    private func patchConv(_ id: String, _ f: (inout Conversation) -> Void) {
        guard let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        var c = state.conversations[i]
        f(&c)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { state.conversations[i] = c }
    }

    private func patchContact(_ id: String, _ f: (inout Contact) -> Void) {
        guard let i = state.contacts.firstIndex(where: { $0.id == id }) else { return }
        var c = state.contacts[i]
        f(&c)
        state.contacts[i] = c
    }

    /// Закреп, архив, «без звука» (setConvFlag). Закреп и архив исключают друг друга.
    func setFlag(_ convId: String, _ flag: String, _ on: Bool, toast text: String? = nil) {
        patchConv(convId) { c in
            var m = c.meta ?? [:]
            m[flag] = on ? (flag == "pinned" ? isoString(Date()) : "1") : nil
            if on && flag == "archived" { m["pinned"] = nil }
            if on && flag == "pinned" { m["archived"] = nil }
            c.meta = m
        }
        haptic(.medium)
        Task { await act(["type": "setConvFlag", "conversationId": convId, "flag": flag, "on": on]) }
        if let text {
            if flag == "archived" {
                show(text, undo: { [weak self] in self?.setFlag(convId, "archived", !on) })
            } else { show(text) }
        }
    }

    func markRead(_ convId: String) {
        unreadLocal.remove(convId)
        guard let c = conversation(convId), c.unread > 0 else { return }
        patchConv(convId) { $0.unread = 0 }
        Task { await act(["type": "read", "conversationId": convId]) }
    }

    /// «Пометить как новое» — только в приложении (у бэкенда нет такого действия).
    func markUnread(_ convId: String) { unreadLocal.insert(convId) }

    /// Удаление чата: клиент и его переписки уходят из кабинета (действие removeContact).
    func deleteChat(contactId: String) async {
        let ok = await act(["type": "removeContact", "contactId": contactId], ok: "Чат удалён")
        if ok, fixture {
            state.conversations.removeAll { $0.contactId == contactId }
            state.contacts.removeAll { $0.id == contactId }
        }
    }

    func block(_ contactId: String, _ on: Bool) async {
        if fixture { show(on ? "Клиент заблокирован" : "Клиент разблокирован"); return }
        do {
            let (data, _) = try await API.send("POST", "/api/actions/", json: ["type": "blockContact", "contactId": contactId, "blocked": on])
            if let r = try? JSONDecoder().decode(ActionResponse.self, from: data) { apply(r.state) }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let w = obj["warning"] as? String, !w.isEmpty {
                show(w)
            } else { show(on ? "Клиент заблокирован" : "Клиент разблокирован") }
        } catch { show(friendly(error), ok: false) }
    }

    func setFolder(_ contactId: String, _ folderId: String) {
        patchContact(contactId) { $0.folderId = folderId }
        let n = folder(folderId)?.name ?? "папку"
        Task { await act(["type": "move", "contactId": contactId, "folderId": folderId], ok: "Перенесли в «\(n)»") }
    }

    func setNote(_ contactId: String, _ note: String) {
        guard contact(contactId)?.note ?? "" != note else { return }
        patchContact(contactId) { $0.note = note }
        Task { await act(["type": "setNote", "contactId": contactId, "note": note]) }
    }

    func setAssignee(_ contactId: String, _ m: TeamMember) {
        patchContact(contactId) { $0.assignee = m.name }
        Task { await act(["type": "setAssignee", "contactId": contactId, "name": m.name, "userId": m.id], ok: "Ответственный: \(m.name)") }
    }

    func rename(_ contactId: String, _ name: String) async -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        patchContact(contactId) { $0.name = n }
        return await act(["type": "updateContact", "contactId": contactId, "name": n])
    }

    // классы (метки «класс:…»)
    var classes: [String] {
        var seen = Set<String>(), out: [String] = []
        for c in state.contacts { for k in c.classes where !seen.contains(k) { seen.insert(k); out.append(k) } }
        for k in extraClasses where !seen.contains(k) { seen.insert(k); out.append(k) }
        return out.sorted { a, b in
            let ia = Int(a.split(separator: " ").first ?? ""), ib = Int(b.split(separator: " ").first ?? "")
            if let ia, let ib, ia != ib { return ia < ib }
            if (ia == nil) != (ib == nil) { return ia != nil }
            return a < b
        }
    }

    func classCount(_ k: String) -> Int { state.contacts.filter { $0.classes.contains(k) }.count }

    func setClass(_ contactId: String, _ name: String?) {
        let old = contact(contactId)?.classes ?? []
        patchContact(contactId) { c in
            var t = (c.tags ?? []).filter { !$0.hasPrefix("класс:") }
            if let name { t.append("класс:" + name) }
            c.tags = t
        }
        Task {
            for k in old where k != name { await act(["type": "setCollection", "contactId": contactId, "kind": "class", "name": k, "on": false]) }
            if let name, !old.contains(name) { await act(["type": "setCollection", "contactId": contactId, "kind": "class", "name": name, "on": true]) }
        }
    }

    func saveClass(old: String?, new: String) {
        let n = String(new.trimmingCharacters(in: .whitespaces).prefix(22))
        guard !n.isEmpty else { return }
        if let old {
            if let i = extraClasses.firstIndex(of: old) { extraClasses[i] = n }
            for c in state.contacts where c.classes.contains(old) {
                patchContact(c.id) { x in x.tags = (x.tags ?? []).map { $0 == "класс:" + old ? "класс:" + n : $0 } }
            }
            if classCount(n) > 0 { Task { await act(["type": "renameCollection", "kind": "class", "from": old, "to": n], ok: "Сохранено") } }
            else { show("Сохранено") }
        } else {
            if !classes.contains(n) { extraClasses.append(n) }
            show("Добавлено")
        }
        UserDefaults.standard.set(extraClasses, forKey: "extraClasses")
    }

    func deleteClass(_ name: String) {
        extraClasses.removeAll { $0 == name }
        UserDefaults.standard.set(extraClasses, forKey: "extraClasses")
        let had = classCount(name) > 0
        for c in state.contacts where c.classes.contains(name) {
            patchContact(c.id) { x in x.tags = (x.tags ?? []).filter { $0 != "класс:" + name } }
        }
        if had { Task { await act(["type": "deleteCollection", "kind": "class", "name": name], ok: "Удалено") } } else { show("Удалено") }
    }

    // предметы — только в приложении
    nonisolated static func loadSubjects() -> [SubjectItem] {
        if let d = UserDefaults.standard.data(forKey: "subjects"), let s = try? JSONDecoder().decode([SubjectItem].self, from: d) { return s }
        return [SubjectItem(name: "Математика", color: "#86C7A6"), SubjectItem(name: "Физика", color: "#9CC3D3"),
                SubjectItem(name: "Пробное занятие", color: "#E2C06A"), SubjectItem(name: "Консультация", color: "#E9A37E")]
    }

    func saveSubjects() {
        if let d = try? JSONEncoder().encode(subjects) { UserDefaults.standard.set(d, forKey: "subjects") }
        UserDefaults.standard.set(lessonSubject, forKey: "lessonSubject")
    }

    func subject(of lesson: Lesson) -> SubjectItem? {
        guard let n = lessonSubject[lesson.id] else { return nil }
        return subjects.first { $0.name == n } ?? SubjectItem(name: n, color: "#9CC3D3")
    }

    // папки
    func saveFolder(id: String?, name: String, color: String) async {
        if let id {
            if let i = state.folders.firstIndex(where: { $0.id == id }) { state.folders[i].name = name; state.folders[i].color = color }
            await act(["type": "updateFolder", "id": id, "name": name, "color": color], ok: "Папка сохранена")
        } else {
            if fixture { state.folders.append(Folder(id: "f\(Int.random(in: 100...999))", key: "custom", name: name, color: color)) }
            await act(["type": "addFolder", "name": name, "color": color], ok: "Папка «\(name)» создана")
        }
    }

    func removeFolder(_ id: String) async {
        let moveTo = state.folders.first { $0.id != id }?.id
        if fixture { state.folders.removeAll { $0.id == id } }
        var body: [String: Any] = ["type": "removeFolder", "id": id]
        if let moveTo { body["moveTo"] = moveTo }
        await act(body, ok: "Папка удалена")
    }

    /// Новый порядок папок: сервер двигает по одному шагу (moveFolder ±1).
    func moveFolders(from: IndexSet, to: Int) {
        var list = state.folders
        guard let src = from.first else { return }
        list.move(fromOffsets: from, toOffset: to)
        let dst = list.firstIndex { $0.id == state.folders[src].id } ?? src
        let id = state.folders[src].id
        withAnimation { state.folders = list }
        let steps = dst - src
        guard steps != 0 else { return }
        Task {
            for _ in 0..<abs(steps) {
                if !(await act(["type": "moveFolder", "id": id, "dir": steps > 0 ? 1 : -1])) { break }
            }
            show("Порядок папок сохранён")
        }
    }

    // клиенты и оплаты
    func addClient(name: String, phone: String, network: String, folderId: String?, klass: String?) async {
        var body: [String: Any] = ["type": "addContact", "name": name, "network": network]
        if !phone.isEmpty { body["phone"] = phone }
        if let folderId { body["folderId"] = folderId }
        if let klass { body["tags"] = ["класс:" + klass] }
        if fixture {
            state.contacts.insert(Contact(id: "new\(Int.random(in: 100...999))", name: name, handle: nil, source: network, networks: [network], folderId: folderId,
                                          phone: phone, tags: klass.map { ["класс:" + $0] }, firstContactAt: isoString(Date())), at: 0)
        }
        let fname = folder(folderId)?.name ?? ""
        await act(body, ok: fname.isEmpty ? "Клиент добавлен" : "\(name): папка «\(fname)»")
    }

    func addPayment(contactId: String, productId: String?, amount: Double, paid: Bool) async {
        var body: [String: Any] = ["contactId": contactId, "productId": productId.map { $0 as Any } ?? NSNull(), "amount": Int(amount)]
        if paid { body["type"] = "pay" } else {
            body["type"] = "promise"
            body["remindAt"] = isoString(Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        }
        if fixture {
            state.deals.insert(Deal(id: "d\(Int.random(in: 100...999))", contactId: contactId, productId: productId, amount: amount,
                                    status: paid ? "paid" : "promised", date: isoString(Date()), dueAt: paid ? nil : isoString(Date().addingTimeInterval(7 * 86400))), at: 0)
        }
        await act(body, ok: "\(name(contact(contactId))): \(money(amount)), \(paid ? "оплачено" : "обещал оплатить")")
    }

    func markPaid(_ deal: Deal) {
        if let i = state.deals.firstIndex(where: { $0.id == deal.id }) { withAnimation { state.deals[i].status = "paid" } }
        haptic(.medium)
        Task { await act(["type": "updateDeal", "id": deal.id, "status": "paid"]) }
        show("\(name(contact(deal.contactId))): \(money(deal.amount)) оплачено", undo: { [weak self] in
            guard let self else { return }
            if let i = self.state.deals.firstIndex(where: { $0.id == deal.id }) { self.state.deals[i].status = deal.status }
            Task { await self.act(["type": "updateDeal", "id": deal.id, "status": deal.status]) }
        })
    }

    func remind(_ contactId: String, at: Date, text: String = "Написать клиенту") {
        Task { await act(["type": "remind", "contactId": contactId, "at": isoString(at), "text": text], ok: "Напомним \(Fmt.whenFull(at))") }
    }

    func doneReminder(_ id: String) {
        Task { await act(["type": "doneReminder", "id": id], ok: "Готово") }
    }

    func acceptFinding(_ f: PaymentFinding, _ accept: Bool) async {
        findings.removeAll { $0.id == f.id }
        if fixture { show(accept ? "Оплата записана" : "Поняли, это не оплата"); return }
        do {
            _ = try await API.send("POST", "/api/payment-findings/", json: ["messageId": f.messageId, "action": accept ? "accept" : "reject"])
            show(accept ? "Оплата записана" : "Поняли, это не оплата")
            await loadState()
        } catch { show(friendly(error), ok: false) }
    }

    func merge(keep: String, drop: String, yes: Bool) async {
        suggestions.removeAll { ($0.aId == keep && $0.bId == drop) || ($0.aId == drop && $0.bId == keep) }
        if yes {
            await act(["type": "merge", "keepId": keep, "dropId": drop], ok: "Объединили: одна карточка, две соцсети")
        } else {
            if !fixture { _ = try? await API.send("POST", "/api/link-suggestions/", json: ["aId": keep, "bId": drop]) }
            show("Поняли, это разные люди")
        }
    }

    // сотрудники
    func setRole(_ memberId: String, _ role: String) async {
        let p: [String: Any]
        switch role {
        case "Администратор": p = ["channels": "all", "onlyAssigned": false, "canPay": true, "canExport": true, "seeMoney": true]
        case "Только просмотр": p = ["channels": "all", "onlyAssigned": true, "canPay": false, "canExport": false, "seeMoney": false]
        default: p = ["channels": "all", "onlyAssigned": false, "canPay": true, "canExport": false, "seeMoney": true]
        }
        await stateCall("PUT", "/api/team/\(memberId)/permissions/", p, ok: "Роль сохранена")
    }

    func removeMember(_ id: String) async {
        if fixture { state.team.removeAll { $0.id == id } }
        await stateCall("DELETE", "/api/team/\(id)/", [:], ok: "Доступ закрыт")
    }

    // MARK: - сообщения

    func send(_ convId: String, text: String, attachments: [Attachment] = [], replyTo: String? = nil) async -> Bool {
        let tmp = "tmp-" + UUID().uuidString
        var m = Message(id: tmp, dir: "out", text: text, at: isoString(Date()), attachments: attachments.isEmpty ? nil : attachments,
                        replyTo: replyTo.flatMap { rid in messages(convId).first { $0.id == rid }.map { ReplyRef(id: rid, text: $0.preview, dir: $0.dir) } })
        m.pending = true
        patchConv(convId) { $0.messages.append(m) }
        if fixture || offline {
            if offline { show("Отправим, когда появится интернет") }
            if fixture { patchConv(convId) { c in if let i = c.messages.firstIndex(where: { $0.id == tmp }) { c.messages[i].pending = nil } } }
            return true
        }
        var json: [String: Any] = ["conversationId": convId, "text": text]
        if !attachments.isEmpty {
            json["attachments"] = attachments.compactMap { a -> [String: Any]? in
                guard let id = a.mediaId else { return nil }
                return a.round == true ? ["mediaId": id, "round": true] : ["mediaId": id]
            }
        }
        if let replyTo { json["replyTo"] = replyTo }
        do {
            let r = try await API.post(ActionResponse.self, "/api/messages/send/", json: json)
            apply(r.state)
            etag = nil
            return true
        } catch {
            patchConv(convId) { $0.messages.removeAll { $0.id == tmp } }
            show(friendly(error), ok: false)
            return false
        }
    }

    func react(_ convId: String, _ m: Message, _ emoji: String?) {
        patchConv(convId) { c in
            if let i = c.messages.firstIndex(where: { $0.id == m.id }) {
                var rx = (c.messages[i].reactions ?? []).filter { !$0.mine }
                if let emoji { rx.append(Reaction(emoji: emoji, mine: true)) }
                c.messages[i].reactions = rx
            }
        }
        if var full = fullHistory[convId], let i = full.firstIndex(where: { $0.id == m.id }) {
            var rx = (full[i].reactions ?? []).filter { !$0.mine }
            if let emoji { rx.append(Reaction(emoji: emoji, mine: true)) }
            full[i].reactions = rx
            fullHistory[convId] = full
        }
        haptic(.medium)
        guard !fixture else { return }
        Task {
            do {
                let r = try await API.post(ActionResponse.self, "/api/messages/react/", json: ["messageId": m.id, "emoji": emoji.map { $0 as Any } ?? NSNull()])
                apply(r.state)
            } catch { show(friendly(error), ok: false) }
        }
    }

    func pinMessage(_ convId: String, _ m: Message, _ on: Bool) {
        patchConv(convId) { c in
            var pins = c.pins.filter { $0 != m.id }
            if on { pins.insert(m.id, at: 0) }
            var meta = c.meta ?? [:]
            meta["pins"] = pins.joined(separator: ",")
            c.meta = meta
        }
        show(on ? "Сообщение закреплено" : "Сообщение откреплено")
        guard !fixture else { return }
        Task {
            do {
                let r = try await API.post(ActionResponse.self, "/api/messages/pin/", json: ["messageId": m.id, "on": on])
                apply(r.state)
            } catch { show(friendly(error), ok: false) }
        }
    }

    func editMessage(_ convId: String, _ m: Message, _ text: String) async {
        patchConv(convId) { c in if let i = c.messages.firstIndex(where: { $0.id == m.id }) { c.messages[i].text = text; c.messages[i].edited = true } }
        if fixture { show("Сообщение изменено"); return }
        do {
            let r = try await API.post(ActionResponse.self, "/api/messages/edit/", json: ["messageId": m.id, "text": text])
            apply(r.state)
            show("Сообщение изменено")
        } catch { show(friendly(error), ok: false) }
    }

    func deleteMessages(_ convId: String, _ ids: [String], everyone: Bool) async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            patchConv(convId) { $0.messages.removeAll { ids.contains($0.id) } }
            if var f = fullHistory[convId] { f.removeAll { ids.contains($0.id) }; fullHistory[convId] = f }
        }
        show(ids.count > 1 ? "Удалено сообщений: \(ids.count)" : "Сообщение удалено")
        guard !fixture else { return }
        for id in ids {
            do {
                let r = try await API.post(ActionResponse.self, "/api/messages/delete/", json: ["messageId": id, "mode": everyone ? "everyone" : "local"])
                apply(r.state)
            } catch { show(friendly(error), ok: false); break }
        }
    }

    /// Пересылка: текст и вложения (по mediaId) уходят в выбранный диалог.
    func forward(_ from: String, _ ids: [String], to: String) async {
        let list = messages(from).filter { ids.contains($0.id) }
        var ok = true
        for m in list {
            let atts = (m.attachments ?? []).filter { $0.mediaId != nil }
            if m.body.isEmpty && atts.isEmpty { continue }
            if !(await send(to, text: m.body, attachments: atts)) { ok = false; break }
        }
        if ok { show("Переслано: \(name(contact(conversation(to)?.contactId)))") }
    }

    func schedule(_ convId: String, text: String, at: Date, replyTo: String? = nil) async -> Bool {
        if fixture {
            scheduled[convId, default: []].append(ScheduledMessage(id: UUID().uuidString, conversationId: convId, text: text, sendAt: isoString(at), status: "pending", error: nil))
            show("Отправим \(Fmt.whenFull(at))")
            return true
        }
        var json: [String: Any] = ["conversationId": convId, "text": text, "sendAt": isoLocal(at)]
        if let replyTo { json["replyTo"] = replyTo }
        do {
            let (data, _) = try await API.send("POST", "/api/scheduled-messages/", json: json)
            if let r = try? JSONDecoder().decode(ScheduledList.self, from: data) { scheduled[convId] = r.items }
            show("Отправим \(Fmt.whenFull(at))")
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    func cancelScheduled(_ s: ScheduledMessage) async {
        scheduled[s.conversationId]?.removeAll { $0.id == s.id }
        guard !fixture else { show("Отправка отменена"); return }
        do {
            let (data, _) = try await API.send("DELETE", "/api/scheduled-messages/\(s.id)/")
            if let r = try? JSONDecoder().decode(ScheduledList.self, from: data) { scheduled[s.conversationId] = r.items }
            show("Отправка отменена")
        } catch { show(friendly(error), ok: false) }
    }

    func sendScheduledNow(_ s: ScheduledMessage) async {
        guard !fixture else { show("Отправлено"); scheduled[s.conversationId]?.removeAll { $0.id == s.id }; return }
        do {
            let (data, _) = try await API.send("PATCH", "/api/scheduled-messages/\(s.id)/", json: ["sendAt": isoLocal(Date().addingTimeInterval(5))])
            if let r = try? JSONDecoder().decode(ScheduledList.self, from: data) { scheduled[s.conversationId] = r.items }
            show("Отправим сейчас")
        } catch { show(friendly(error), ok: false) }
    }

    func search(_ q: String) async -> [SearchItem] {
        guard !fixture, q.count >= 2 else { return [] }
        return (try? await API.get(SearchResponse.self, "/api/search/", query: [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "30")]).items) ?? []
    }

    // MARK: - расписание

    func addLesson(convId: String, start: Date, minutes: Int, weeks: Int, subject: String) async -> Bool {
        if fixture {
            let id = "l\(Int.random(in: 1000...9999))"
            lessons.append(Lesson(id: id, conversationId: convId, contactId: conversation(convId)?.contactId ?? "", startsAt: isoString(start),
                                  endsAt: isoString(start.addingTimeInterval(Double(minutes) * 60)), status: "planned", seriesId: nil))
            lessonSubject[id] = subject
            show("Занятие в \(Fmt.hm(start)) добавлено")
            return true
        }
        var json: [String: Any] = ["action": "add", "conversationId": convId, "start": localStamp(start), "duration": minutes]
        if weeks > 1 { json["repeat"] = ["weeks": weeks] }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: json)
            let before = Set(lessons.map(\.id))
            await loadLessons()
            for l in lessons where !before.contains(l.id) && l.conversationId == convId { lessonSubject[l.id] = subject }
            saveSubjects()
            show("Занятие в \(Fmt.hm(start)) добавлено")
            return true
        } catch { show(friendly(error), ok: false); return false }
    }

    func moveLesson(_ l: Lesson, start: Date, minutes: Int, subject: String) async -> Bool {
        lessonSubject[l.id] = subject
        saveSubjects()
        if fixture {
            if let i = lessons.firstIndex(of: l) {
                lessons[i] = Lesson(id: l.id, conversationId: l.conversationId, contactId: l.contactId, startsAt: isoString(start),
                                    endsAt: isoString(start.addingTimeInterval(Double(minutes) * 60)), status: l.status, seriesId: l.seriesId)
            }
            show("Занятие изменено")
            return true
        }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: ["action": "move", "id": l.id, "start": localStamp(start), "duration": minutes])
            await loadLessons()
            show("Занятие изменено")
            return true
        } catch { show(friendly(error), ok: false); return false }
    }

    func deleteLesson(_ l: Lesson, following: Bool) async {
        withAnimation { lessons.removeAll { $0.id == l.id || (following && l.seriesId != nil && $0.seriesId == l.seriesId && $0.start >= l.start) } }
        if fixture { show("Занятие удалено"); return }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: ["action": "delete", "id": l.id, "following": following])
            show(following ? "Занятия удалены" : "Занятие удалено")
            await loadLessons()
        } catch { show(friendly(error), ok: false) }
    }

    func lessons(on day: Date) -> [Lesson] {
        lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: day) && $0.status != "cancelled" }.sorted { $0.start < $1.start }
    }

    // MARK: - живые обновления

    func startLive() {
        guard !fixture else { return }
        stopLive()
        eventsTask = Task { [weak self] in await self?.eventsLoop() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.loadState()
            }
        }
    }

    func stopLive() {
        eventsTask?.cancel(); eventsTask = nil
        pollTask?.cancel(); pollTask = nil
    }

    private func eventsLoop() async {
        while !Task.isCancelled {
            do {
                var req = URLRequest(url: API.url("/api/events/"))
                req.timeoutInterval = 600
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, resp) = try await API.session.bytes(for: req)
                if (resp as? HTTPURLResponse)?.statusCode == 200 {
                    var event = "message"
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            handleEvent(event, String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            event = "message"
                        }
                    }
                }
            } catch {}
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func handleEvent(_ event: String, _ data: String) {
        let obj = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any]
        switch event {
        case "delta":
            let ids = (obj?["c"] as? [String]) ?? []
            Task { await loadPartial(ids) }
        case "typing":
            guard let c = obj?["c"] as? String else { return }
            typing[c] = TypingInfo(at: Date(), kind: obj?["k"] as? String ?? "typing")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_200_000_000)
                if let t = self?.typing[c], Date().timeIntervalSince(t.at) >= 5 { self?.typing[c] = nil }
            }
        case "presence":
            guard let c = obj?["c"] as? String else { return }
            presence[c] = Presence(online: obj?["online"] as? Bool, lastSeen: obj?["lastSeen"] as? String)
        default:
            if data.contains("changed") { Task { await loadState() } }
        }
    }

    /// Подпись под именем в шапке чата: «печатает…», «в сети», «был(а) в сети в 14:05».
    func statusLine(_ convId: String) -> String? {
        if let t = typing[convId], Date().timeIntervalSince(t.at) < 5 {
            return t.kind == "recording" ? "записывает голосовое…" : "печатает…"
        }
        guard let p = presence[convId] else { return nil }
        if p.online == true { return "в сети" }
        if let d = parseISO(p.lastSeen) { return "был(а) в сети " + Fmt.whenFull(d) }
        return nil
    }

    // MARK: - аккаунт и ИИ

    /// Удаление аккаунта (App Store 5.1.1(v)): POST /api/account/delete {confirm:true}.
    /// Владелец удаляет кабинет целиком, сотрудник — только свою учётку.
    func deleteAccount() async -> Bool {
        if fixture { show("В демо удаление отключено"); return false }
        do {
            if let t = pushToken { _ = try? await API.send("DELETE", "/api/push/device/", json: ["token": t]) }
            _ = try await API.send("POST", "/api/account/delete/", json: ["confirm": true])
            stopLive()
            resetAll()
            withAnimation { phase = .login }
            show(user?.isOwner == false ? "Учётная запись удалена" : "Аккаунт и кабинет удалены")
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    var translateOn: Bool { state.workspace?.translate ?? false }

    /// Перевод сообщений через ИИ-сервисы — настройка кабинета (PATCH /api/workspace {translate}), только владелец.
    func setTranslate(_ on: Bool) async {
        let old = state.workspace
        state.workspace = WorkspaceInfo(currency: old?.currency, translate: on)
        UserDefaults.standard.set(on, forKey: "aiConsent")
        if fixture { show(on ? "Перевод через ИИ включён" : "Перевод через ИИ выключен"); return }
        if !(await stateCall("PATCH", "/api/workspace/", ["translate": on], ok: on ? "Перевод через ИИ включён" : "Перевод через ИИ выключен")) {
            state.workspace = old
        }
    }

    // MARK: - настройки

    func setTheme(_ t: ThemeMode) {
        withAnimation(.easeInOut(duration: 0.3)) { theme = t }
        UserDefaults.standard.set(t.rawValue, forKey: "theme")
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func setContactsOn(_ on: Bool) {
        if on && bookAccess != true {
            PhoneBook.request { [weak self] granted in
                guard let self else { return }
                self.bookAccess = granted
                self.contactsOn = granted
                UserDefaults.standard.set(granted, forKey: "contactsOn")
                if granted { self.refreshBook(); self.show("Имена берём из контактов") } else { self.show("Нет доступа к контактам. Разрешите в настройках iPhone", ok: false) }
            }
            return
        }
        contactsOn = on
        UserDefaults.standard.set(on, forKey: "contactsOn")
    }

    func refreshBook() {
        if fixture { return }
        bookAccess = PhoneBook.authorized
        guard bookAccess == true else { return }
        Task.detached {
            let names = PhoneBook.loadNames()
            await MainActor.run { self.bookNames = names }
        }
    }

    /// «Добавить в контакты»: имя и номер (или ссылка на соцсеть) попадают в телефонную книгу.
    func addToBook(_ c: Contact) {
        let save = { [weak self] in
            guard let self else { return }
            let conv = self.mainConversation(of: c.id)
            let ok = self.fixture ? true : PhoneBook.save(name: self.name(c), phone: self.phoneOf(c), network: conv?.network ?? c.source, handle: c.handle)
            if ok {
                if let p = self.phoneOf(c) { self.bookNames[PhoneBook.key(p)] = self.name(c) }
                self.show("Добавили в контакты телефона")
            } else { self.show("Не получилось сохранить контакт", ok: false) }
        }
        if fixture || bookAccess == true { save(); return }
        PhoneBook.request { [weak self] granted in
            self?.bookAccess = granted
            if granted { save() } else { self?.show("Без доступа к контактам добавить не получится", ok: false) }
        }
    }

    func setPush(_ on: Bool) {
        pushOn = on
        UserDefaults.standard.set(on, forKey: "push")
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in
                    if granted {
                        Push.register()
                        self.scheduleReminderNotifications()
                    } else {
                        self.pushOn = false
                        UserDefaults.standard.set(false, forKey: "push")
                        self.show("Уведомления выключены в настройках iPhone", ok: false)
                    }
                }
            }
        } else if let t = pushToken, !fixture {
            Task { _ = try? await API.send("DELETE", "/api/push/device/", json: ["token": t]) }
        }
    }

    /// Токен APNs получен: регистрируем устройство в кабинете (POST /api/push/device).
    func registerDevice(_ token: String) {
        pushToken = token
        UserDefaults.standard.set(token, forKey: "pushToken")
        guard !fixture, phase == .ready || phase == .onboarding, pushOn else { return }
        Task { _ = try? await API.send("POST", "/api/push/device/", json: ["platform": "ios", "token": token]) }
    }

    func setReminders(_ on: Bool) {
        remindersOn = on
        UserDefaults.standard.set(on, forKey: "reminders")
        if on { scheduleReminderNotifications() } else { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    }

    func setFace(_ on: Bool) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            show("На этом телефоне нет Face ID или код-пароля", ok: false)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: on ? "Включить вход по Face ID" : "Выключить вход по Face ID") { ok, _ in
            Task { @MainActor in
                if ok { self.faceOn = on; UserDefaults.standard.set(on, forKey: "face") }
                else { self.show("Не подтверждено, настройка не изменилась", ok: false) }
            }
        }
    }

    /// Напоминания кабинета → локальные уведомления.
    func scheduleReminderNotifications() {
        guard remindersOn, !fixture else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let upcoming = openReminders.filter { $0.date > Date() }.sorted { $0.date < $1.date }.prefix(60)
        for r in upcoming {
            let content = UNMutableNotificationContent()
            content.title = name(contact(r.contactId))
            content.body = r.text.isEmpty ? "Написать клиенту" : r.text
            content.sound = .default
            if let conv = mainConversation(of: r.contactId) { content.userInfo = ["url": "/messages?c=\(conv.id)"] }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.date)
            center.add(UNNotificationRequest(identifier: "rem-" + r.id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    // MARK: - уведомления (экран)

    var notes: [NoteItem] {
        var out: [NoteItem] = []
        let dayAgo = Date().addingTimeInterval(-86400)
        for c in liveChats where unread(c) > 0 && !c.isMuted {
            if let m = c.messages.last(where: { !$0.isOut }) {
                out.append(NoteItem(id: "m" + c.id, kind: .msg, title: name(contact(c.contactId)), sub: m.preview, at: m.date, convId: c.id))
            }
        }
        for d in state.deals where d.isLate {
            out.append(NoteItem(id: "p" + d.id, kind: .pay, title: "Просрочена оплата",
                                sub: "\(name(contact(d.contactId))) · \(money(d.amount)), ждали \(Fmt.day(d.due ?? d.day))",
                                at: d.due ?? d.day, convId: mainConversation(of: d.contactId)?.id))
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        for r in openReminders where r.date < end {
            out.append(NoteItem(id: "r" + r.id, kind: .rem, title: "Напоминание", sub: "\(name(contact(r.contactId))): \(r.text)",
                                at: min(r.date, Date()), convId: mainConversation(of: r.contactId)?.id))
        }
        for l in lessons(on: Date()) where l.end > Date() {
            let s = subject(of: l)?.name ?? "занятие"
            out.append(NoteItem(id: "l" + l.id, kind: .les, title: "Занятие в \(Fmt.hm(l.start))",
                                sub: "\(name(contact(l.contactId))) · \(s.lowercased()), \(l.minutes) мин", at: Calendar.current.startOfDay(for: Date()), convId: nil))
        }
        return out.filter { $0.at > dayAgo || $0.kind != .msg }.sorted { $0.at > $1.at }
    }

    var newNotes: Int { notes.filter { $0.at > notifSeen }.count }

    func seeNotes() {
        notifSeen = Date()
        UserDefaults.standard.set(notifSeen.timeIntervalSince1970, forKey: "notifSeen")
    }

    // MARK: - тосты и навигация

    func show(_ text: String, ok: Bool = true, undo: (() -> Void)? = nil) {
        toastUndo = undo
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { toast = Toast(text: text, ok: ok, undo: undo != nil) }
        if !ok { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.22)) { self?.toast = nil }
            self?.toastUndo = nil
        }
    }

    func runUndo() {
        let u = toastUndo
        toastUndo = nil
        withAnimation { toast = nil }
        u?()
    }

    var path: [Route] {
        get {
            switch tab {
            case .home: return homePath
            case .messages: return messagesPath
            case .clients: return clientsPath
            case .payments: return paymentsPath
            case .more: return morePath
            }
        }
        set {
            switch tab {
            case .home: homePath = newValue
            case .messages: messagesPath = newValue
            case .clients: clientsPath = newValue
            case .payments: paymentsPath = newValue
            case .more: morePath = newValue
            }
        }
    }

    func open(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }

    func openChat(_ convId: String) {
        markRead(convId)
        if case .chat(let id)? = path.last, id == convId { return }
        path.append(.chat(convId))
    }

    func openChat(contactId: String) {
        if let c = mainConversation(of: contactId) { openChat(c.id) } else { show("С этим клиентом ещё нет переписки") }
    }

    /// Нажатие на push: url вида /messages?c=<id диалога> (или /lk/messages?c=…).
    func openURL(_ s: String) {
        guard let comps = URLComponents(string: s), let c = comps.queryItems?.first(where: { $0.name == "c" })?.value else { return }
        tab = .messages
        messagesPath = []
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if self.conversation(c) == nil { await self.loadState(force: true) }
            self.openChat(c)
        }
    }

    // MARK: - сводка

    struct Stats {
        var leads = 0
        var paid = 0
        var revenue: Double = 0
        var waiting = 0
        var remind = 0
        var bars: [Int] = Array(repeating: 0, count: 14)
        var barDays: [Int] = []
    }

    func stats(days: Int) -> Stats {
        var s = Stats()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let leadEvents = state.events.filter { $0.type == "lead_created" }
        s.leads = leadEvents.isEmpty ? state.contacts.filter { $0.first >= start }.count : leadEvents.filter { $0.date >= start }.count
        let paid = state.deals.filter { $0.status == "paid" && $0.day >= start }
        s.paid = paid.count
        s.revenue = paid.reduce(0) { $0 + $1.amount }
        s.waiting = liveChats.filter { waiting($0) && !$0.isGroup }.count
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        s.remind = openReminders.filter { $0.date < end }.count + state.deals.filter { $0.isLate }.count
        let inEvents = state.events.filter { $0.type == "message_in" }
        for i in 0..<14 {
            let d0 = cal.date(byAdding: .day, value: i - 13, to: today) ?? today
            let d1 = cal.date(byAdding: .day, value: 1, to: d0) ?? d0
            if inEvents.isEmpty {
                var n = 0
                for conv in state.conversations { n += conv.messages.filter { m in !m.isOut && m.date >= d0 && m.date < d1 }.count }
                s.bars[i] = n
            } else {
                s.bars[i] = inEvents.filter { $0.date >= d0 && $0.date < d1 }.count
            }
            s.barDays.append(cal.component(.day, from: d0))
        }
        return s
    }

    struct Todo: Identifiable {
        let id: String
        let contactId: String
        let text: String
        let due: Date
        let late: Bool
        let reminderId: String?
    }

    var todos: [Todo] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        var out = openReminders.filter { $0.date < end }.map {
            Todo(id: "r" + $0.id, contactId: $0.contactId, text: $0.text.isEmpty ? "Написать клиенту" : $0.text, due: $0.date,
                 late: $0.date < cal.startOfDay(for: Date()), reminderId: $0.id)
        }
        for d in state.deals where d.isLate && !out.contains(where: { $0.contactId == d.contactId }) {
            out.append(Todo(id: "d" + d.id, contactId: d.contactId, text: "Напомнить об оплате", due: d.due ?? d.day, late: true, reminderId: nil))
        }
        return out.sorted { $0.due < $1.due }
    }
}
