import Foundation
import SwiftUI
import UserNotifications

/// Новые функции бэкенда (ноябрь 2026): закрепы, архив, «без звука», реакции, закреплённые сообщения,
/// «печатает» и «в сети», черновики, отложенная отправка, поиск, расписание, классы и группы,
/// профиль ИИ, найденные оплаты, «тот же человек», телефонная книга, push.
extension Store {

    // MARK: - запуск и живые события

    func afterLogin() {
        Task { await loadAccount() }
        Task { await loadDrafts() }
        Task { await loadPresence() }
        Task { await loadFindings() }
        Task { await loadSuggestions() }
        Task { await loadProfiles() }
        refreshBook()
        if pushOn { Push.register() }
    }

    /// SSE: delta — изменились только диалоги, typing — печатает/записывает, presence — в сети.
    func handleEvent(_ event: String, _ data: String) {
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

    /// Дельта: обновить только эти диалоги (/api/state?conv=…), без перечитывания всего кабинета.
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

    /// Подпись под именем в шапке чата.
    func statusLine(_ convId: String) -> String? {
        if let t = typing[convId], Date().timeIntervalSince(t.at) < 5 {
            return t.kind == "recording" ? "записывает голосовое…" : "печатает…"
        }
        guard let p = presence[convId] else { return nil }
        if p.online == true { return "в сети" }
        if let d = parseISO(p.lastSeen) { return "был(а) в сети " + Fmt.whenFull(d) }
        return nil
    }

    func loadPresence() async {
        guard !fixture, let r = try? await API.get(PresenceResponse.self, "/api/presence/") else { return }
        presence = r.presence
    }

    // MARK: - черновики на сервере

    func loadDrafts() async {
        guard !fixture, let r = try? await API.get(DraftsResponse.self, "/api/drafts/") else { return }
        serverDrafts = r.drafts.mapValues { $0.text }
        for (k, v) in serverDrafts where (drafts[k] ?? "").isEmpty { drafts[k] = v }
    }

    func saveDraft(_ convId: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[convId] = text
        guard (serverDrafts[convId] ?? "") != t else { return }
        serverDrafts[convId] = t.isEmpty ? nil : t
        guard !fixture else { return }
        Task { _ = try? await API.send("PUT", "/api/drafts/", json: ["conversationId": convId, "text": t]) }
    }

    // MARK: - закреп, архив, «без звука», удаление чата

    /// setConvFlag: pinned / archived / muted. Закреп и архив исключают друг друга.
    func setFlag(_ convId: String, _ flag: String, _ on: Bool) {
        if let i = state.conversations.firstIndex(where: { $0.id == convId }) {
            var m = state.conversations[i].meta ?? [:]
            m[flag] = on ? (flag == "pinned" ? isoString(Date()) : "1") : nil
            if on && flag == "archived" { m["pinned"] = nil }
            if on && flag == "pinned" { m["archived"] = nil }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.conversations[i].meta = m }
        }
        haptic(.medium)
        guard !fixture else { return }
        Task { await act(["type": "setConvFlag", "conversationId": convId, "flag": flag, "on": on]) }
    }

    func toggleMute(_ convId: String) {
        let on = !(conversation(convId)?.isMuted ?? false)
        setFlag(convId, "muted", on)
        show(on ? "Без звука" : "Уведомления включены", undo: { [weak self] in self?.setFlag(convId, "muted", !on) })
    }

    func toggleArchive(_ convId: String) {
        let on = !(conversation(convId)?.isArchived ?? false)
        setFlag(convId, "archived", on)
        show(on ? "В архиве. Потяни список вниз, чтобы открыть архив" : "Чат вернулся из архива", undo: { [weak self] in self?.setFlag(convId, "archived", !on) })
    }

    /// Удалить чат: клиент и переписка уходят из кабинета (removeContact).
    /// everyone — сперва удалить сообщения и у собеседника (Telegram).
    func deleteChat(_ convId: String, everyone: Bool) async {
        guard let c = conversation(convId) else { return }
        if everyone && !fixture {
            for m in messages(convId) where m.externalId != nil {
                _ = try? await API.send("POST", "/api/messages/delete/", json: ["messageId": m.id, "mode": "everyone"])
            }
        }
        if fixture {
            withAnimation { state.conversations.removeAll { $0.id == convId } }
            show(everyone ? "Удалено у вас и у собеседника" : "Чат удалён")
            return
        }
        await act(["type": "removeContact", "contactId": c.contactId], ok: everyone ? "Удалено у вас и у собеседника" : "Чат удалён")
    }

    func block(_ contactId: String, _ on: Bool) async {
        if fixture { show(on ? "Клиент заблокирован" : "Клиент разблокирован"); return }
        do {
            let (data, _) = try await API.send("POST", "/api/actions/", json: ["type": "blockContact", "contactId": contactId, "blocked": on])
            if let r = try? JSONDecoder().decode(ActionResponse.self, from: data) { state = r.state }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let w = obj["warning"] as? String, !w.isEmpty {
                show(w)
            } else { show(on ? "Клиент заблокирован" : "Клиент разблокирован") }
        } catch { show(friendly(error), ok: false) }
    }

    // MARK: - сообщения: реакции, закреп, превью ссылок, поиск

    private func patchMessage(_ convId: String, _ id: String, _ f: (inout Message) -> Void) {
        if let i = state.conversations.firstIndex(where: { $0.id == convId }),
           let j = state.conversations[i].messages.firstIndex(where: { $0.id == id }) {
            f(&state.conversations[i].messages[j])
        }
        if var full = fullHistory[convId], let j = full.firstIndex(where: { $0.id == id }) {
            f(&full[j])
            fullHistory[convId] = full
        }
    }

    /// Реакция (только Telegram и WhatsApp): одна наша на сообщение, повтор снимает.
    func react(_ convId: String, _ m: Message, _ emoji: String?) {
        // та же реакция уже стоит — повторное нажатие снимает её (иначе Telegram отвечает MESSAGE_NOT_MODIFIED)
        let current: String? = messages(convId).first { $0.id == m.id }?.reactions?.first { $0.mine }?.emoji
        var target: String? = emoji
        if let e = emoji, e == current { target = nil }
        if target == nil && current == nil { return }
        guard !reacting.contains(m.id) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            patchMessage(convId, m.id) { msg in
                var rx = (msg.reactions ?? []).filter { !$0.mine }
                if let target { rx.append(Reaction(emoji: target, mine: true)) }
                msg.reactions = rx
            }
        }
        haptic(.medium)
        guard !fixture else { return }
        reacting.insert(m.id)
        Task {
            defer { reacting.remove(m.id) }
            do {
                let r = try await API.post(ActionResponse.self, "/api/messages/react/", json: ["messageId": m.id, "emoji": target.map { $0 as Any } ?? NSNull()])
                state = r.state
                etag = nil
            } catch {
                // сырой текст ошибки не показываем; вид реакции возвращаем с сервера
                show("Не получилось поставить реакцию. Попробуй ещё раз", ok: false)
                await loadState(force: true)
            }
        }
    }

    /// Закрепить сообщение в чате (плашка сверху). В Telegram по QR — и в самом мессенджере.
    /// both: закрепить и у собеседника (в Telegram — без pm_oneside); false — только у себя.
    func pinMessage(_ convId: String, _ m: Message, _ on: Bool, both: Bool = true) {
        if let i = state.conversations.firstIndex(where: { $0.id == convId }) {
            var pins = state.conversations[i].pins.filter { $0 != m.id }
            if on { pins.insert(m.id, at: 0) }
            var meta = state.conversations[i].meta ?? [:]
            meta["pins"] = pins.joined(separator: ",")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.conversations[i].meta = meta }
        }
        show(on ? (both ? "Закреплено у вас и у собеседника" : "Закреплено у вас") : "Сообщение откреплено")
        guard !fixture else { return }
        Task {
            do {
                let r = try await API.post(ActionResponse.self, "/api/messages/pin/", json: ["messageId": m.id, "on": on, "both": both])
                state = r.state
                etag = nil
            } catch { show(friendly(error), ok: false) }
        }
    }

    func linkPreview(_ url: URL) async -> LinkPreview? {
        let key = url.absoluteString
        if let p = linkPreviews[key] { return p }
        guard !fixture else { return nil }
        guard let r = try? await API.get(LinkPreviewResponse.self, "/api/link-preview/", query: [URLQueryItem(name: "url", value: key)]),
              let p = r.preview else { return nil }
        linkPreviews[key] = p
        return p
    }

    func search(_ q: String) async -> [SearchItem] {
        guard !fixture, q.count >= 2 else { return [] }
        return (try? await API.get(SearchResponse.self, "/api/search/", query: [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "30")]).items) ?? []
    }

    // MARK: - отложенная отправка

    func loadScheduled(_ convId: String) async {
        guard !fixture else { return }
        if let r = try? await API.get(ScheduledList.self, "/api/scheduled-messages/", query: [URLQueryItem(name: "conversationId", value: convId)]) {
            scheduled[convId] = r.items
        }
    }

    @discardableResult
    func schedule(_ convId: String, text: String, at: Date, replyTo: String? = nil) async -> Bool {
        if fixture {
            scheduled[convId, default: []].append(ScheduledMessage(id: UUID().uuidString, conversationId: convId, text: text, sendAt: isoString(at), status: "pending", error: nil))
            show("Отправлю " + Fmt.whenFull(at))
            return true
        }
        var json: [String: Any] = ["conversationId": convId, "text": text, "sendAt": isoLocal(at)]
        if let replyTo { json["replyTo"] = replyTo }
        do {
            let (data, _) = try await API.send("POST", "/api/scheduled-messages/", json: json)
            if let r = try? JSONDecoder().decode(ScheduledList.self, from: data) { scheduled[convId] = r.items }
            show("Отправлю " + Fmt.whenFull(at))
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    func cancelScheduled(_ s: ScheduledMessage) async {
        withAnimation { scheduled[s.conversationId]?.removeAll { $0.id == s.id } }
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
            show("Отправляю сейчас")
        } catch { show(friendly(error), ok: false) }
    }

    // MARK: - профиль ИИ, найденные оплаты, «тот же человек»

    func loadProfiles() async {
        guard !fixture, let r = try? await API.get(AIProfiles.self, "/api/profiles/") else { return }
        aiProfiles = r.profiles
    }

    func loadFindings() async {
        guard !fixture, let r = try? await API.get(FindingsResponse.self, "/api/payment-findings/") else { return }
        findings = r.items
    }

    func acceptFinding(_ f: PaymentFinding, _ accept: Bool) async {
        withAnimation { findings.removeAll { $0.id == f.id } }
        if fixture { show(accept ? "Оплата записана" : "Понял, это не оплата"); return }
        do {
            _ = try await API.send("POST", "/api/payment-findings/", json: ["messageId": f.messageId, "action": accept ? "accept" : "reject"])
            show(accept ? "Оплата записана" : "Понял, это не оплата")
            await loadState(force: true)
        } catch { show(friendly(error), ok: false) }
    }

    func loadSuggestions() async {
        guard !fixture, let r = try? await API.get(LinkSuggestions.self, "/api/link-suggestions/") else { return }
        suggestions = r.items
    }

    func merge(keep: String, drop: String, yes: Bool) async {
        withAnimation { suggestions.removeAll { ($0.aId == keep && $0.bId == drop) || ($0.aId == drop && $0.bId == keep) } }
        if yes {
            await act(["type": "merge", "keepId": keep, "dropId": drop], ok: "Объединено: одна карточка, две соцсети")
        } else {
            if !fixture { _ = try? await API.send("POST", "/api/link-suggestions/", json: ["aId": keep, "bId": drop]) }
            show("Понял, это разные люди")
        }
    }

    // MARK: - классы и группы (метки «класс:9», «группа:9 класс»)

    var classes: [String] { collections("class") }
    var groups: [String] { collections("group") }

    private func collections(_ kind: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for c in state.contacts {
            for k in (kind == "class" ? c.classes : c.groups) where !seen.contains(k) { seen.insert(k); out.append(k) }
        }
        if kind == "class" { for k in extraClasses where !seen.contains(k) { seen.insert(k); out.append(k) } }
        return out.sorted { a, b in
            let ia = Int(a.split(separator: " ").first ?? ""), ib = Int(b.split(separator: " ").first ?? "")
            if let ia, let ib, ia != ib { return ia < ib }
            if (ia == nil) != (ib == nil) { return ia != nil }
            return a < b
        }
    }

    func members(_ kind: String, _ name: String) -> Int {
        state.contacts.filter { (kind == "class" ? $0.classes : $0.groups).contains(name) }.count
    }

    /// Клиент подходит под фильтр класса/группы чатов и клиентов.
    func matchesCollection(_ c: Contact?) -> Bool {
        guard collectionFilter != "all" else { return true }
        guard let c else { return false }
        if collectionFilter.hasPrefix("class:") { return c.classes.contains(String(collectionFilter.dropFirst(6))) }
        if collectionFilter.hasPrefix("group:") { return c.groups.contains(String(collectionFilter.dropFirst(6))) }
        return true
    }

    func setCollection(_ contactId: String, kind: String, name: String, on: Bool) {
        let prefix = kind == "class" ? "класс:" : "группа:"
        if let i = state.contacts.firstIndex(where: { $0.id == contactId }) {
            var t = state.contacts[i].tags ?? []
            t.removeAll { $0 == prefix + name }
            if on { t.append(prefix + name) }
            let old = state.contacts[i]
            state.contacts[i] = Contact(id: old.id, name: old.name, handle: old.handle, hue: old.hue, source: old.source, networks: old.networks,
                                        folderId: old.folderId, assignee: old.assignee, note: old.note, phone: old.phone, email: old.email,
                                        tags: t, lang: old.lang, avatar: old.avatar, firstContactAt: old.firstContactAt)
        }
        Task { await act(["type": "setCollection", "contactId": contactId, "kind": kind, "name": name, "on": on],
                         ok: on ? "\(kind == "class" ? classTitle(name) : "Группа «\(name)»") — назначено" : "Снято") }
    }

    /// Класс у клиента один: снять прежний, поставить новый.
    func setClass(_ contactId: String, _ name: String?) {
        let old = contact(contactId)?.classes ?? []
        for k in old where k != name { setCollection(contactId, kind: "class", name: k, on: false) }
        if let name, !old.contains(name) { setCollection(contactId, kind: "class", name: name, on: true) }
    }

    func renameCollection(_ kind: String, from: String, to: String) async {
        let n = String(to.trimmingCharacters(in: .whitespaces).prefix(22))
        guard !n.isEmpty, n != from else { return }
        if kind == "class", let i = extraClasses.firstIndex(of: from) { extraClasses[i] = n; UserDefaults.standard.set(extraClasses, forKey: "extraClasses") }
        if members(kind, from) > 0 { await act(["type": "renameCollection", "kind": kind, "from": from, "to": n], ok: "Переименовано") } else { show("Переименовано") }
    }

    func deleteCollection(_ kind: String, _ name: String) async {
        if kind == "class" { extraClasses.removeAll { $0 == name }; UserDefaults.standard.set(extraClasses, forKey: "extraClasses") }
        if collectionFilter == (kind == "class" ? "class:" : "group:") + name { collectionFilter = "all" }
        if members(kind, name) > 0 { await act(["type": "deleteCollection", "kind": kind, "name": name], ok: "Удалено") } else { show("Удалено") }
    }

    func addClass(_ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(22))
        guard !n.isEmpty, !classes.contains(n) else { return }
        extraClasses.append(n)
        UserDefaults.standard.set(extraClasses, forKey: "extraClasses")
        show("Класс «\(classTitle(n))» добавлен")
    }

    // MARK: - предметы (на телефоне) и расписание (/api/schedule)

    nonisolated static func loadSubjects() -> [SubjectItem] {
        if let d = UserDefaults.standard.data(forKey: "subjects"), let s = try? JSONDecoder().decode([SubjectItem].self, from: d) { return s }
        return [SubjectItem(name: "Математика", color: "#86C7A6"), SubjectItem(name: "Физика", color: "#9CC3D3"),
                SubjectItem(name: "Пробное занятие", color: "#E2C06A"), SubjectItem(name: "Консультация", color: "#E9A37E")]
    }

    func saveSubjects() {
        if let d = try? JSONEncoder().encode(subjects) { UserDefaults.standard.set(d, forKey: "subjects") }
        UserDefaults.standard.set(lessonSubject, forKey: "lessonSubject")
    }

    func subject(of l: Lesson) -> SubjectItem? {
        guard let n = lessonSubject[l.id] else { return nil }
        return subjects.first { $0.name == n } ?? SubjectItem(name: n, color: "#9CC3D3")
    }

    nonisolated static func monday(of d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: d)
        let wd = cal.component(.weekday, from: start)
        return cal.date(byAdding: .day, value: -((wd + 5) % 7), to: start) ?? start
    }

    func loadLessons(week: Date? = nil) async {
        if let week { lessonsWeek = Store.monday(of: week) }
        guard !fixture else { return }
        let to = Calendar.current.date(byAdding: .day, value: 7, to: lessonsWeek) ?? lessonsWeek
        do {
            let r = try await API.get(LessonsResponse.self, "/api/schedule/", query: [URLQueryItem(name: "from", value: dayStamp(lessonsWeek)), URLQueryItem(name: "to", value: dayStamp(to))])
            lessons = r.lessons
            lessonsError = nil
        } catch let e as APIError where e.status == 403 {
            lessons = []
            lessonsError = "Расписание ведёт владелец кабинета"
        } catch {
            lessonsError = friendly(error)
        }
    }

    func lessons(on day: Date) -> [Lesson] {
        lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: day) && $0.status != "cancelled" }.sorted { $0.start < $1.start }
    }

    /// Добавить занятие; weekdays — дни повтора (0 = вс … 6 = сб), weeks — сколько недель.
    func addLesson(convId: String, start: Date, minutes: Int, weeks: Int, weekdays: [Int], subject: String) async -> Bool {
        if fixture {
            let id = "l\(Int.random(in: 1000...9999))"
            let cid = conversation(convId)?.contactId ?? ""
            lessons.append(Lesson(id: id, conversationId: convId, contactId: cid, startsAt: isoString(start),
                                  endsAt: isoString(start.addingTimeInterval(Double(minutes) * 60)), status: "planned", seriesId: weeks > 1 ? "s" + id : nil))
            lessonSubject[id] = subject
            show("Занятие в \(Fmt.hm(start)) добавлено")
            return true
        }
        var json: [String: Any] = ["action": "add", "conversationId": convId, "start": localStamp(start), "duration": minutes]
        if weeks > 1 {
            var rep: [String: Any] = ["weeks": weeks]
            if !weekdays.isEmpty { rep["weekdays"] = weekdays }
            json["repeat"] = rep
        }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: json)
            let before = Set(lessons.map(\.id))
            await loadLessons()
            for l in lessons where !before.contains(l.id) && l.conversationId == convId { lessonSubject[l.id] = subject }
            saveSubjects()
            show(weeks > 1 ? "Занятия добавлены на \(ruCount(weeks, "неделю", "недели", "недель"))" : "Занятие в \(Fmt.hm(start)) добавлено")
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
            show("Занятие перенесено на " + Fmt.whenFull(start))
            return true
        }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: ["action": "move", "id": l.id, "start": localStamp(start), "duration": minutes])
            await loadLessons()
            show("Занятие перенесено на " + Fmt.whenFull(start))
            return true
        } catch { show(friendly(error), ok: false); return false }
    }

    /// Отменить (останется в истории) или удалить; following — это и все следующие в серии.
    func dropLesson(_ l: Lesson, cancel: Bool, following: Bool) async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            lessons.removeAll { $0.id == l.id || (following && l.seriesId != nil && $0.seriesId == l.seriesId && $0.start >= l.start) }
        }
        let what = cancel ? (following ? "Занятия отменены" : "Занятие отменено") : (following ? "Занятия удалены" : "Занятие удалено")
        if fixture { show(what); return }
        do {
            _ = try await API.send("POST", "/api/schedule/", json: ["action": cancel ? "cancel" : "delete", "id": l.id, "following": following])
            show(what)
            await loadLessons()
        } catch { show(friendly(error), ok: false) }
    }

    // MARK: - сотрудники

    func setRole(_ memberId: String, _ role: String) async {
        let p: [String: Any]
        switch role {
        case "Администратор": p = ["channels": "all", "onlyAssigned": false, "canPay": true, "canExport": true, "seeMoney": true]
        case "Только просмотр": p = ["channels": "all", "onlyAssigned": true, "canPay": false, "canExport": false, "seeMoney": false]
        default: p = ["channels": "all", "onlyAssigned": false, "canPay": true, "canExport": false, "seeMoney": true]
        }
        await stateCall("PUT", "/api/team/\(memberId)/permissions/", p, ok: "Роль: \(role)")
    }

    func removeMember(_ id: String) async {
        if fixture { state.team.removeAll { $0.id == id } }
        await stateCall("DELETE", "/api/team/\(id)/", [:], ok: "Доступ закрыт")
    }

    @discardableResult
    func stateCall(_ method: String, _ path: String, _ json: [String: Any], ok: String? = nil) async -> Bool {
        if fixture { if let ok { show(ok) }; return true }
        do {
            let r = try await API.call(ActionResponse.self, method, path, json: json)
            state = r.state
            etag = nil
            if let ok { show(ok) }
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    // MARK: - аккаунт, ИИ, тема

    /// Удаление аккаунта (App Store 5.1.1(v)): POST /api/account/delete {confirm:true}.
    func deleteAccount() async {
        if fixture { show("В демо удаление отключено"); return }
        do {
            if let t = pushToken { _ = try? await API.send("DELETE", "/api/push/device/", json: ["token": t]) }
            _ = try await API.send("POST", "/api/account/delete/", json: ["confirm": true])
            stopLive()
            resetAll()
            withAnimation { phase = .login }
            show("Аккаунт удалён")
        } catch {
            show(friendly(error), ok: false)
        }
    }

    /// Перевод и расшифровка через ИИ — настройка кабинета (PATCH /api/workspace {translate}), только владелец.
    func setTranslate(_ on: Bool) async {
        let old = state.workspace
        state.workspace = WorkspaceInfo(currency: old?.currency, translate: on)
        if fixture { show(on ? "Перевод через ИИ включён" : "Перевод через ИИ выключен"); return }
        if !(await stateCall("PATCH", "/api/workspace/", ["translate": on], ok: on ? "Перевод через ИИ включён" : "Перевод через ИИ выключен")) {
            state.workspace = old
        }
    }

    /// Смена темы: снимок окна ложится сверху и плавно растворяется (~0,35 с), под ним тема меняется сразу — без мигания.
    func setTheme(_ t: ThemeMode) {
        guard t != theme else { return }
        let win = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        let snap = win?.snapshotView(afterScreenUpdates: false)
        if let win, let snap {
            snap.frame = win.bounds
            snap.isUserInteractionEnabled = false
            win.addSubview(snap)
        }
        theme = t
        UserDefaults.standard.set(t.rawValue, forKey: "theme")
        guard let snap else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: { snap.alpha = 0 },
                           completion: { _ in snap.removeFromSuperview() })
        }
    }

    // MARK: - согласие на ИИ

    /// Согласие на отправку текста и голосовых в ИИ-сервисы: спрашиваем при первом использовании перевода или расшифровки.
    func ensureAI(askAgain: Bool) async -> Bool {
        if aiConsent == true { return true }
        if aiConsent == false && !askAgain { return false }
        if aiAsking { return false }
        aiAsking = true
        return await withCheckedContinuation { c in aiContinuation = c }
    }

    func answerAI(_ ok: Bool) {
        guard let c = aiContinuation else { aiAsking = false; return }
        aiContinuation = nil
        aiAsking = false
        aiConsent = ok
        UserDefaults.standard.set(ok, forKey: "aiConsent")
        c.resume(returning: ok)
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - телефонная книга

    /// Имя клиента: для номеров WhatsApp и MAX — из телефонной книги, если включено.
    func name(_ c: Contact?) -> String {
        guard let c else { return "Клиент" }
        return bookName(c) ?? c.name
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
        let nets = [c.source ?? ""] + (c.networks ?? [])
        return nets.contains("whatsapp") || nets.contains("max")
    }

    func phoneOf(_ c: Contact) -> String? {
        if let p = c.phone, !p.isEmpty { return p }
        if PhoneBook.looksLikePhone(c.name) { return c.name }
        if let h = c.handle, PhoneBook.looksLikePhone(h) { return h }
        return nil
    }

    func setContactsOn(_ on: Bool) {
        if on && bookAccess != true {
            PhoneBook.request { [weak self] granted in
                guard let self else { return }
                self.bookAccess = granted
                self.contactsOn = granted
                UserDefaults.standard.set(granted, forKey: "contactsOn")
                if granted { self.refreshBook(); self.show("Имена берём из контактов") } else { self.show("Нет доступа к контактам — разреши в настройках iPhone", ok: false) }
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

    /// «Добавить в контакты»: имя и номер (или ссылка на профиль в соцсети) — в телефонную книгу.
    func addToBook(_ c: Contact) {
        let save = { [weak self] in
            guard let self else { return }
            let net = self.mainConversation(of: c.id)?.network ?? c.source
            let ok = self.fixture ? true : PhoneBook.save(name: self.name(c), phone: self.phoneOf(c), network: net, handle: c.handle)
            if ok {
                if let p = self.phoneOf(c) { self.bookNames[PhoneBook.key(p)] = self.name(c) }
                self.show("Добавлено в контакты телефона")
            } else { self.show("Не получилось сохранить контакт", ok: false) }
        }
        if fixture || bookAccess == true { save(); return }
        PhoneBook.request { [weak self] granted in
            self?.bookAccess = granted
            if granted { save() } else { self?.show("Без доступа к контактам добавить не получится", ok: false) }
        }
    }

    // MARK: - push

    /// Токен APNs получен: регистрируем устройство (POST /api/push/device).
    func registerDevice(_ token: String) {
        pushToken = token
        UserDefaults.standard.set(token, forKey: "pushToken")
        guard !fixture, phase == .ready, pushOn else { return }
        Task { _ = try? await API.send("POST", "/api/push/device/", json: ["platform": "ios", "token": token]) }
    }

    func unregisterDevice() {
        guard let t = pushToken, !fixture else { return }
        Task { _ = try? await API.send("DELETE", "/api/push/device/", json: ["token": t]) }
    }

    /// Нажатие на push: url вида /messages?c=<id диалога>.
    func openURL(_ s: String) {
        guard let comps = URLComponents(string: s), let c = comps.queryItems?.first(where: { $0.name == "c" })?.value else { return }
        tab = .chats
        chatsPath = []
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if self.conversation(c) == nil { await self.loadState(force: true) }
            if self.conversation(c) != nil { self.chatsPath = [.chat(c)] }
        }
    }
}
