import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import QuickLook
import UniformTypeIdentifiers

/// Подсказка-намерение по последнему входящему (как intentOf() в макете). Клиент её не видит.
struct Intent {
    let folderKey: String
    let title: String
    let action: String
    let remind: Bool
    let promise: Bool

    static func of(_ text: String) -> Intent? {
        let t = text.lowercased()
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        if has("оплач|переведу|скину деньги|ödeme yap|ödeyece|i.ll pay|will pay") {
            return Intent(folderKey: "later", title: "Обещает оплатить", action: "В «Оплатит позже» + напомнить завтра в 10:00", remind: true, promise: true)
        }
        if has("подума|дорог|посоветуюсь|düşün|pahalı|think about") {
            return Intent(folderKey: "thinking", title: "Думает", action: "Переложить в «Думает» + напомнить через 2 дня", remind: true, promise: false)
        }
        if has("не надо|не актуал|не интерес|istemiyor|gerek yok|ilgilenmiyor|not interested") {
            return Intent(folderKey: "rejected", title: "Отказ", action: "Переложить в «Отказ»", remind: false, promise: false)
        }
        if has("сколько|цена|стоим|прайс|fiyat|ne kadar|price") {
            return Intent(folderKey: "talking", title: "Спрашивает цену", action: "Переложить в «В диалоге»", remind: false, promise: false)
        }
        if has("teşekkür|iletişime geçtiğiniz|автоответ|auto.?reply") {
            return Intent(folderKey: "talking", title: "Похоже на автоответ", action: "Оставить и напомнить завтра", remind: true, promise: false)
        }
        return nil
    }
}

enum RemPreset: String, CaseIterable {
    case hour, evening, tomorrow, twoDays, monday
    var title: String {
        switch self {
        case .hour: return "Через час"
        case .evening: return "Сегодня в 18:00"
        case .tomorrow: return "Завтра в 10:00"
        case .twoDays: return "Через 2 дня"
        case .monday: return "В понедельник в 10:00"
        }
    }
    var date: Date {
        let cal = Calendar.current, now = Date()
        func at(_ d: Date, _ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: d) ?? d }
        switch self {
        case .hour: return now.addingTimeInterval(3600)
        case .evening:
            let e = at(now, 18)
            return e < now ? e.addingTimeInterval(86400) : e
        case .tomorrow: return at(cal.date(byAdding: .day, value: 1, to: now) ?? now, 10)
        case .twoDays: return at(cal.date(byAdding: .day, value: 2, to: now) ?? now, 10)
        case .monday:
            let wd = cal.component(.weekday, from: now) // 1 — вс, 2 — пн
            var add = (9 - wd) % 7
            if add == 0 { add = 7 }
            return at(cal.date(byAdding: .day, value: add, to: now) ?? now, 10)
        }
    }
}

struct ChatView: View {
    @Environment(Store.self) private var store
    let convId: String
    @State private var trHint = false
    @State private var draft = ""
    @State private var sending: [String] = []
    @State private var sheet: ChatSheet?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var uploading = false
    @State private var replyTo: Message?
    @State private var viewer: ViewerState?
    @State private var confirmDelete: Message?
    @State private var recorder = VoiceRecorder()
    @State private var videoMode = false
    @StateObject private var cam = CameraModel()
    /// кружок: запись прямо над полем ввода (те же фазы, что у голосового)
    @State private var notePhase: VoiceRecorder.Phase = .idle
    @State private var noteFinish: NoteFinish?
    @State private var pressing = false
    @State private var pressSendMode = false
    @State private var holdTask: Task<Void, Never>?
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var highlight: String?
    @State private var pinJump: String?
    @State private var sendingVoice: [TimeInterval] = []
    @State private var sendHoldTask: Task<Void, Never>?
    /// высота панели ввода (с ответом/подсказкой) — нижний отступ ленты, чтобы последнее сообщение не пряталось под ней
    @State private var bottomH: CGFloat = 0
    @FocusState private var inputFocused: Bool

    enum NoteFinish { case send, preview, discard }

    enum ChatSheet: String, Identifiable {
        case folder, remind, templates, attach, translate, schedule, scheduled
        var id: String { rawValue }
    }

    var body: some View {
        let conv = store.conversation(convId)
        let contact = conv.flatMap { store.contact($0.contactId) }
        ZStack {
            if let conv, let contact {
                messagesView(conv)
                noteOverlay
                VStack(spacing: 0) {
                    header(conv, contact)
                    Spacer()
                    bottom(conv, contact)
                        .background(GeometryReader { g in Color.clear.preference(key: ChatBottomHeightKey.self, value: g.size.height) })
                }
                .onPreferenceChange(ChatBottomHeightKey.self) { h in if h > 0 { bottomH = h } }
                if trHint, let lang = foreignLang(contact) {
                    ChatTranslateHint(langName: LangName.acc(lang)) { withAnimation { trHint = false } }
                }
            } else {
                VStack {
                    TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { EmptyView() })
                    EmptyNote(text: "Чат не найден — возможно, его удалили")
                    Spacer()
                }
            }
        }
        .screenBackground(store.wall)
        .onAppear {
            store.markRead(convId)
            // подсказка о переводе — один раз, при первом входе в иностранный чат
            if store.translateOn, let c = contact, foreignLang(c) != nil, !UserDefaults.standard.bool(forKey: "trHintSeen") {
                UserDefaults.standard.set(true, forKey: "trHintSeen")
                withAnimation(.spring(response: 0.4).delay(0.3)) { trHint = true }
            }
            if let d = store.drafts[convId] { draft = d }
            #if DEBUG
            applyFixtureScreen()
            #endif
        }
        .onDisappear {
            store.saveDraft(convId, draft)
            if recorder.isActive { recorder.cancel() }
            if notePhase != .idle { closeNote() }
        }
        .task {
            await store.loadHistory(convId)
            await store.loadScheduled(convId)
            await store.translateIncoming(convId)
        }
        .sheet(item: $sheet) { s in
            if let conv, let contact {
                switch s {
                case .folder: FolderSheet(contactId: contact.id)
                case .remind: ReminderSheet(contactId: contact.id)
                case .templates: TemplatesSheet { text in draft = text; inputFocused = true }
                case .translate: TranslateSheet(lang: foreignLang(contact) ?? (contact.lang ?? ""))
                case .schedule:
                    ScheduleSendSheet(text: draft) { at in
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let reply = replyTo?.id
                        draft = ""
                        replyTo = nil
                        Task { if !(await store.schedule(conv.id, text: t, at: at, replyTo: reply)) { draft = t } }
                    }
                case .scheduled: ScheduledListSheet(convId: conv.id)
                case .attach:
                    AttachSheet(canNote: conv.network == "telegram",
                                onPhoto: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showPhotos = true } },
                                onFile: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showFiles = true } },
                                onTemplate: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = .templates } },
                                onVoice: { sheet = nil; store.show("Удерживай кнопку микрофона справа от поля — запись пойдёт, пока держишь") },
                                onNote: {
                                    sheet = nil
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { videoMode = true }
                                    store.show("Удерживай кнопку камеры справа от поля — кружок пишется, пока держишь")
                                })
                        .id(conv.id)
                }
            }
        }
        .fullScreenCover(item: $viewer) { v in
            MediaViewer(items: v.items, start: v.start) { viewer = nil }
                .environment(store)
        }
        .onChange(of: cam.ready) { _, ready in
            // камера включилась, а кнопку всё ещё держат (или замок) — начинаем запись
            if ready, notePhase == .recording || notePhase == .locked, !cam.recording { cam.record() }
        }
        .onChange(of: cam.outputURL) { _, url in
            if let url { noteRecorded(url) }
        }
        .onChange(of: cam.problem) { _, p in
            if let p, notePhase != .idle {
                store.show(p, ok: false)
                closeNote()
            }
        }
        .confirmationDialog("Удалить сообщение у клиента?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            if let m = confirmDelete {
                Button("Удалить у всех", role: .destructive) {
                    confirmDelete = nil
                    Task { await store.unsend(m.id, convId: convId) }
                }
            }
            Button("Отмена", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Сообщение пропадёт и у клиента, и здесь. Вернуть будет нельзя.")
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await sendFile(url) } }
        }
    }

    // MARK: переписка

    private func mediaItems(_ msgs: [Message]) -> [MediaItem] {
        var out: [MediaItem] = []
        for m in msgs {
            for (i, a) in (m.attachments ?? []).enumerated() where a.kind == "image" || a.kind == "video" {
                out.append(MediaItem(id: m.id + "#\(i)", raw: a.url, kind: a.kind, name: a.name ?? "", round: a.round == true, mime: a.mime))
            }
        }
        return out
    }

    private func openMedia(_ msgs: [Message], messageId: String, index: Int) {
        let items = mediaItems(msgs)
        let key = messageId + "#\(index)"
        let start: Int = items.firstIndex { $0.id == key } ?? 0
        guard !items.isEmpty else { return }
        viewer = ViewerState(items: items, start: start)
    }

    private func canUnsend(_ m: Message, _ conv: Conversation) -> Bool {
        guard m.isOut, m.externalId != nil, conv.network == "telegram" || conv.network == "whatsapp" else { return false }
        if store.user?.isOwner == true || store.fixture { return true }
        return m.authorId != nil && m.authorId == store.user?.id
    }

    private func messagesView(_ conv: Conversation) -> some View {
        let msgs = store.messages(conv.id)
        let intent = currentIntent(conv)
        let extra: CGFloat = (intent != nil ? 104 : 0) + (replyTo != nil ? 56 : 0)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if (conv.older ?? 0) > 0 && store.fullHistory[conv.id] == nil {
                        ProgressView().tint(Pal.fg).padding(.vertical, 8)
                    }
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        if i == 0 || !Calendar.current.isDate(msgs[i - 1].date, inSameDayAs: m.date) {
                            Text(Fmt.dayLong(m.date))
                                .font(Typo.body(12, .semibold))
                                .foregroundStyle(Pal.fg)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Pal.bubIn))
                                .padding(.vertical, 8)
                        }
                        Bubble(message: m,
                               highlighted: highlight == m.id,
                               canUnsend: canUnsend(m, conv),
                               canReact: conv.network == "telegram" || conv.network == "whatsapp",
                               pinned: conv.pins.contains(m.id),
                               onReply: { startReply(m) },
                               onDelete: { confirmDelete = m },
                               onOpenMedia: { idx in openMedia(msgs, messageId: m.id, index: idx) },
                               onQuoteTap: { id in jump(to: id, proxy: proxy) },
                               onReact: { e in store.react(conv.id, m, e) },
                               onPin: { store.pinMessage(conv.id, m, !conv.pins.contains(m.id)) })
                            .id(m.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    ForEach(sending, id: \.self) { t in
                        pendingBubble(t).id("pending-" + t)
                    }
                    ForEach(sendingVoice, id: \.self) { t in
                        pendingVoice(t).id("pending-voice-\(t)")
                    }
                    if let t = store.typing[conv.id], Date().timeIntervalSince(t.at) < 5 {
                        TypingDots().frame(maxWidth: .infinity, alignment: .leading).id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, conv.pins.isEmpty ? 150 : 204)
                .padding(.bottom, bottomH > 0 ? bottomH + 12 : 96 + extra)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: msgs.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.loadState(force: true) }
            .onAppear {
                // defaultScrollAnchor с LazyVStack не всегда открывает чат внизу (снимки CI открывались сверху)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("bottom", anchor: .bottom) }
                #if DEBUG
                if let id = fixtureScrollTarget() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.2)) }
                }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .sguardoBubbleGrew)) { n in
                // раскрыли расшифровку у последнего сообщения — докрутить, чтобы пузырь был целиком над полем ввода
                guard let id = n.object as? String, id == store.messages(conv.id).last?.id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: bottomH) { old, new in
                // панель ввода выросла (ответ, подсказка) — низ ленты не должен уйти под неё
                if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: msgs.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: pinJump) { _, id in
                guard let id else { return }
                jump(to: id, proxy: proxy)
                pinJump = nil
            }
            .onChange(of: sending.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: inputFocused) { _, f in
                if f { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
        }
    }

    /// Мгновенная заглушка голосового в ленте, пока файл загружается.
    private func pendingVoice(_ sec: TimeInterval) -> some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 16, weight: .semibold))
                LevelBars(levels: (0..<40).map { k in CGFloat(0.2 + 0.7 * abs(sin(Double(k) / 2.3))) }, count: 22, color: Pal.onAcc)
                Text(durationText(sec)).font(Typo.body(12, .medium)).monospacedDigit()
                ProgressView().controlSize(.mini).tint(Pal.onAcc)
            }
            .foregroundStyle(Pal.onAcc)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous).fill(Pal.acc.opacity(0.75)))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func pendingBubble(_ t: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            HStack(alignment: .bottom, spacing: 6) {
                Text(t).font(Typo.body(15.5)).foregroundStyle(Pal.onAcc)
                Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Pal.onAcc.opacity(0.6))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous).fill(Pal.acc.opacity(0.7)))
        }
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        highlight = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { if highlight == id { highlight = nil } } }
    }

    private func startReply(_ m: Message) {
        haptic(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { replyTo = m }
        inputFocused = true
    }

    private func header(_ conv: Conversation, _ contact: Contact) -> some View {
        let f = store.folder(contact.folderId)
        let rem = store.reminder(for: contact.id)
        let net = NetInfo.of(conv.network)
        let promised = store.deals(of: contact.id).last { $0.status == "promised" }
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }
                Button { store.open(.client(contact.id)) } label: {
                    VStack(spacing: 1) {
                        Text(store.name(contact)).font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                        HStack(spacing: 4) {
                            Circle().fill(net.color).frame(width: 7, height: 7)
                            if let st = store.statusLine(conv.id) {
                                Text(st).font(Typo.body(11, .medium)).foregroundStyle(Pal.acc).lineLimit(1)
                                    .transition(.opacity)
                            } else {
                                Text(joinHandle(net.name, contact.handle))
                                    .font(Typo.body(11)).foregroundStyle(Pal.fg.opacity(0.72)).lineLimit(1)
                            }
                            if store.translateOn, let lang = foreignLang(contact) {
                                langBadge(lang)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .glassCapsule(interactive: true)
                Button { store.open(.client(contact.id)) } label: {
                    Avatar(name: contact.name, hue: contact.displayHue, url: contact.avatar, size: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Карточка клиента")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(text: f?.name ?? "Без папки", dot: Color(css: f?.color), height: 32, fontSize: 13) { sheet = .folder }
                    if let promised, promised.amount > 0 {
                        Chip(text: Fmt.money(promised.amount, currency: store.state.workspace?.currency), height: 32, fontSize: 13) { store.open(.client(contact.id)) }
                            .contextMenu {
                                Button(role: .destructive) { undoPromise(contact.id, promised) } label: { Label("Снять обещание", systemImage: "xmark.circle") }
                            }
                    }
                    ForEach(contact.tags ?? [], id: \.self) { t in
                        tagChip(t, contact: contact)
                    }
                    if let rem {
                        Chip(text: "⏰ " + Fmt.remShort(rem.date), height: 32, fontSize: 13) { sheet = .remind }
                            .contextMenu {
                                Button { sheet = .remind } label: { Label("Перенести", systemImage: "clock") }
                                Button { done(rem, contact.id) } label: { Label("Готово", systemImage: "checkmark") }
                                Button(role: .destructive) { removeReminder(rem, contact.id) } label: { Label("Удалить напоминание", systemImage: "trash") }
                            }
                    } else {
                        Chip(text: "🔔 Напомнить", height: 32, fontSize: 13) { sheet = .remind }
                    }
                }
                .padding(.vertical, 2)
            }
            if let pid = conv.pins.first, let pm = store.messages(conv.id).first(where: { $0.id == pid }) {
                pinnedBar(pm, conv)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(LinearGradient(stops: [.init(color: Pal.page.opacity(0.97), location: 0), .init(color: Pal.page.opacity(0.85), location: 0.55), .init(color: Pal.page.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    /// Закреплённое сообщение: нажатие — к сообщению, крестик — открепить.
    private func pinnedBar(_ m: Message, _ conv: Conversation) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Pal.acc).frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(conv.pins.count > 1 ? "Закреплено · \(conv.pins.count)" : "Закреплённое сообщение").font(Typo.body(12, .semibold)).foregroundStyle(Pal.acc)
                Text(m.preview).font(Typo.body(13)).foregroundStyle(Pal.fg).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { store.pinMessage(conv.id, m, false) } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Pal.fg2).frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .accessibilityLabel("Открепить")
        }
        .padding(.horizontal, 12).frame(height: 46)
        .contentShape(Rectangle())
        .onTapGesture { pinJump = m.id }
        .glassRect(16, .light)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Метка в шапке: крестик снимает её с клиента (с «Отменить»).
    private func tagChip(_ t: String, contact: Contact) -> some View {
        HStack(spacing: 4) {
            if let ic = tagIcon(t) { Image(systemName: ic).font(.system(size: 11, weight: .semibold)) }
            Text(tagTitle(t)).font(Typo.body(13, .semibold)).lineLimit(1)
            Button { removeTag(t, contact) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .accessibilityLabel("Снять метку \(tagTitle(t))")
        }
        .foregroundStyle(Pal.ink)
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 32)
        .background(Capsule().fill(labelColor(t)))
        .onTapGesture { store.open(.client(contact.id)) }
    }

    private func removeTag(_ t: String, _ c: Contact) {
        var tags = c.tags ?? []
        tags.removeAll { $0 == t }
        let body: [String: Any] = ["type": "updateContact", "contactId": c.id, "tags": tags]
        Task { await store.perform([body], contactId: c.id, ok: "Метка «\(tagTitle(t))» снята") }
    }

    private func done(_ r: Reminder, _ contactId: String) {
        Task { await store.perform([["type": "doneReminder", "id": r.id]], contactId: contactId, ok: "Напоминание выполнено") }
    }

    private func removeReminder(_ r: Reminder, _ contactId: String) {
        Task { await store.perform([["type": "removeReminder", "id": r.id]], contactId: contactId, ok: "Напоминание удалено") }
    }

    private func undoPromise(_ contactId: String, _ d: Deal) {
        Task { await store.perform([["type": "removeDeal", "id": d.id]], contactId: contactId, ok: "Обещание снято") }
    }

    private func currentIntent(_ conv: Conversation) -> Intent? {
        guard let m = conv.last, !m.isOut, !store.hintOff.contains(conv.id + "|" + m.id) else { return nil }
        return Intent.of(m.body)
    }

    private func bottom(_ conv: Conversation, _ contact: Contact) -> some View {
        let intent = currentIntent(conv)
        return VStack(spacing: 10) {
            if let intent, let m = conv.last, !isRecActive {
                intentCard(intent, m, conv, contact)
            }
            if let r = replyTo, !isRecActive {
                replyBar(r)
            }
            if !(store.scheduled[conv.id] ?? []).isEmpty, !isRecActive {
                scheduledBar(conv)
            }
            if store.translateOn, inputFocused, let lang = foreignLang(contact), !isRecActive {
                translateChip(lang)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer(conv)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: intent?.title)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: replyTo?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: inputFocused)
    }

    private func intentCard(_ intent: Intent, _ m: Message, _ conv: Conversation, _ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: 15, weight: .bold)).foregroundStyle(Pal.acc)
                Text(intent.title).font(Typo.body(14, .semibold)).foregroundStyle(Pal.fg)
                Spacer()
                Text("клиент не увидит").font(Typo.body(12)).foregroundStyle(Pal.fg3)
            }
            HStack(spacing: 8) {
                Button { Task { await apply(intent, contact) } } label: {
                    Text(intent.action).font(Typo.body(13.5, .semibold)).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 40).primaryFill(14)
                }
                .buttonStyle(PressStyle())
                Button { withAnimation { store.hideHint(conv.id, lastMessageId: m.id) } } label: {
                    Text("Нет").font(Typo.body(14)).foregroundStyle(Pal.fg).padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassRect(22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func replyBar(_ r: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 15)).foregroundStyle(Pal.acc)
            Rectangle().fill(Pal.acc).frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.isOut ? "Ответ на ваше сообщение" : "Ответ клиенту").font(Typo.body(12, .semibold)).foregroundStyle(Pal.acc)
                Text(r.preview).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { withAnimation { replyTo = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Pal.fg).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Не отвечать")
        }
        .padding(.horizontal, 12).frame(height: 48)
        .glassRect(18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func scheduledBar(_ conv: Conversation) -> some View {
        let items: [ScheduledMessage] = (store.scheduled[conv.id] ?? []).sorted { $0.date < $1.date }
        let failed: Bool = items.contains { $0.status == "failed" }
        return Button { sheet = .scheduled } label: {
            HStack(spacing: 8) {
                Image(systemName: failed ? "exclamationmark.circle.fill" : "clock.fill").font(.system(size: 14))
                    .foregroundStyle(failed ? Pal.danger : Pal.acc)
                Text("Запланировано: \(items.count)").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                if let first = items.first { Text("· " + Fmt.whenFull(first.date)).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Pal.fg3)
            }
            .padding(.horizontal, 14).frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .glassRect(19, .light)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: перевод при отправке

    /// Язык клиента для перевода. Сервер может ошибиться (ссылка t.me сделала русского клиента «английским»),
    /// поэтому доверяем contact.lang, только если сами входящие это подтверждают.
    private func foreignLang(_ c: Contact) -> String? {
        guard let l = c.lang?.lowercased(), !l.isEmpty, !l.hasPrefix("ru") else { return nil }
        let msgs: [Message] = store.conversation(convId)?.messages ?? []
        return incomingLooksForeign(msgs) ? l : nil
    }

    /// Большинство из последних 6 входящих с текстом (≥12 букв без ссылок, @ и #) — не кириллица.
    private func incomingLooksForeign(_ msgs: [Message]) -> Bool {
        var foreign = 0
        var total = 0
        for m in msgs.reversed() where !m.isOut {
            if total >= 6 { break }
            let words: [Substring] = m.body.split(whereSeparator: { $0.isWhitespace })
            let clean: [Substring] = words.filter { (w: Substring) -> Bool in
                let lw: String = w.lowercased()
                return !(lw.hasPrefix("@") || lw.hasPrefix("#") || lw.contains("://") || lw.hasPrefix("www.") || lw.contains("t.me/"))
            }
            var letters = 0
            var cyr = 0
            for w in clean {
                for u in w.unicodeScalars where CharacterSet.letters.contains(u) {
                    letters += 1
                    if (0x0400...0x04FF).contains(Int(u.value)) { cyr += 1 }
                }
            }
            guard letters >= 12 else { continue }
            total += 1
            if cyr * 2 < letters { foreign += 1 }
        }
        return total > 0 && foreign * 2 > total
    }

    /// Переводить исходящие этого чата: только если клиент и правда пишет не по-русски.
    private var canTranslate: Bool {
        guard let conv = store.conversation(convId), let c = store.contact(conv.contactId) else { return false }
        return foreignLang(c) != nil
    }

    /// Значок языка в шапке: «🌐 EN». Тап — лист с объяснением и переключателем (перехватывает тап у карточки клиента).
    private func langBadge(_ lang: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 9, weight: .semibold))
            Text(String(lang.prefix(2)).uppercased()).font(Typo.body(10, .semibold))
        }
        .foregroundStyle(store.translateOut ? Pal.page : Pal.fg)
        .padding(.horizontal, 6).frame(height: 16)
        .background(Capsule().fill(store.translateOut ? Pal.fg.opacity(0.85) : Pal.fg.opacity(0.18)))
        .contentShape(Rectangle().inset(by: -8))
        .highPriorityGesture(TapGesture().onEnded { haptic(); sheet = .translate })
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Перевод переписки")
    }

    /// Компактный переключатель над полем ввода (только пока поле в фокусе): «🌐 RU → EN» и тумблер.
    private func translateChip(_ lang: String) -> some View {
        let code: String = String(lang.prefix(2)).uppercased()
        return HStack {
            Button {
                haptic()
                withAnimation(.spring(response: 0.3)) { store.translateOut.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
                    Text(store.translateOut ? "RU → \(code)" : "без перевода").font(Typo.body(12, .medium)).lineLimit(1)
                    ZStack(alignment: store.translateOut ? .trailing : .leading) {
                        Capsule().fill(store.translateOut ? Pal.fg.opacity(0.85) : Pal.fg.opacity(0.2))
                        Circle().fill(store.translateOut ? Pal.page : Pal.fg).frame(width: 11, height: 11).padding(2)
                    }
                    .frame(width: 26, height: 15)
                }
                .foregroundStyle(Pal.fg.opacity(0.9))
                .padding(.horizontal, 10).frame(height: 26)
                .glassCapsule(.dark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.translateOut ? "перевод при отправке включён" : "перевод при отправке выключен")
            Spacer(minLength: 0)
        }
    }

    // MARK: поле ввода и запись

    private func composer(_ conv: Conversation) -> some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canNote = conv.network == "telegram"
        return ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 8) {
                switch recPhase {
                case .idle:
                    CircleButton(system: "plus", iconSize: 20) { sheet = .attach }
                    textField
                case .recording:
                    recordingBar
                case .locked:
                    lockedBar
                case .preview:
                    previewBar
                }
                mainButton(conv, hasText: hasText, canNote: canNote)
            }
            if recPhase == .recording {
                lockHint.offset(x: 0, y: -62)
            }
        }
    }

    private var textField: some View {
        HStack(spacing: 6) {
            TextField("", text: $draft, prompt: Text("Сообщение").foregroundColor(Pal.fg3), axis: .vertical)
                .lineLimit(1...5)
                .font(Typo.body(16))
                .foregroundStyle(Pal.fg)
                .focused($inputFocused)
                .accessibilityIdentifier("composer")
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { inputFocused = false; sheet = .schedule } label: {
                    Image(systemName: "clock").font(.system(size: 17)).foregroundStyle(Pal.fg.opacity(0.75)).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .accessibilityLabel("Отправить позже")
                .transition(.scale.combined(with: .opacity))
            }
            Button { sheet = .templates } label: {
                Image(systemName: "tag").font(.system(size: 17)).foregroundStyle(Pal.fg.opacity(0.75)).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Шаблоны")
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 6)
        .frame(minHeight: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var recordingBar: some View {
        let cancelProgress: Double = Double(min(1, max(0, -dragX / 110)))
        return HStack(spacing: 10) {
            Circle().fill(Pal.danger).frame(width: 10, height: 10)
                .opacity(Int(recElapsed * 2) % 2 == 0 ? 1 : 0.35)
            Text(durationTenths(recElapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(Pal.fg)
                .lineLimit(1).fixedSize()
            if notePhase == .idle {
                LevelBars(levels: recorder.levels, count: 14).opacity(1 - cancelProgress)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text("влево — отмена").font(Typo.body(14))
            }
            .foregroundStyle(Pal.fg2.opacity(1 - cancelProgress * 0.7))
            .offset(x: min(0, dragX * 0.5))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var lockHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold))
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(Pal.fg)
        .frame(width: 44, height: 70)
        .glass(.light, in: Capsule())
        .offset(y: min(0, dragY * 0.4))
        .transition(.opacity)
        .accessibilityLabel("Вверх — запись без рук")
    }

    @ViewBuilder private var lockedBar: some View {
        if notePhase == .locked {
            HStack(spacing: 10) {
                Button { cancelNote() } label: {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel("Удалить кружок")
                Circle().fill(Pal.danger).frame(width: 9, height: 9)
                    .opacity(Int(cam.elapsed * 2) % 2 == 0 ? 1 : 0.35)
                Text(durationText(cam.elapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(Pal.fg)
                Text("кружок · без рук").font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            voiceLockedBar
        }
    }

    private var voiceLockedBar: some View {
        HStack(spacing: 10) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить запись")
            Circle().fill(Pal.danger).frame(width: 9, height: 9)
                .opacity(Int(recorder.elapsed * 2) % 2 == 0 ? 1 : 0.35)
            Text(durationTenths(recorder.elapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(Pal.fg)
                .lineLimit(1).fixedSize()
            LevelBars(levels: recorder.levels, count: 12).opacity(recorder.paused ? 0.4 : 1).clipped()
            Spacer(minLength: 0)
            Button { recorder.togglePause() } label: {
                Image(systemName: recorder.paused ? "mic.fill" : "pause.fill").font(.system(size: 14)).foregroundStyle(Pal.fg).frame(width: 34, height: 34)
                    .background(Circle().fill(Pal.fg.opacity(0.12)))
            }
            .accessibilityLabel(recorder.paused ? "Продолжить запись" : "Пауза")
            Button { recorder.toPreview() } label: {
                Image(systemName: "stop.fill").font(.system(size: 14)).foregroundStyle(Pal.fg).frame(width: 34, height: 34)
                    .background(Circle().fill(Pal.fg.opacity(0.18)))
            }
            .accessibilityLabel("Остановить и прослушать")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var previewBar: some View {
        if notePhase == .preview {
            HStack(spacing: 10) {
                Button { cancelNote() } label: {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel("Удалить кружок")
                Image(systemName: "video.circle.fill").font(.system(size: 20)).foregroundStyle(Pal.acc)
                Text("Кружок готов").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg)
                Spacer(minLength: 0)
                Text(durationText(cam.elapsed)).font(Typo.body(14, .medium)).monospacedDigit().foregroundStyle(Pal.fg2)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            voicePreviewBar
        }
    }

    private var voicePreviewBar: some View {
        HStack(spacing: 10) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить запись")
            Button { recorder.togglePlay() } label: {
                Image(systemName: recorder.playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(Pal.onAcc)
                    .frame(width: 32, height: 32).background(Circle().fill(Pal.acc))
            }
            .accessibilityLabel(recorder.playing ? "Пауза" : "Прослушать")
            LevelBars(levels: recorder.levels, count: 26, progress: recorder.playing || recorder.playProgress > 0 ? recorder.playProgress : nil)
            Spacer(minLength: 0)
            Text(durationText(recorder.elapsed)).font(Typo.body(14, .medium)).monospacedDigit().foregroundStyle(Pal.fg2)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Правая кнопка: текст — отправить; запись без рук / прослушивание — отправить голосовое;
    /// иначе микрофон (или камера кружка в Telegram): удержать — записать, нажать — сменить режим.
    private func mainButton(_ conv: Conversation, hasText: Bool, canNote: Bool) -> some View {
        let phase: VoiceRecorder.Phase = recPhase
        let recording: Bool = phase == .recording
        let sendMode: Bool = hasText || phase == .locked || phase == .preview
        let icon: String = sendMode ? "arrow.up" : (videoMode && canNote ? "video" : "mic")
        let filled: Bool = sendMode || uploading || recording
        let recIcon: String = notePhase == .recording ? "video.fill" : "mic.fill"
        return ZStack {
            if uploading { ProgressView().tint(Pal.onAcc) } else {
                Image(systemName: recording ? recIcon : icon)
                    .font(.system(size: 19, weight: sendMode ? .bold : .regular))
                    .foregroundStyle(filled ? Pal.onAcc : Pal.fg)
            }
        }
        .frame(width: 44, height: 44)
        .background(Circle().fill(recording ? Pal.danger : (filled ? Pal.acc : .clear)))
        .contentTransition(.symbolEffect(.replace))
        .contentShape(Circle())
        .glass(.light, in: Circle(), interactive: true)
        // стекло двигается вместе с кнопкой: без «второго кружка» за красным микрофоном
        .scaleEffect(recording ? 1.25 : 1)
        .offset(x: recording ? min(0, dragX) : 0, y: recording ? min(0, dragY) : 0)
        .gesture(holdGesture(conv, canNote: canNote, sendMode: sendMode, hasText: hasText))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sendMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: videoMode)
        .accessibilityLabel(sendMode ? "Отправить" : (videoMode && canNote ? "Кружок: удерживай, чтобы записать" : "Голосовое: удерживай, чтобы записать"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tapSend(conv, sendMode: sendMode, hasText: hasText) }
    }

    private func tapSend(_ conv: Conversation, sendMode: Bool, hasText: Bool) {
        guard sendMode else {
            store.show("Удерживай кнопку, чтобы записать")
            return
        }
        if hasText && recPhase == .idle {
            Task { await send(conv) }
        } else if notePhase == .locked {
            stopNote(.send)
        } else if notePhase == .preview, let url = cam.outputURL {
            closeNote(keepFile: true)
            Task { await sendNote(url) }
        } else {
            Task { await sendVoice() }
        }
    }

    /// Один жест на кнопке: в режиме «отправить» — нажатие, иначе удержание (запись) или короткое нажатие (смена режима).
    /// Маску жеста не переключаем: сброс жеста посреди удержания оставил бы кнопку «нажатой».
    private func holdGesture(_ conv: Conversation, canNote: Bool, sendMode: Bool, hasText: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !pressing {
                    pressing = true
                    pressSendMode = sendMode
                    if !sendMode {
                        beginHold(canNote: canNote)
                    } else if hasText && recPhase == .idle {
                        sendHoldTask?.cancel()
                        sendHoldTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled, pressing else { return }
                            sendHoldTask = nil
                            pressSendMode = false
                            haptic(.medium)
                            inputFocused = false
                            sheet = .schedule
                        }
                    }
                }
                guard recPhase == .recording else { return }
                dragX = min(0, v.translation.width)
                dragY = min(0, v.translation.height)
                if v.translation.width < -110 {
                    if notePhase == .recording { cancelNote() } else { recorder.cancel(); haptic(.rigid) }
                    resetDrag()
                } else if v.translation.height < -80 {
                    if notePhase == .recording {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { notePhase = .locked }
                        haptic(.medium)
                    } else {
                        recorder.lock()
                    }
                    resetDrag()
                }
            }
            .onEnded { v in
                pressing = false
                sendHoldTask?.cancel()
                sendHoldTask = nil
                resetDrag()
                if pressSendMode {
                    // отпустили над кнопкой — отправляем
                    if abs(v.translation.width) < 40 && abs(v.translation.height) < 40 { tapSend(conv, sendMode: true, hasText: hasText) }
                    return
                }
                endHold(canNote: canNote)
            }
    }

    private func resetDrag() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { dragX = 0; dragY = 0 }
    }

    private func beginHold(canNote: Bool) {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, pressing else { return }
            holdTask = nil
            haptic(.medium)
            if videoMode && canNote {
                startNote()
                return
            }
            inputFocused = false
            let ok = await recorder.start()
            if !ok {
                store.show("Нет доступа к микрофону — разреши в настройках iPhone", ok: false)
            } else if !pressing {
                // отпустили, пока система спрашивала доступ, — запись не начинаем
                recorder.cancel()
            }
        }
    }

    private func endHold(canNote: Bool) {
        if let t = holdTask {
            // короткое нажатие: в Telegram переключает голосовое/кружок, в других сетях — подсказка
            t.cancel()
            holdTask = nil
            if canNote {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { videoMode.toggle() }
                haptic()
                store.show(videoMode ? "Режим кружка: удерживай кнопку, чтобы записать" : "Режим голосового: удерживай, чтобы записать")
            } else {
                store.show("Удерживай кнопку, чтобы записать голосовое")
            }
            return
        }
        if notePhase == .recording {
            stopNote(.send)
        } else if recorder.phase == .recording {
            Task { await sendVoice() }
        }
    }

    // MARK: кружок над полем ввода

    private var recPhase: VoiceRecorder.Phase { notePhase != .idle ? notePhase : recorder.phase }
    private var recElapsed: TimeInterval { notePhase != .idle ? cam.elapsed : recorder.elapsed }
    private var isRecActive: Bool { recPhase != .idle }

    private func startNote() {
        inputFocused = false
        cam.problem = nil
        cam.reset()
        noteFinish = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { notePhase = .recording }
        if store.fixture { return }
        // запись начнётся, когда камера включится (onChange cam.ready)
        cam.prepare()
    }

    /// Остановить запись: отправить, показать для прослушивания или выбросить.
    private func stopNote(_ finish: NoteFinish) {
        guard notePhase == .recording || notePhase == .locked else { return }
        if store.fixture {
            if finish == .send { store.show("Отправлено") }
            closeNote()
            return
        }
        let tooShort: Bool = !cam.recording || (finish == .send && cam.elapsed < 0.8)
        if tooShort {
            if finish != .discard { store.show("Слишком коротко — держи кнопку дольше", ok: false) }
            noteFinish = .discard
            if cam.recording { cam.stop() } else { closeNote() }
            return
        }
        noteFinish = finish
        cam.stop()
    }

    private func cancelNote() {
        haptic(.rigid)
        if notePhase == .preview { closeNote() } else { stopNote(.discard) }
    }

    /// Файл кружка записан (отпустили, «стоп» или упёрлись в 60 с).
    private func noteRecorded(_ url: URL) {
        let finish: NoteFinish = noteFinish ?? (notePhase == .locked ? .preview : .send)
        noteFinish = nil
        switch finish {
        case .send:
            closeNote(keepFile: true)
            haptic(.medium)
            Task { await sendNote(url) }
        case .preview:
            cam.shutdown()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { notePhase = .preview }
        case .discard:
            closeNote()
        }
    }

    private func closeNote(keepFile: Bool = false) {
        cam.shutdown()
        if keepFile {
            cam.outputURL = nil
            cam.elapsed = 0
        } else {
            cam.reset()
        }
        noteFinish = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { notePhase = .idle }
    }

    /// Живой круг камеры над полем ввода (поверх ленты), кольцо до 60 с; в режиме без рук — «сменить камеру» и «стоп».
    @ViewBuilder private var noteOverlay: some View {
        if notePhase != .idle {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .allowsHitTesting(notePhase != .recording)
                VStack(spacing: 16) {
                    noteCircle
                    if notePhase == .locked {
                        HStack(spacing: 22) {
                            noteControl(icon: "arrow.triangle.2.circlepath.camera", label: "Сменить камеру") { haptic(); cam.switchCamera() }
                            noteControl(icon: "stop.fill", label: "Стоп", tint: Pal.danger) { haptic(); stopNote(.preview) }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else if notePhase == .recording {
                        Text("Отпусти — отправится").font(Typo.body(13, .medium)).foregroundStyle(Pal.fg2)
                    }
                }
                .padding(.bottom, 118)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomTrailing)))
            .accessibilityIdentifier("note-overlay")
        }
    }

    private var noteCircle: some View {
        let side: CGFloat = 240
        let progress: Double = min(1, cam.elapsed / CameraModel.maxDuration)
        return ZStack {
            Circle().fill(Pal.fg.opacity(0.08))
            noteCircleContent
                .frame(width: side, height: side)
                .clipShape(Circle())
            Circle().stroke(Pal.fg.opacity(0.18), lineWidth: 4).padding(-7)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Pal.acc, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-7)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }

    @ViewBuilder private var noteCircleContent: some View {
        if notePhase == .preview, let url = cam.outputURL {
            LoopingVideo(url: url)
        } else if store.fixture {
            Image(uiImage: fixtureNoteImage()).resizable().scaledToFill()
        } else if cam.ready {
            CameraPreview(session: cam.session)
        } else {
            ZStack {
                Color.black.opacity(0.4)
                ProgressView().tint(Pal.fg)
            }
        }
    }

    private func noteControl(icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: Circle(), interactive: true)
        .accessibilityLabel(label)
    }

    // MARK: действия

    private func send(_ conv: Conversation) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let reply = replyTo
        draft = ""
        store.drafts[convId] = ""
        haptic(.medium)
        withAnimation { sending.append(text); replyTo = nil }
        let ok = await store.send(conv.id, text: text, replyTo: reply?.id, translate: canTranslate)
        withAnimation { sending.removeAll { $0 == text } }
        if !ok { draft = text; replyTo = reply }
    }

    private func sendVoice() async {
        let sec = recorder.elapsed
        guard let url = recorder.finish() else {
            store.show("Слишком коротко — держи кнопку дольше", ok: false)
            return
        }
        haptic(.medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sendingVoice.append(sec) }
        await uploadAndSend(url: url, name: "Голосовое.m4a", mime: "audio/mp4", round: false)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sendingVoice.removeAll { $0 == sec } }
    }

    private func sendNote(_ url: URL) async {
        await uploadAndSend(url: url, name: "note.mov", mime: "video/quicktime", round: true)
    }

    private func uploadAndSend(url: URL, name: String, mime: String, round: Bool) async {
        if store.fixture { store.show("Отправлено"); return }
        uploading = true
        defer {
            uploading = false
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let data = try Data(contentsOf: url)
            let att = try await API.upload(data: data, name: name, mime: mime)
            let reply = replyTo
            if await store.send(convId, text: "", attachments: [att], round: round, replyTo: reply?.id) {
                withAnimation { replyTo = nil }
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    private func apply(_ intent: Intent, _ contact: Contact) async {
        guard let conv = store.conversation(convId), let m = conv.last else { return }
        let folderName = store.folder(key: intent.folderKey)?.name ?? intent.title
        var bodies: [[String: Any]] = []
        if intent.promise {
            let amount = store.dealDraft[contact.id] ?? Int(store.deals(of: contact.id).last { $0.status == "promised" }?.amount ?? 0)
            bodies.append(["type": "promise", "contactId": contact.id, "productId": NSNull(), "amount": amount, "remindAt": isoString(RemPreset.tomorrow.date)])
        } else {
            if let f = store.folder(key: intent.folderKey) {
                bodies.append(["type": "move", "contactId": contact.id, "folderId": f.id])
            }
            if intent.remind {
                let at = intent.folderKey == "thinking" ? RemPreset.twoDays.date : RemPreset.tomorrow.date
                bodies.append(["type": "remind", "contactId": contact.id, "at": isoString(at), "text": "Написать клиенту"])
            }
        }
        let ok = "Готово: «\(folderName)»" + (intent.remind ? ", напоминание стоит" : "")
        await store.perform(bodies, contactId: contact.id, ok: ok)
        store.hideHint(conv.id, lastMessageId: m.id)
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        uploading = true
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let ext = isVideo ? "mp4" : "jpg"
            let mime = isVideo ? "video/mp4" : "image/jpeg"
            var payload = data
            if !isVideo, let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) { payload = jpg }
            let att = try await API.upload(data: payload, name: "photo-\(Int(Date().timeIntervalSince1970)).\(ext)", mime: mime)
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.send(convId, text: text, attachments: [att], replyTo: replyTo?.id, translate: canTranslate) {
                draft = ""
                replyTo = nil
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    private func sendFile(_ url: URL) async {
        uploading = true
        defer { uploading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let att = try await API.upload(data: data, name: url.lastPathComponent, mime: mime)
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.send(convId, text: text, attachments: [att], replyTo: replyTo?.id, translate: canTranslate) {
                draft = ""
                replyTo = nil
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    #if DEBUG
    /// Снимки CI: `-scrollto <id>` — прокрутить ленту к сообщению (кружки, проигрывание голосового).
    private func fixtureScrollTarget() -> String? {
        guard store.fixture else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-scrollto"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Снимки CI: ответ, запись голосового, прослушивание, просмотр фото, кружок.
    private func applyFixtureScreen() {
        guard store.fixture else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return }
        let msgs = store.messages(convId)
        switch args[i + 1] {
        case "chat-reply":
            replyTo = msgs.last { !$0.isOut }
        case "chat-tr":
            inputFocused = true
        case "chat-tr-sheet":
            sheet = .translate
        case "chat-voice":
            recorder.phase = .locked
            recorder.elapsed = 7
            recorder.levels = (0..<70).map { k in CGFloat(0.2 + 0.7 * abs(sin(Double(k) / 3))) }
        case "chat-preview":
            recorder.phase = .preview
            recorder.elapsed = 12
            recorder.playProgress = 0.4
            recorder.levels = (0..<70).map { k in CGFloat(0.15 + 0.8 * abs(sin(Double(k) / 4))) }
        case "viewer":
            let items = mediaItems(msgs)
            if !items.isEmpty { viewer = ViewerState(items: items, start: 0) }
        case "note", "note-rec":
            videoMode = true
            notePhase = .recording
            cam.elapsed = 9
        case "note-lock":
            videoMode = true
            notePhase = .locked
            cam.elapsed = 23
        case "chat-voice-rec":
            recorder.phase = .recording
            recorder.elapsed = 4
            dragX = -34
        default: break
        }
    }
    #endif
}

// MARK: - пузырь

struct Bubble: View {
    let message: Message
    var highlighted = false
    var canUnsend = false
    var canReact = false
    var pinned = false
    var onReply: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenMedia: (Int) -> Void = { _ in }
    var onQuoteTap: (String) -> Void = { _ in }
    var onReact: (String?) -> Void = { _ in }
    var onPin: () -> Void = {}
    @State private var previewURL: URL?
    @State private var loadingFile = false
    @State private var swipe: CGFloat = 0

    var body: some View {
        let out = message.isOut
        let atts: [Attachment] = message.attachments ?? []
        let bare: Bool = atts.count == 1 && atts[0].round == true && message.body.isEmpty && message.replyTo == nil
        let voiceOnly: Bool = atts.count == 1 && atts[0].kind == "audio" && message.body.isEmpty
        let pad: CGFloat = bare || (atts.isEmpty && message.replyTo == nil) ? 0 : 4
        HStack {
            if out { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                if let q = message.replyTo {
                    quote(q, out: out)
                }
                ForEach(Array(atts.enumerated()), id: \.offset) { i, a in
                    attachment(a, index: i, out: out, showTime: voiceOnly)
                }
                if !message.body.isEmpty || atts.isEmpty {
                    textBlock(out: out)
                    if let link = message.firstLink {
                        LinkPreviewCard(url: link, out: out).padding(.horizontal, atts.isEmpty && message.replyTo == nil ? 6 : 0).padding(.bottom, 6)
                    }
                } else if !bare && !voiceOnly {
                    // кружок и голосовое показывают время сами (капсула у круга / строка под волной)
                    HStack { Spacer(); time(out: out) }.padding(.horizontal, 8).padding(.bottom, 2)
                }
            }
            .padding(.horizontal, pad)
            .padding(.vertical, pad)
            .background { if !bare { bubbleShape(out: out) } }
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Pal.acc, lineWidth: 2)
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu { menu(atts) }
            .overlay(alignment: out ? .bottomLeading : .bottomTrailing) { reactionsRow(out: out) }
            .padding(.bottom, (message.reactions ?? []).isEmpty ? 0 : 14)
            if !out { Spacer(minLength: 60) }
        }
        .overlay(alignment: .trailing) {
            if swipe < -8 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16)).foregroundStyle(Pal.fg)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Pal.fg.opacity(swipe < -55 ? 0.3 : 0.15)))
                    .offset(x: 40)
                    .opacity(Double(min(1, -swipe / 55)))
            }
        }
        .offset(x: swipe)
        .simultaneousGesture(swipeGesture)
        .quickLookPreview($previewURL)
    }

    /// Смахнуть пузырь влево — ответить (как в Telegram).
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                let dx: CGFloat = v.translation.width
                guard dx < 0, abs(dx) > abs(v.translation.height) * 2 else { return }
                let was: Bool = swipe < -55
                swipe = max(-80, dx)
                if !was && swipe < -55 { haptic() }
            }
            .onEnded { _ in
                if swipe < -55 { onReply() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipe = 0 }
            }
    }

    /// Реакции под пузырём, как в Telegram: наша подсвечена, нажатие снимает.
    @ViewBuilder private func reactionsRow(out: Bool) -> some View {
        let rx: [Reaction] = message.reactions ?? []
        if !rx.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(rx.enumerated()), id: \.offset) { _, r in
                    Button { if r.mine { onReact(nil) } } label: {
                        Text(r.emoji).font(.system(size: 14))
                            .padding(.horizontal, 7).frame(height: 24)
                            .background(Capsule().fill(r.mine ? Pal.acc.opacity(0.22) : Pal.bubIn))
                            .overlay(Capsule().stroke(Pal.line, lineWidth: 0.5))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .offset(x: out ? -6 : 6, y: 16)
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private func menu(_ atts: [Attachment]) -> some View {
        if canReact {
            let mine: String? = (message.reactions ?? []).first { $0.mine }?.emoji
            ControlGroup {
                ForEach(["👍", "❤️", "🔥", "🙏"], id: \.self) { e in
                    Button { onReact(mine == e ? nil : e) } label: { Text(e) }
                }
            }
            .controlGroupStyle(.compactMenu)
            Menu {
                ForEach(["😂", "👌", "🤝", "😢", "🎉", "👏"], id: \.self) { e in
                    Button { onReact(mine == e ? nil : e) } label: { Text(e) }
                }
                if mine != nil { Button(role: .destructive) { onReact(nil) } label: { Label("Убрать реакцию", systemImage: "xmark") } }
            } label: { Label("Ещё реакции", systemImage: "face.smiling") }
        }
        Button { onReply() } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") }
        Button { onPin() } label: { Label(pinned ? "Открепить" : "Закрепить", systemImage: pinned ? "pin.slash" : "pin") }
        if !message.body.isEmpty {
            Button { UIPasteboard.general.string = message.body } label: { Label("Скопировать", systemImage: "doc.on.doc") }
        }
        if let i = atts.firstIndex(where: { $0.kind == "image" || $0.kind == "video" }) {
            Button { onOpenMedia(i) } label: { Label("Открыть", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        if canUnsend {
            Button(role: .destructive) { onDelete() } label: { Label("Удалить у всех", systemImage: "trash") }
        }
    }

    private func quote(_ q: ReplyRef, out: Bool) -> some View {
        Button { onQuoteTap(q.id) } label: {
            HStack(spacing: 8) {
                Rectangle().fill(out ? Pal.onAcc.opacity(0.6) : Pal.acc).frame(width: 3).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 1) {
                    Text(q.dir == "out" ? "Вы" : "Клиент").font(Typo.body(12, .semibold))
                        .foregroundStyle(out ? Pal.onAcc.opacity(0.8) : Pal.acc)
                    Text(q.text).font(Typo.body(13)).lineLimit(2)
                        .foregroundStyle((out ? Pal.onAcc : Pal.fg).opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((out ? Pal.onAcc : Pal.fg).opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func bubbleShape(out: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: out ? 20 : 6, bottomTrailingRadius: out ? 6 : 20, topTrailingRadius: 20, style: .continuous)
        if out {
            shape.fill(Pal.acc)
        } else {
            shape.fill(Pal.bubIn)
                .overlay(shape.stroke(Pal.line, lineWidth: 0.5))
        }
    }

    private func time(out: Bool) -> some View {
        HStack(spacing: 3) {
            Text(Fmt.hm(message.date)).font(Typo.body(11))
            if out { DoubleCheck(size: 10) }
        }
        .foregroundStyle((out ? Pal.onAcc : Pal.fg).opacity(0.62))
    }

    private func textBlock(out: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message.body.isEmpty ? "Вложение" : message.body)
                .font(Typo.body(15.5))
                .foregroundStyle(out ? Pal.onAcc : Pal.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let tr = message.translation, !tr.text.isEmpty {
                Text((out ? "вы написали: " : "перевод: ") + tr.text)
                    .font(Typo.body(13))
                    .foregroundStyle((out ? Pal.onAcc : Pal.fg).opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            time(out: out)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder private func attachment(_ a: Attachment, index: Int, out: Bool, showTime: Bool = false) -> some View {
        let url = API.media(a.url)
        switch a.kind {
        case "image":
            Button { onOpenMedia(index) } label: {
                RemoteImage(raw: a.url)
                    .frame(width: 230, height: 180)
                    .background(placeholder("photo"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Фото, открыть")
        case "audio":
            AudioBubble(url: url, raw: a.url, out: out, message: message, showTime: showTime, mime: a.mime)
        case "video" where a.round == true:
            RoundNoteBubble(raw: a.url, out: out, message: message, onOpen: { onOpenMedia(index) })
        case "video":
            Button { onOpenMedia(index) } label: {
                ZStack {
                    if a.round == true {
                        LinearGradient(colors: [Pal.sky.opacity(0.45), Color(hex: 0xFFB8D6).opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Circle().stroke(Pal.fg.opacity(0.35), lineWidth: 1)
                    } else {
                        placeholder("video")
                    }
                    Image(systemName: "play.fill").font(.system(size: 24)).foregroundStyle(Pal.fg)
                        .frame(width: 54, height: 54).background(Circle().fill(Color.black.opacity(0.35)))
                }
                .frame(width: a.round == true ? 190 : 230, height: a.round == true ? 190 : 150)
                .clipShape(a.round == true ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(a.round == true ? "Кружок, смотреть" : "Видео, смотреть")
        default:
            Button { if let url { Task { await openFile(url, a) } } } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(out ? Pal.onAcc.opacity(0.12) : Pal.fg.opacity(0.15))
                        if loadingFile { ProgressView() } else { Image(systemName: "doc").font(.system(size: 16)) }
                    }
                    .frame(width: 38, height: 38)
                    Text(a.name ?? "Файл").font(Typo.body(14, .medium)).lineLimit(2)
                }
                .foregroundStyle(out ? Pal.onAcc : Pal.fg)
                .padding(8)
                .frame(maxWidth: 240, alignment: .leading)
            }
            .buttonStyle(PressStyle())
        }
    }

    private func placeholder(_ icon: String) -> some View {
        ZStack {
            LinearGradient(colors: [Pal.sky.opacity(0.35), Color(hex: 0xFFB8D6).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Pal.fg)
        }
    }

    /// Файл — во временную папку с правильным расширением (без него Quick Look показывает пустой экран).
    private func openFile(_ url: URL, _ a: Attachment) async {
        loadingFile = true
        defer { loadingFile = false }
        do {
            let data = try await API.download(url)
            var name = (a.name ?? "file").replacingOccurrences(of: "/", with: "_")
            if (name as NSString).pathExtension.isEmpty, let mime = a.mime, let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
                name += "." + ext
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + name)
            try data.write(to: dest)
            previewURL = dest
        } catch {}
    }
}

struct URLBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

/// Названия языков для подписи перевода: «на испанский», «на турецкий».
enum LangName {
    static let acc: [String: String] = [
        "en": "английский", "es": "испанский", "tr": "турецкий", "de": "немецкий", "fr": "французский", "it": "итальянский",
        "pt": "португальский", "pl": "польский", "uk": "украинский", "ar": "арабский", "zh": "китайский", "ja": "японский",
        "ko": "корейский", "nl": "нидерландский", "ka": "грузинский", "az": "азербайджанский", "kk": "казахский", "uz": "узбекский",
        "he": "иврит", "fa": "персидский", "hi": "хинди", "id": "индонезийский", "vi": "вьетнамский", "th": "тайский", "el": "греческий",
        "cs": "чешский", "ro": "румынский", "hu": "венгерский", "sv": "шведский", "fi": "финский", "da": "датский", "no": "норвежский",
    ]
    static func acc(_ code: String) -> String { acc[String(code.lowercased().prefix(2))] ?? "язык клиента" }
}


extension LangName {
    /// «на турецком»
    static func prep(_ code: String) -> String {
        let a = acc(code)
        if a.hasSuffix("ий") { return String(a.dropLast(2)) + "ом" }
        return a
    }
}

/// Подсказка один раз: пишите по-русски — переведём.
struct ChatTranslateHint: View {
    let langName: String
    let done: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: done)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "globe").font(.system(size: 26, weight: .semibold))
                Text("Пишите по-русски").font(Typo.display(20))
                Text("Сообщения клиента переводятся на русский, а ваш ответ уйдёт на \(langName) автоматически. Перевод выключается значком языка в шапке чата.")
                    .font(Typo.body(15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
                Button(action: done) {
                    Text("Понятно").font(Typo.body(16, .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Pal.fg)
            .padding(20)
            .glassRect(28)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

/// Лист «Перевод переписки»: что происходит и переключатель перевода исходящих.
struct TranslateSheet: View {
    @Environment(Store.self) private var store
    let lang: String

    var body: some View {
        SheetBox(title: "Перевод переписки", subtitle: "Клиент пишет на \(LangName.prep(lang))") {
            Text("Входящие переводим на русский автоматически — перевод под сообщением. Вы пишете по-русски, а клиенту уходит на \(LangName.acc(lang)).")
                .font(Typo.body(14)).foregroundStyle(Pal.fg2).lineSpacing(3)
                .padding(.horizontal, 8).padding(.bottom, 6)
            SheetOption(icon: "globe", title: "Переводить мои ответы", subtitle: store.translateOut ? "уйдёт на \(LangName.acc(lang))" : "уйдёт как написано", action: {
                withAnimation(.spring(response: 0.3)) { store.translateOut.toggle() }
            }) {
                GlassSwitch(isOn: Binding(get: { store.translateOut }, set: { store.translateOut = $0 }))
            }
        }
    }
}

/// Высота нижней панели чата (поле ввода + ответ/подсказка).
private struct ChatBottomHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
