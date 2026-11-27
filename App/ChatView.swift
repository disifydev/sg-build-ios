import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers

/// Чат: шапка со стеклом, закреплённое, лента, ответ/правка, шаблоны, отложенная отправка, голосовые и кружки.
struct ChatView: View {
    @Environment(Store.self) private var store
    let convId: String

    @State private var draft = ""
    @State private var replyTo: Message?
    @State private var editing: Message?
    @State private var selecting: Set<String>? = nil
    @State private var showTemplates = false
    @State private var ctx: Message?
    @State private var frames: [String: CGRect] = [:]
    @State private var ctxFrame: CGRect = .zero
    @State private var delIds: [String]? = nil
    @State private var circleMode = false
    @StateObject private var rec = VoiceRecorder()
    @StateObject private var cam = CircleRecorder()
    @State private var recDX: CGFloat = 0
    @State private var recDY: CGFloat = 0
    @State private var pressTask: Task<Void, Never>?
    @State private var pressed = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var uploading = false
    @State private var scrollTo: String?
    @State private var blockAsk = false
    @State private var delChat: Conversation?
    @FocusState private var focused: Bool

    private let rx = ["👍", "❤️", "🔥", "🙏", "😂", "👌", "🤝"]

    var body: some View {
        let conv = store.conversation(convId)
        ZStack {
            Aurora()
            if let conv {
                feed(conv)
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: topInset(conv)) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { if selecting == nil { compose(conv) } }
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: Th.cream, location: 0), .init(color: Th.cream.opacity(0.9), location: 0.6), .init(color: Th.cream.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: topInset(conv) + 80)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                topArea(conv).frame(maxHeight: .infinity, alignment: .top)
                if cam.active || store.demoChatOverlay == "circle" { CircleOverlay(cam: cam, demo: store.demoChatOverlay == "circle").zIndex(8) }
                if let m = ctx { contextOverlay(conv, m).zIndex(9) }
            } else {
                VStack {
                    TopBar(back: { store.pop() })
                    EmptyBlock(icon: "chat", title: "Чат не найден", text: "Возможно, его удалили")
                    Spacer()
                }
            }
        }
        .onAppear(perform: appear)
        .onDisappear {
            store.saveDraft(convId, editing == nil ? draft : "")
            rec.cancel(); cam.stop(send: false)
        }
        .task { await store.loadHistory(convId) }
        .task { await store.loadScheduled(convId) }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItem) { _, item in if let item { Task { await sendPhoto(item) } } }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { r in
            if case .success(let url) = r { Task { await sendFile(url) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attachPick)) { n in
            guard (n.object as? String) == convId, let what = n.userInfo?["what"] as? String else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                switch what {
                case "photo": showPhotos = true
                case "file": showFiles = true
                case "templates": withAnimation { showTemplates = true }
                default: break
                }
            }
        }
        .confirmationDialog(delIds.map { $0.count > 1 ? "Удалить \($0.count) \(pl($0.count, "сообщение", "сообщения", "сообщений"))?" : "Удалить сообщение?" } ?? "",
                            isPresented: Binding(get: { delIds != nil }, set: { if !$0 { delIds = nil } }), titleVisibility: .visible) {
            Button("Удалить у себя и у собеседника", role: .destructive) { deleteSelected(everyone: true) }
            Button("Удалить только у себя", role: .destructive) { deleteSelected(everyone: false) }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Заблокировать клиента?", isPresented: $blockAsk, titleVisibility: .visible) {
            Button(conv?.isBlocked == true ? "Разблокировать" : "Заблокировать", role: .destructive) {
                if let c = conv { Task { await store.block(c.contactId, !c.isBlocked) } }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("В Telegram и WhatsApp по QR блокировка ставится и в самом мессенджере, в других сетях — только в Sguardo.") }
        .chatDeleteDialog($delChat)
        .simultaneousGesture(backSwipe)
        .onReceive(NotificationCenter.default.publisher(for: .circleLimit)) { _ in
            if rec.recording, circleMode, let c = store.conversation(convId) { finishRecording(c) }
        }
    }

    private func appear() {
        store.markRead(convId)
        if draft.isEmpty, let d = store.serverDrafts[convId] { draft = d }
        #if DEBUG
        if store.fixture, let o = store.demoChatOverlay {
            if o == "context", let m = store.messages(convId).first(where: { $0.isOut && $0.kind == "text" }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ctxFrame = frames[m.id] ?? CGRect(x: 90, y: 300, width: 280, height: 80); withAnimation { ctx = m } }
            }
            if o == "reply", let m = store.messages(convId).last(where: { !$0.isOut }) { replyTo = m; draft = "Можно в четверг в 18:30" }
            if o == "templates" { showTemplates = true }
            if o == "voice" { rec.demo() }
            if o == "select" { selecting = Set(store.messages(convId).suffix(2).map(\.id)) }
        }
        #endif
    }

    /// Свайп вправо из любого места — назад (как в Telegram).
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard ctx == nil, !rec.recording, !cam.active else { return }
                if v.translation.width > 110 && abs(v.translation.height) < 60 { store.pop() }
            }
    }

    // MARK: шапка

    @ViewBuilder private func topArea(_ conv: Conversation) -> some View {
        VStack(spacing: 8) {
            if selecting != nil { selectHeader } else { header(conv) }
            if selecting == nil, let pid = conv.pins.first, let pm = store.messages(convId).first(where: { $0.id == pid }) {
                pinBar(pm)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func topInset(_ conv: Conversation) -> CGFloat {
        let pin = selecting == nil && conv.pins.first.map { id in store.messages(convId).contains { $0.id == id } } == true
        return 52 + 8 + (pin ? 54 : 0)
    }

    private func header(_ conv: Conversation) -> some View {
        let c = store.contact(conv.contactId)
        return HStack(spacing: 8) {
            GlassCircle(icon: "chevL", label: "Назад") { store.pop() }
            Button { if let c { store.open(.profile(c.id)) } } label: {
                HStack(spacing: 9) {
                    Avatar(name: store.avatarName(c), network: conv.network, size: 38, url: c?.avatar)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.name(c)).font(Typo.body(15, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                        subLine(conv, c)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 5).padding(.trailing, 14)
                .frame(height: 48)
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .glassCapsule(interactive: true)
            Menu { chatMenu(conv, c) } label: {
                Icon(name: "more").foregroundStyle(Th.fg).frame(width: 44, height: 44).glass(Circle(), interactive: true)
            }
            .accessibilityLabel("Ещё")
        }
    }

    @ViewBuilder private func subLine(_ conv: Conversation, _ c: Contact?) -> some View {
        if let s = store.statusLine(convId) {
            Text(s).font(Typo.body(11.5)).foregroundStyle(Th.teal).lineLimit(1)
        } else if let c, store.bookName(c) != nil {
            HStack(spacing: 4) {
                Icon(name: "book", size: 11)
                Text("в контактах · " + (store.phoneOf(c) ?? ""))
            }
            .font(Typo.body(11.5)).foregroundStyle(Th.muted).lineLimit(1)
        } else {
            Text(Net.name(conv.network) + ((c?.handle ?? c?.phone).map { " · " + $0 } ?? ""))
                .font(Typo.body(11.5)).foregroundStyle(Th.muted).lineLimit(1)
        }
    }

    @ViewBuilder private func chatMenu(_ conv: Conversation, _ c: Contact?) -> some View {
        if let c { Button { store.open(.profile(c.id)) } label: { Label("Профиль", systemImage: "person") } }
        if let url = netURL(conv, c) {
            Button { UIApplication.shared.open(url) } label: { Label("Открыть в " + Net.name(conv.network), systemImage: "arrow.up.right.square") }
        }
        Button { store.setFlag(conv.id, "pinned", !conv.isPinned, toast: conv.isPinned ? "Чат откреплён" : "Чат закреплён") } label: {
            Label(conv.isPinned ? "Открепить" : "Закрепить", systemImage: "pin")
        }
        Button { store.setFlag(conv.id, "muted", !conv.isMuted, toast: conv.isMuted ? "Уведомления включены" : "Уведомления выключены") } label: {
            Label(conv.isMuted ? "Включить уведомления" : "Выключить уведомления", systemImage: conv.isMuted ? "bell" : "bell.slash")
        }
        Button { withAnimation { selecting = [] } } label: { Label("Выбрать сообщения", systemImage: "checkmark.circle") }
        Button { blockAsk = true } label: { Label(conv.isBlocked ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised") }
        Button(role: .destructive) { delChat = conv } label: { Label("Удалить чат", systemImage: "trash") }
    }

    private func netURL(_ conv: Conversation, _ c: Contact?) -> URL? {
        let h = (c?.handle ?? "").replacingOccurrences(of: "@", with: "")
        let phone = c.flatMap { store.phoneOf($0) }?.filter(\.isNumber) ?? ""
        switch conv.network {
        case "telegram": return h.isEmpty || PhoneBook.looksLikePhone(h) ? nil : URL(string: "https://t.me/" + h)
        case "whatsapp": return phone.isEmpty ? nil : URL(string: "https://wa.me/" + phone)
        case "instagram": return h.isEmpty ? nil : URL(string: "https://instagram.com/" + h)
        case "vk": return h.isEmpty ? nil : URL(string: "https://vk.com/" + h)
        default: return nil
        }
    }

    private var selectHeader: some View {
        HStack(spacing: 8) {
            GlassCap(title: "Отмена") { withAnimation { selecting = nil } }
            Text("Выбрано: \(selecting?.count ?? 0)").font(Typo.body(15, .semibold)).foregroundStyle(Th.fg).frame(maxWidth: .infinity)
            GlassCircle(icon: "fwd", label: "Переслать") {
                guard let s = selecting, !s.isEmpty else { store.show("Выберите сообщения"); return }
                store.sheet = .forward(conv: convId, mids: Array(s))
                selecting = nil
            }
            GlassCircle(icon: "trash", label: "Удалить") {
                guard let s = selecting, !s.isEmpty else { store.show("Выберите сообщения"); return }
                delIds = Array(s)
            }
            .foregroundStyle(Th.danger)
        }
        .frame(height: 52)
    }

    private func pinBar(_ m: Message) -> some View {
        HStack(spacing: 6) {
            Button { scrollTo = m.id } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Закреплённое сообщение").font(Typo.body(12, .semibold)).foregroundStyle(Th.teal)
                    Text(m.preview).font(Typo.body(13.5)).foregroundStyle(Th.fg).lineLimit(1)
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Th.teal).frame(width: 3).padding(.vertical, 2).offset(x: -3) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { store.pinMessage(convId, m, false) } label: {
                Icon(name: "x", size: 16).foregroundStyle(Th.muted).frame(width: 36, height: 36)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Открепить")
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 46)
        .glassCapsule()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: лента

    private func feed(_ conv: Conversation) -> some View {
        let list = store.messages(convId)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if store.historyMore[convId] == true {
                        ProgressView().padding(8).onAppear { Task { await store.loadOlder(convId) } }
                    }
                    if store.offline || store.demo == .offline {
                        HStack(spacing: 4) { Icon(name: "wifiOff", size: 13); Text("нет сети: показываем сохранённое") }
                            .font(Typo.body(12, .semibold)).foregroundStyle(Th.muted).padding(.vertical, 6)
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                        let prev = i > 0 ? list[i - 1] : nil
                        if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: m.date) {
                            Text(Fmt.dayChip(m.date)).font(Typo.body(12, .semibold)).foregroundStyle(Th.muted)
                                .padding(.horizontal, 12).padding(.vertical, 5).padding(.vertical, 8)
                        }
                        MessageRow(m: m, conv: conv, gap: prev != nil && prev!.dir != m.dir, selecting: selecting != nil,
                                   picked: selecting?.contains(m.id) ?? false, hidden: ctx?.id == m.id,
                                   onReply: { startReply(m) }, onLong: { openCtx(m) }, onToggle: { toggle(m) })
                            .id(m.id)
                            .background(GeometryReader { g in Color.clear.preference(key: FramesKey.self, value: [m.id: g.frame(in: .global)]) })
                    }
                    if let t = store.typing[convId], Date().timeIntervalSince(t.at) < 5 {
                        TypingBubble().frame(maxWidth: .infinity, alignment: .leading).id("typing")
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onPreferenceChange(FramesKey.self) { frames = $0 }
            .onChange(of: list.count) { _, _ in withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: scrollTo) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
                scrollTo = nil
            }
        }
    }

    private func startReply(_ m: Message) {
        editing = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { replyTo = m }
        focused = true
        haptic()
    }

    private func toggle(_ m: Message) {
        guard var s = selecting else { return }
        if s.contains(m.id) { s.remove(m.id) } else { s.insert(m.id) }
        selecting = s
        haptic()
    }

    private func openCtx(_ m: Message) {
        guard selecting == nil, !m.id.hasPrefix("tmp-") else { return }
        ctxFrame = frames[m.id] ?? .zero
        focused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { ctx = m }
    }

    private func closeCtx() { withAnimation(.easeOut(duration: 0.2)) { ctx = nil } }

    // MARK: меню сообщения

    private func contextOverlay(_ conv: Conversation, _ m: Message) -> some View {
        GeometryReader { g in
            let items = menuItems(conv, m)
            let rxH: CGFloat = canReact(conv) ? 51 : 0
            let menuH = CGFloat(items.count) * 44 + 12 + (m.isOut ? 42 : 0)
            let bh = max(40, ctxFrame.height)
            let want = ctxFrame.minY - rxH - 8
            let topY = max(60, min(want, g.size.height - (rxH + bh + menuH + 24) - 28))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.12))
                    .ignoresSafeArea()
                    .onTapGesture { closeCtx() }
                    .transition(.opacity)
                VStack(alignment: m.isOut ? .trailing : .leading, spacing: 8) {
                    if canReact(conv) { reactionBar(conv, m) }
                    BubbleBody(m: m, conv: conv, interactive: false)
                        .frame(width: ctxFrame.width > 0 ? min(ctxFrame.width, g.size.width - 24) : nil, alignment: m.isOut ? .trailing : .leading)
                        .scaleEffect(1.02, anchor: m.isOut ? .trailing : .leading)
                    msgMenu(items, m)
                        .transition(.scale(scale: 0.5, anchor: m.isOut ? .topTrailing : .topLeading).combined(with: .opacity))
                }
                .frame(width: g.size.width - 24, alignment: m.isOut ? .trailing : .leading)
                .padding(.horizontal, 12)
                .offset(y: topY)
            }
        }
        .ignoresSafeArea()
    }

    private func canReact(_ conv: Conversation) -> Bool { conv.network == "telegram" || conv.network == "whatsapp" }

    private func reactionBar(_ conv: Conversation, _ m: Message) -> some View {
        let mine = m.reactions?.first { $0.mine }?.emoji
        return HStack(spacing: 0) {
            ForEach(Array(rx.enumerated()), id: \.offset) { i, e in
                ReactionButton(emoji: e, on: mine == e, delay: Double(i) * 0.028) {
                    store.react(convId, m, mine == e ? nil : e)
                    closeCtx()
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .glassCapsule(strong: true)
    }

    private struct MenuItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        var danger = false
    }

    private func menuItems(_ conv: Conversation, _ m: Message) -> [MenuItem] {
        var out = [MenuItem(id: "reply", title: "Ответить", icon: "reply")]
        switch m.kind {
        case "text": out.append(MenuItem(id: "copy", title: "Скопировать", icon: "copy"))
        case "image": out.append(MenuItem(id: "save", title: "Сохранить фото", icon: "save"))
        case "video", "round": out.append(MenuItem(id: "save", title: "Сохранить видео", icon: "save"))
        case "audio": out.append(MenuItem(id: "save", title: "Сохранить аудио", icon: "save"))
        default: out.append(MenuItem(id: "save", title: "Сохранить файл", icon: "save"))
        }
        if m.isOut && m.kind == "text" { out.append(MenuItem(id: "edit", title: "Изменить", icon: "edit")) }
        out.append(MenuItem(id: "pin", title: conv.pins.contains(m.id) ? "Открепить" : "Закрепить", icon: "pin"))
        out.append(MenuItem(id: "fwd", title: "Переслать", icon: "fwd"))
        out.append(MenuItem(id: "del", title: "Удалить", icon: "trash", danger: true))
        out.append(MenuItem(id: "sel", title: "Выбрать", icon: "selc"))
        return out
    }

    private func msgMenu(_ items: [MenuItem], _ m: Message) -> some View {
        VStack(spacing: 0) {
            if m.isOut {
                HStack(spacing: 6) {
                    Icon(name: "checks", size: 13)
                    Text("Отправлено " + Fmt.whenFull(m.date))
                }
                .font(Typo.body(12.5)).foregroundStyle(Th.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).frame(height: 38)
                Rectangle().fill(Th.hair).frame(height: 0.5).padding(.bottom, 4)
            }
            ForEach(items) { it in
                Button { run(it.id, m) } label: {
                    HStack(spacing: 14) {
                        Text(it.title).font(Typo.body(15))
                        Spacer()
                        Icon(name: it.icon, size: 16)
                    }
                    .foregroundStyle(it.danger ? Th.danger : Th.fg)
                    .padding(.horizontal, 14).frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
            }
        }
        .padding(6)
        .frame(width: 236)
        .glassRect(24, strong: true)
    }

    private func run(_ id: String, _ m: Message) {
        closeCtx()
        switch id {
        case "reply": startReply(m)
        case "copy": UIPasteboard.general.string = m.body; store.show("Текст скопирован")
        case "save": Task { await MediaSaver.save(m, store: store) }
        case "edit":
            replyTo = nil
            editing = m
            draft = m.body
            focused = true
        case "pin": store.pinMessage(convId, m, !(store.conversation(convId)?.pins.contains(m.id) ?? false))
        case "fwd": store.sheet = .forward(conv: convId, mids: [m.id])
        case "del": delIds = [m.id]
        case "sel": withAnimation { selecting = [m.id] }
        default: break
        }
    }

    private func deleteSelected(everyone: Bool) {
        guard let ids = delIds else { return }
        delIds = nil
        selecting = nil
        Task { await store.deleteMessages(convId, ids, everyone: everyone) }
    }

    // MARK: поле ввода

    private func compose(_ conv: Conversation) -> some View {
        let has = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let planned = (store.scheduled[convId] ?? []).filter { $0.status != "sent" }
        return VStack(alignment: .leading, spacing: 6) {
            if !planned.isEmpty && !rec.recording {
                Button { store.sheet = .scheduledList(conv: convId) } label: {
                    HStack(spacing: 6) {
                        Icon(name: "clock", size: 14)
                        Text("Запланировано: \(planned.count)").font(Typo.body(13, .semibold))
                        if planned.contains(where: { $0.status == "failed" }) { Text("· не отправлено").font(Typo.body(13)).foregroundStyle(Th.danger) }
                    }
                    .foregroundStyle(Th.teal)
                    .padding(.horizontal, 12).frame(height: 32)
                    .glassCapsule()
                }
                .buttonStyle(PressStyle())
            }
            if showTemplates { templates }
            if let e = editing { cbar(icon: "edit", title: "Редактирование", text: e.preview) { editing = nil; draft = "" } }
            else if let r = replyTo {
                cbar(icon: "reply", title: r.isOut ? "Ответ на своё сообщение" : store.name(store.contact(conv.contactId)), text: r.preview) { replyTo = nil }
            }
            HStack(alignment: .bottom, spacing: 8) {
                GlassCircle(icon: "clip", label: "Вложения") { store.sheet = .attach(conv: convId) }
                    .opacity(rec.recording ? 0 : 1)
                inputField(has)
                sendButton(has, conv)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .overlay(alignment: .bottomTrailing) { if rec.recording { recordControls } }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: replyTo?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: editing?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showTemplates)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: rec.recording)
    }

    private func inputField(_ has: Bool) -> some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 4) {
                TextField("", text: $draft, prompt: Text("Сообщение").foregroundColor(Th.faint), axis: .vertical)
                    .font(Typo.body(15.5)).foregroundStyle(Th.fg)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.vertical, 13)
                    .accessibilityLabel("Сообщение")
                Button { withAnimation { showTemplates.toggle() } } label: {
                    Icon(name: "bolt", size: 16).foregroundStyle(showTemplates ? Th.teal : Th.muted).frame(width: 36, height: 46)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Шаблоны")
                Button {
                    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { store.show("Сначала напишите сообщение"); return }
                    store.sheet = .schedSend(conv: convId, text: t)
                    draft = ""
                } label: {
                    Icon(name: "clock", size: 16).foregroundStyle(Th.muted).frame(width: 36, height: 46)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Отправить позже")
            }
            .padding(.leading, 16).padding(.trailing, 6)
            .opacity(rec.recording ? 0 : 1)
            if rec.recording { recordStrip }
        }
        .frame(minHeight: 48)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func sendButton(_ has: Bool, _ conv: Conversation) -> some View {
        if has || editing != nil {
            Button { Task { await sendText(conv) } } label: {
                Icon(name: editing != nil ? "check" : "send").foregroundStyle(Th.onTeal)
                    .frame(width: 48, height: 48).background(Circle().fill(Th.teal))
                    .transition(.scale.combined(with: .opacity))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(editing != nil ? "Сохранить" : "Отправить")
        } else {
            Icon(name: circleMode ? "vcirc" : "mic").foregroundStyle(Th.fg)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .glass(Circle())
                .opacity(rec.recording ? 0 : 1)
                .scaleEffect(pressed ? 0.9 : 1)
                .gesture(recordGesture(conv))
                .accessibilityLabel(circleMode ? "Кружок: удерживайте, чтобы записать" : "Голосовое: удерживайте, чтобы записать")
                .accessibilityAction { toggleMode() }
        }
    }

    private func toggleMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { circleMode.toggle() }
        store.show(circleMode ? "Кружок: удерживайте, чтобы записать" : "Голосовое: удерживайте, чтобы записать")
    }

    /// Удержание: запись; влево — отмена, вверх — замочек. Короткое нажатие меняет голосовое ↔ кружок.
    private func recordGesture(_ conv: Conversation) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if !pressed {
                    pressed = true
                    pressTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        if Task.isCancelled { return }
                        startRecording()
                    }
                }
                guard recording, !locked else { return }
                recDX = min(0, v.translation.width)
                recDY = min(0, v.translation.height)
                if recDY < -70 { lockRecording() } else if recDX < -120 { cancelRecording() }
            }
            .onEnded { _ in
                pressTask?.cancel()
                let wasRecording = recording
                pressed = false
                if wasRecording {
                    if !locked { finishRecording(conv) }
                } else if !justCancelled {
                    toggleMode()
                }
                justCancelled = false
                recDX = 0; recDY = 0
            }
    }

    @State private var justCancelled = false
    private var recording: Bool { rec.recording }
    private var locked: Bool { rec.locked }

    private func startRecording() {
        haptic(.medium)
        if circleMode { cam.start() }
        rec.start(withCamera: circleMode)
    }

    private func lockRecording() {
        haptic(.rigid)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { rec.locked = true }
        recDX = 0; recDY = 0
    }

    private func cancelRecording() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        justCancelled = true
        rec.cancel()
        cam.stop(send: false)
        recDX = 0; recDY = 0
    }

    private func finishRecording(_ conv: Conversation) {
        let secs = rec.elapsed
        if secs < 0.7 {
            rec.cancel(); cam.stop(send: false)
            store.show(circleMode ? "Удерживайте, чтобы записать кружок" : "Удерживайте, чтобы записать голосовое")
            return
        }
        haptic(.medium)
        if circleMode {
            rec.cancel()
            cam.stop(send: true) { url in
                guard let url else { store.show("Не получилось записать кружок", ok: false); return }
                Task { await upload(url: url, name: "circle-\(Int(Date().timeIntervalSince1970)).mp4", mime: "video/mp4", round: true) }
            }
        } else {
            guard let url = rec.stop() else { return }
            Task { await upload(url: url, name: "voice-\(Int(Date().timeIntervalSince1970)).m4a", mime: "audio/mp4", round: false) }
        }
    }

    private var recordStrip: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: 0xE5484D)).frame(width: 10, height: 10).opacity(rec.blink ? 0.2 : 1)
            Text(rec.timeText).font(Typo.body(15)).monospacedDigit().foregroundStyle(Th.fg).frame(minWidth: 56, alignment: .leading)
            if rec.locked {
                Button("Отмена") { cancelRecording() }.font(Typo.body(15, .semibold)).foregroundStyle(Th.teal).frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 2) { Icon(name: "chevL", size: 16); Text("Влево — отмена") }
                    .font(Typo.body(14)).foregroundStyle(Th.muted)
                    .frame(maxWidth: .infinity)
                    .offset(x: recDX * 0.7)
                    .opacity(Double(max(0, 1 + recDX / 140)))
            }
        }
        .padding(.leading, 14).padding(.trailing, 44)
    }

    private var recordControls: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 6) {
                Icon(name: rec.locked ? "lock" : "lockO", size: 16)
                if !rec.locked { Icon(name: "chevU", size: 13) }
            }
            .foregroundStyle(Th.fg)
            .frame(width: 42, height: rec.locked ? 42 : 84)
            .glassCapsule()
            .offset(x: -25, y: rec.locked ? -112 : -96 + max(recDY * 0.75, -56))
            ZStack {
                Circle().fill(Th.teal.opacity(0.24)).frame(width: 116, height: 116).scaleEffect(1 + min(1, rec.level) * 0.6)
                Button {
                    if rec.locked, let conv = store.conversation(convId) { finishRecording(conv) }
                } label: {
                    Icon(name: rec.locked ? "send" : (circleMode ? "vcirc" : "mic"), size: 28).foregroundStyle(Th.onTeal)
                        .frame(width: 92, height: 92).background(Circle().fill(Th.teal))
                        .shadow(color: Th.teal.opacity(0.6), radius: 14, y: 10)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(rec.locked)
            }
            .frame(width: 92, height: 92)
            .offset(x: 22 + recDX * 0.55, y: 22 + recDY * 0.6)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var templates: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if store.state.templates.isEmpty {
                    Text("Шаблонов пока нет, их можно добавить в веб-кабинете").font(Typo.body(13)).foregroundStyle(Th.muted)
                        .padding(.horizontal, 14).frame(height: 36).glassCapsule(strong: true)
                }
                ForEach(store.state.templates) { t in
                    Button {
                        draft = t.text
                        focused = true
                        withAnimation { showTemplates = false }
                    } label: {
                        Text(t.title.isEmpty ? t.text : t.title).font(Typo.body(13.5, .medium)).foregroundStyle(Th.fg).lineLimit(1)
                            .padding(.horizontal, 14).frame(height: 36)
                    }
                    .buttonStyle(PressStyle())
                    .glassCapsule(strong: true)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func cbar(icon: String, title: String, text: String, close: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Icon(name: icon, size: 16).foregroundStyle(Th.teal)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Typo.body(13, .bold)).foregroundStyle(Th.teal)
                Text(text).font(Typo.body(13)).foregroundStyle(Th.muted).lineLimit(1)
            }
            .padding(.leading, 8)
            .overlay(alignment: .leading) { Rectangle().fill(Th.teal).frame(width: 3) }
            Spacer(minLength: 0)
            Button(action: close) { Icon(name: "x", size: 16).foregroundStyle(Th.muted).frame(width: 36, height: 36) }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Отменить")
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .glassRect(22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: отправка

    private func sendText(_ conv: Conversation) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = editing {
            editing = nil
            draft = ""
            if !text.isEmpty && text != e.body { await store.editMessage(convId, e, text) }
            return
        }
        guard !text.isEmpty else { return }
        let r = replyTo?.id
        draft = ""
        replyTo = nil
        withAnimation { showTemplates = false }
        haptic(.medium)
        store.saveDraft(convId, "")
        if !(await store.send(convId, text: text, replyTo: r)) { draft = text }
    }

    private func upload(url: URL, name: String, mime: String, round: Bool) async {
        if store.fixture {
            _ = await store.send(convId, text: "", attachments: [Attachment(kind: mime.hasPrefix("audio") ? "audio" : "video", name: name, url: "fixture:" + (round ? "cam" : "voice"), mediaId: "x", mime: mime, round: round, duration: 3)])
            return
        }
        uploading = true
        defer { uploading = false }
        do {
            let data = try Data(contentsOf: url)
            var att = try await API.upload(data: data, name: name, mime: mime)
            if round { att = Attachment(kind: att.kind, name: att.name, url: att.url, mediaId: att.mediaId, mime: att.mime, round: true) }
            _ = await store.send(convId, text: "", attachments: [att], replyTo: replyTo?.id)
            replyTo = nil
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        uploading = true
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            var payload = data
            if !isVideo, let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) { payload = jpg }
            let att = try await API.upload(data: payload, name: "photo-\(Int(Date().timeIntervalSince1970)).\(isVideo ? "mp4" : "jpg")", mime: isVideo ? "video/mp4" : "image/jpeg")
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.send(convId, text: text, attachments: [att], replyTo: replyTo?.id) { draft = ""; replyTo = nil }
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
            if await store.send(convId, text: "", attachments: [att], replyTo: replyTo?.id) { replyTo = nil }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }
}

extension Notification.Name {
    static let attachPick = Notification.Name("sguardo.attachPick")
}

struct FramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

private struct ReactionButton: View {
    let emoji: String
    let on: Bool
    let delay: Double
    let action: () -> Void
    @State private var shown = false
    var body: some View {
        Button(action: action) {
            Text(emoji).font(.system(size: 24))
                .frame(width: 41, height: 41)
                .background(Circle().fill(on ? Th.teal.opacity(0.2) : .clear))
        }
        .buttonStyle(PressStyle())
        .scaleEffect(shown ? 1 : 0.1).offset(y: shown ? 0 : 12).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(delay)) { shown = true } }
        .accessibilityLabel("Реакция \(emoji)")
    }
}

// MARK: - строка сообщения

/// Форма пузыря: скругление 20, «хвостик» 6 снизу со стороны отправителя.
struct BubbleShape: Shape {
    let out: Bool
    func path(in r: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: out ? 20 : 6, bottomTrailingRadius: out ? 6 : 20, topTrailingRadius: 20, style: .continuous)
            .path(in: r)
    }
}

struct MessageRow: View {
    let m: Message
    let conv: Conversation
    let gap: Bool
    let selecting: Bool
    let picked: Bool
    let hidden: Bool
    let onReply: () -> Void
    let onLong: () -> Void
    let onToggle: () -> Void
    @State private var dx: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            if selecting {
                ZStack {
                    Circle().stroke(picked ? Color.clear : Th.faint, lineWidth: 1.6)
                    if picked { Circle().fill(Th.teal); Icon(name: "check", size: 13).foregroundStyle(Th.onTeal) }
                }
                .frame(width: 24, height: 24)
                .transition(.scale.combined(with: .opacity))
            }
            if m.isOut { Spacer(minLength: 50) }
            BubbleBody(m: m, conv: conv, interactive: !selecting)
                .offset(x: dx)
                .opacity(hidden ? 0 : 1)
                .onLongPressGesture(minimumDuration: 0.4) { if !selecting { onLong() } }
            if !m.isOut { Spacer(minLength: 50) }
        }
        .overlay(alignment: .trailing) {
            Icon(name: "reply", size: 16).foregroundStyle(Th.fg)
                .frame(width: 32, height: 32).background(Circle().fill(Th.glass2))
                .opacity(Double(min(1, -dx / 55)))
                .scaleEffect(0.4 + min(1, -dx / 55) * 0.6)
                .padding(.trailing, 2)
                .allowsHitTesting(false)
        }
        .padding(.top, gap ? 8 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if selecting { onToggle() } }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    guard !selecting, abs(v.translation.width) > abs(v.translation.height) * 1.2, v.translation.width < 0 else { return }
                    var x = v.translation.width
                    if x < -60 { x = -60 + (x + 60) * 0.3 }
                    dx = x
                }
                .onEnded { _ in
                    if dx < -45 { onReply() }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.6)) { dx = 0 }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selecting)
    }
}

/// Содержимое пузыря: текст, ответ, голосовое, фото, кружок, файл; время и галочки; реакции.
struct BubbleBody: View {
    @Environment(Store.self) private var store
    let m: Message
    let conv: Conversation
    var interactive = true

    var body: some View {
        switch m.kind {
        case "round": RoundVideo(m: m, interactive: interactive)
        default: bubble
        }
    }

    private var out: Bool { m.isOut }
    private var fg: Color { out ? Th.bubOutFg : Th.fg }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(BubbleShape(out: out).fill(out ? Th.bubOut : Th.bubIn))
        .overlay { if !out { BubbleShape(out: false).stroke(Th.glassEdge, lineWidth: 0.5) } }
        .clipShape(BubbleShape(out: out))
        .contentShape(BubbleShape(out: out))
    }

    @ViewBuilder private var content: some View {
        switch m.kind {
        case "audio":
            VStack(alignment: .leading, spacing: 2) {
                VoiceBubble(m: m, out: out)
                if let t = m.transcript?.text, !t.isEmpty { Text(t).font(Typo.body(13)).foregroundStyle(fg.opacity(0.8)).padding(.horizontal, 6) }
                reactionsRow
                HStack { Spacer(); meta }
            }
            .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 4)
            .frame(minWidth: 210)
        case "image":
            VStack(alignment: .leading, spacing: 0) {
                PhotoThumb(a: m.att!, interactive: interactive)
                    .frame(width: 238, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if !m.body.isEmpty { Text(m.body).font(Typo.body(15)).foregroundStyle(fg) }
                    reactionsRow
                    HStack { Spacer(); meta }
                }
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
                .frame(width: 238, alignment: .leading)
            }
            .padding(4)
        case "video":
            VStack(alignment: .leading, spacing: 0) {
                VideoThumb(a: m.att!, interactive: interactive)
                    .frame(width: 238, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack { if !m.body.isEmpty { Text(m.body).font(Typo.body(15)).foregroundStyle(fg) }; Spacer(); meta }
                    .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            }
            .padding(4)
        case "text":
            textBlock
        default:
            VStack(alignment: .leading, spacing: 2) {
                FileRow(a: m.att!, out: out, interactive: interactive)
                if !m.body.isEmpty { Text(m.body).font(Typo.body(15)).foregroundStyle(fg) }
                reactionsRow
                HStack { Spacer(); meta }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if conv.isGroup, !out, let a = m.author, !a.isEmpty {
                Text(a).font(Typo.body(13, .semibold)).foregroundStyle(Th.teal)
                    .padding(.bottom, 2)
            }
            if let r = m.replyTo { quote(r) }
            (Text(m.body) + Text(spacer).font(Typo.body(11)).foregroundColor(.clear))
                .font(Typo.body(15)).foregroundStyle(fg)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.disabled)
            if let tr = m.translation, !tr.text.isEmpty {
                Text((out ? "вы написали: " : "перевод: ") + tr.text).font(Typo.body(13)).foregroundStyle(fg.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
            reactionsRow
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .overlay(alignment: .bottomTrailing) { meta.padding(.trailing, 10).padding(.bottom, 6) }
    }

    /// Невидимый хвост под время, чтобы оно не наезжало на текст (как .mtsp макета).
    private var spacer: String {
        "  " + (m.edited == true ? "изм. " : "") + Fmt.hm(m.date) + (out ? " ✓✓" : "")
    }

    private func quote(_ r: ReplyRef) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(r.dir == "out" ? "Вы" : store.name(store.contact(conv.contactId))).font(Typo.body(12.5, .bold))
            Text(r.text).font(Typo.body(13)).opacity(0.8).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(fg.opacity(0.1)))
        .overlay(alignment: .leading) { Rectangle().fill(fg).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.top, 2).padding(.bottom, 6)
    }

    @ViewBuilder private var reactionsRow: some View {
        if let rx = m.reactions, !rx.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(rx.enumerated()), id: \.offset) { _, r in
                    Text(r.emoji).font(.system(size: 14))
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Capsule().fill(fg.opacity(r.mine ? 0.22 : 0.12)))
                }
            }
            .padding(.top, 5)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if m.edited == true { Text("изм.").italic() }
            Text(Fmt.hm(m.date)).monospacedDigit()
            if out { Icon(name: m.pending == true ? "clock" : "checks", size: 13) }
        }
        .font(Typo.body(11))
        .foregroundStyle(fg.opacity(0.65))
    }
}

struct TypingBubble: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Th.muted).frame(width: 7, height: 7)
                    .offset(y: on ? -5 : 0).opacity(on ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(BubbleShape(out: false).fill(Th.bubIn))
        .onAppear { on = true }
        .accessibilityLabel("Печатает")
    }
}
