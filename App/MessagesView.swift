import SwiftUI

/// Сообщения: поиск, «Все / Непрочитанные / Ждут ответа», аккаунты и папки, список чатов с жестами как в Telegram.
struct MessagesView: View {
    @Environment(Store.self) private var store
    @State private var q = ""
    @State private var net = "all"
    @State private var fold = "all"
    @State private var found: [SearchItem] = []
    @State private var delTarget: Conversation?

    var body: some View {
        @Bindable var store = store
        let list = chats()
        ZStack {
            Aurora()
            List {
                Group {
                    TabHeader(title: "Сообщения", sub: "все переписки из соцсетей") { BellAndAccount() }
                    if store.offline || store.demo == .offline { OfflineBanner() }
                    searchField
                    Seg(items: [("all", "Все", nil), ("unread", "Непрочитанные", unreadCount), ("wait", "Ждут ответа", waitCount)],
                        selection: $store.messagesFilter)
                        .padding(.horizontal, 16).padding(.top, 10)
                    chips.padding(.top, 10).padding(.bottom, 8)
                }
                .plainRow()

                switch dataState(store) {
                case .loading:
                    SkelRows(n: 7).padding(6).cardGlass(28).padding(.horizontal, 12).plainRow()
                case .error:
                    EmptyBlock(icon: "alert", title: "Не получилось загрузить", text: "Сервер не ответил. Проверьте связь и попробуйте ещё раз", error: true,
                               button: "Повторить", buttonIcon: "refresh") { Task { await store.loadState(force: true) } }.plainRow()
                case .empty:
                    EmptyBlock(icon: "inbox", title: "Сообщений пока нет", text: "Переписки из ваших соцсетей появятся здесь, когда клиенты напишут").plainRow()
                case .ready:
                    if showArchive { archiveRow(position: list.isEmpty ? .only : .first) }
                    if list.isEmpty {
                        EmptyBlock(icon: "search", title: "Ничего не нашли", text: "Попробуйте другое имя или снимите фильтр").plainRow()
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        ChatListRow(conv: c, archived: false, onDelete: { delTarget = c })
                            .cardRow(cardPos(i, count: list.count))
                    }
                    if !found.isEmpty { foundSection }
                }
                Color.clear.frame(height: 100).plainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { store.showArchiveRow = true }
                await store.loadState(force: true)
            }
        }
        .task(id: q) {
            let t = q.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2 else { found = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let r = await store.search(t)
            found = Array(r.prefix(20))
        }
        .chatDeleteDialog($delTarget)
    }

    private var showArchive: Bool {
        store.showArchiveRow && !store.archivedChats.isEmpty && store.messagesFilter == "all" && q.isEmpty && net == "all" && fold == "all"
    }

    private var unreadCount: Int { store.liveChats.filter { store.unread($0) > 0 }.count }
    private var waitCount: Int { store.liveChats.filter { store.waiting($0) }.count }

    private func chats() -> [Conversation] {
        var cs = store.liveChats
        switch store.messagesFilter {
        case "unread": cs = cs.filter { store.unread($0) > 0 }
        case "wait": cs = cs.filter { store.waiting($0) }
        default: break
        }
        if net != "all" { cs = cs.filter { $0.network == net } }
        if fold != "all" { cs = cs.filter { store.contact($0.contactId)?.folderId == fold } }
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.isEmpty {
            cs = cs.filter { c in
                let n = store.name(store.contact(c.contactId)).lowercased()
                return n.contains(t) || (c.last?.preview.lowercased().contains(t) ?? false)
            }
        }
        return store.sortChats(cs)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon(name: "search", size: 16).foregroundStyle(Th.muted)
            TextField("", text: $q, prompt: Text("Поиск по имени").foregroundColor(Th.faint))
                .font(Typo.body(15)).foregroundStyle(Th.fg)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !q.isEmpty {
                Button { q = "" } label: { Icon(name: "x", size: 16).foregroundStyle(Th.muted) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .glassCapsule()
        .padding(.horizontal, 16)
    }

    private var networks: [String] {
        var seen = Set<String>(), out: [String] = []
        for c in store.state.channels.map(\.type) + store.state.conversations.map(\.network) where !seen.contains(c) { seen.insert(c); out.append(c) }
        return out
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Button { net = "all" } label: { Label("Все аккаунты", systemImage: net == "all" ? "checkmark" : "square.grid.2x2") }
                    ForEach(networks, id: \.self) { n in
                        Button { net = n } label: {
                            if net == n { Label(Net.name(n), systemImage: "checkmark") } else { Text(Net.name(n)) }
                        }
                    }
                } label: { ChipLabel(title: net == "all" ? "Все аккаунты" : Net.name(net), on: net != "all") }
                Menu {
                    Button { fold = "all" } label: { Label("Все папки", systemImage: fold == "all" ? "checkmark" : "square.grid.2x2") }
                    ForEach(store.folders) { f in
                        Button { fold = f.id } label: {
                            if fold == f.id { Label(f.name, systemImage: "checkmark") } else { Text(f.name) }
                        }
                    }
                    Divider()
                    Button { store.open(.folders) } label: { Label("Настроить папки", systemImage: "slider.horizontal.3") }
                } label: {
                    let f = store.folder(fold)
                    ChipLabel(title: f?.name ?? "Все папки", on: f != nil, dot: f.map { Color(css: $0.color) })
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func archiveRow(position: CardPos) -> some View {
        Button { store.open(.archive) } label: {
            HStack(spacing: 12) {
                Icon(name: "archive").foregroundStyle(Th.cream)
                    .frame(width: 48, height: 48).background(Circle().fill(Th.fg.opacity(0.28)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Архив").font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg)
                    Text(store.archivedChats.map { store.name(store.contact($0.contactId)) }.joined(separator: ", "))
                        .font(Typo.body(14)).foregroundStyle(Th.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .cardRow(position)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var foundSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectTitle(title: "В сообщениях", small: "\(found.count)")
            VStack(spacing: 0) {
                ForEach(found) { f in
                    Button { store.openChat(f.conversationId) } label: {
                        HStack(spacing: 12) {
                            Avatar(name: f.name ?? "?", network: f.network, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name ?? "Клиент").font(Typo.body(15, .semibold)).foregroundStyle(Th.fg)
                                Text(f.snippet ?? "").font(Typo.body(13.5)).foregroundStyle(Th.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if let d = parseISO(f.at) { Text(Fmt.when(d)).font(Typo.body(12)).foregroundStyle(Th.muted) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowStyle())
                }
            }
            .padding(6)
            .cardGlass(28)
            .padding(.horizontal, 12)
        }
        .plainRow()
    }
}

// MARK: - строки списка «как карточка»

enum CardPos { case only, first, middle, last }

func cardPos(_ i: Int, count: Int) -> CardPos {
    if count == 1 { return .only }
    if i == 0 { return .first }
    if i == count - 1 { return .last }
    return .middle
}

private struct CardSegment: View {
    let pos: CardPos
    var body: some View {
        let r: CGFloat = 28
        let top: CGFloat = pos == .only || pos == .first ? r : 0
        let bot: CGFloat = pos == .only || pos == .last ? r : 0
        UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bot, bottomTrailingRadius: bot, topTrailingRadius: top, style: .continuous)
            .fill(Th.glass)
            .padding(.top, pos == .only || pos == .first ? 0 : -1)
            .padding(.horizontal, 12)
    }
}

extension View {
    /// Строка списка без фона и разделителей.
    func plainRow() -> some View {
        self.listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Строка-часть стеклянной карточки (.card-g.list-g).
    func cardRow(_ pos: CardPos) -> some View {
        self.padding(.top, pos == .only || pos == .first ? 6 : 0)
            .padding(.bottom, pos == .only || pos == .last ? 6 : 0)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
            .listRowBackground(CardSegment(pos: pos))
            .listRowSeparator(.hidden)
    }

    func chatDeleteDialog(_ target: Binding<Conversation?>) -> some View {
        modifier(ChatDeleteDialog(target: target))
    }
}

/// Вопрос перед удалением чата: в Telegram — «у меня и у собеседника» или «только у меня».
struct ChatDeleteDialog: ViewModifier {
    @Environment(Store.self) private var store
    @Binding var target: Conversation?

    func body(content: Content) -> some View {
        let c = target
        let name = store.name(store.contact(c?.contactId))
        content.confirmationDialog("Удалить чат «\(name)»?", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            if let c {
                if c.network == "telegram" {
                    Button("Удалить у меня и у собеседника", role: .destructive) { Task { await deleteBoth(c) } }
                    Button("Удалить только у меня", role: .destructive) { Task { await store.deleteChat(contactId: c.contactId) } }
                } else {
                    Button("Удалить чат", role: .destructive) { Task { await store.deleteChat(contactId: c.contactId) } }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Telegram: сообщения удаляются и у собеседника (по одному, как «Удалить у всех»), затем чат убирается из кабинета.
    private func deleteBoth(_ c: Conversation) async {
        let ids = store.messages(c.id).map(\.id).filter { !$0.hasPrefix("tmp-") }
        if !store.fixture {
            for id in ids { _ = try? await API.send("POST", "/api/messages/delete/", json: ["messageId": id, "mode": "everyone"]) }
        }
        await store.deleteChat(contactId: c.contactId)
        store.show("Чат удалён у вас и у собеседника")
    }
}

/// Строка чата: аватар со значком сети, имя, время, последнее сообщение, счётчик; свайпы и предпросмотр.
struct ChatListRow: View {
    @Environment(Store.self) private var store
    let conv: Conversation
    var archived: Bool
    var onDelete: () -> Void

    var body: some View {
        let c = store.contact(conv.contactId)
        let n = store.unread(conv)
        Button { store.openChat(conv.id) } label: {
            HStack(spacing: 12) {
                Avatar(name: store.avatarName(c), network: conv.network, size: 48, url: c?.avatar)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Text(store.name(c)).font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                            if let c, store.bookName(c) != nil { Icon(name: "book", size: 13).foregroundStyle(Th.teal.opacity(0.8)) }
                            if conv.isMuted { Icon(name: "bellOff", size: 13).foregroundStyle(Th.faint) }
                        }
                        Spacer(minLength: 4)
                        Text(Fmt.when(store.lastDate(conv))).font(Typo.body(12.5)).foregroundStyle(Th.muted).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        lastLine
                        Spacer(minLength: 4)
                        if n > 0 {
                            Text("\(n)").font(Typo.body(11.5, .bold))
                                .foregroundStyle(conv.isMuted ? Th.cream : Th.onTeal)
                                .padding(.horizontal, 6).frame(minWidth: 21, minHeight: 21)
                                .background(Capsule().fill(conv.isMuted ? Th.faint : Th.teal))
                        } else if conv.isPinned {
                            Icon(name: "pin", size: 13).foregroundStyle(Th.faint)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { store.setFlag(conv.id, "pinned", !conv.isPinned, toast: conv.isPinned ? "Чат откреплён" : "Чат закреплён наверху") } label: {
                Label(conv.isPinned ? "Открепить" : "Закрепить", systemImage: conv.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(Color(hex: 0x1F7A63))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onDelete) { Label("Удалить", systemImage: "trash.fill") }.tint(Color(hex: 0xB3261E))
            Button {
                store.setFlag(conv.id, "archived", !archived, toast: archived ? "Чат вернулся из архива" : "Чат в архиве. Потяните список вниз, чтобы его открыть")
            } label: { Label(archived ? "Вернуть" : "В архив", systemImage: archived ? "tray.and.arrow.up.fill" : "archivebox.fill") }
            .tint(Color(hex: 0x7E8B88))
            Button {
                store.setFlag(conv.id, "muted", !conv.isMuted, toast: conv.isMuted ? "Уведомления из чата включены" : "Уведомления из чата выключены")
            } label: { Label(conv.isMuted ? "Со звуком" : "Без звука", systemImage: conv.isMuted ? "bell.fill" : "bell.slash.fill") }
            .tint(Color(hex: 0xD98E2B))
        }
        .contextMenu {
            if let c {
                if store.inBook(c) {
                    Label("В контактах телефона", systemImage: "checkmark")
                } else {
                    Button { store.addToBook(c) } label: { Label("Добавить в контакты", systemImage: "person.crop.circle.badge.plus") }
                }
            }
            Button { store.setFlag(conv.id, "pinned", !conv.isPinned, toast: conv.isPinned ? "Чат откреплён" : "Чат закреплён наверху") } label: {
                Label(conv.isPinned ? "Открепить" : "Закрепить", systemImage: "pin")
            }
            Button { store.setFlag(conv.id, "muted", !conv.isMuted, toast: conv.isMuted ? "Уведомления из чата включены" : "Уведомления из чата выключены") } label: {
                Label(conv.isMuted ? "Включить уведомления" : "Выключить уведомления", systemImage: conv.isMuted ? "bell" : "bell.slash")
            }
            Button { store.markUnread(conv.id) } label: { Label("Пометить как новое", systemImage: "message.badge") }
            Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
        } preview: {
            ChatPreview(conv: conv).environment(store)
        }
    }

    @ViewBuilder private var lastLine: some View {
        if let s = store.typing[conv.id], Date().timeIntervalSince(s.at) < 5 {
            Text(s.kind == "recording" ? "записывает голосовое…" : "печатает…").font(Typo.body(14)).foregroundStyle(Th.teal).lineLimit(1)
        } else if let d = store.serverDrafts[conv.id], !d.isEmpty {
            (Text("Черновик: ").foregroundColor(Th.wine) + Text(d).foregroundColor(Th.muted)).font(Typo.body(14)).lineLimit(1)
        } else {
            let m = conv.last
            let prefix = m?.isOut == true ? "Вы: " : (conv.isGroup && m?.author != nil ? (m?.author ?? "") + ": " : "")
            Text(m.map { prefix + $0.preview } ?? "Нет сообщений").font(Typo.body(14)).foregroundStyle(Th.muted).lineLimit(1)
        }
    }
}

/// Предпросмотр чата по долгому нажатию (.pv).
struct ChatPreview: View {
    @Environment(Store.self) private var store
    let conv: Conversation
    var body: some View {
        let c = store.contact(conv.contactId)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Avatar(name: store.avatarName(c), network: conv.network, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.name(c)).font(Typo.body(15, .semibold)).foregroundStyle(Th.fg)
                    Text(Net.name(conv.network) + (c?.handle.map { " · " + $0 } ?? "")).font(Typo.body(12)).foregroundStyle(Th.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Th.hair).frame(height: 0.5)
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(conv.messages.suffix(6)) { m in
                    HStack {
                        if m.isOut { Spacer(minLength: 40) }
                        Text(m.preview).font(Typo.body(13.5)).foregroundStyle(m.isOut ? Th.bubOutFg : Th.fg)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(BubbleShape(out: m.isOut).fill(m.isOut ? Th.bubOut : Th.bubIn))
                        if !m.isOut { Spacer(minLength: 40) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(width: 340, height: 318)
        .background(Aurora())
    }
}

/// Архив: убранные из списка чаты, новые сообщения в них без звука.
struct ArchiveView: View {
    @Environment(Store.self) private var store
    @State private var delTarget: Conversation?

    var body: some View {
        let list = store.archivedChats
        ZStack {
            Aurora()
            List {
                Group {
                    TopBar(back: { store.pop() })
                    LargeTitle(title: "Архив")
                }
                .plainRow()
                if list.isEmpty {
                    EmptyBlock(icon: "archive", title: "Архив пуст", text: "Смахните чат влево и нажмите «В архив»").plainRow()
                } else {
                    Hint(text: "Сюда попадают чаты, которые вы убрали из списка. Новые сообщения в них приходят без звука.").plainRow()
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        ChatListRow(conv: c, archived: true, onDelete: { delTarget = c })
                            .cardRow(cardPos(i, count: list.count))
                    }
                }
                Color.clear.frame(height: 60).plainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .chatDeleteDialog($delTarget)
    }
}
