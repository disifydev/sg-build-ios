import SwiftUI

struct ChatsView: View {
    @Environment(Store.self) private var store
    @State private var net = "all"
    @State private var q = ""
    @State private var folderSheetFor: String?
    @State private var showArchive = false
    @State private var found: [SearchItem] = []
    @State private var deleting: Conversation?

    private func matches(_ c: Conversation, query: String) -> Bool {
        let contact: Contact? = store.contact(c.contactId)
        if c.isArchived { return false }
        if store.chatFolder != "all" && contact?.folderId != store.chatFolder { return false }
        if net != "all" && c.network != net { return false }
        if !store.matchesCollection(contact) { return false }
        if query.isEmpty { return true }
        var parts: [String] = [store.name(contact), contact?.name ?? "", contact?.handle ?? "", contact?.phone ?? ""]
        parts.append(contentsOf: c.messages.map { $0.body })
        let hay: String = parts.joined(separator: " ").lowercased()
        return hay.contains(query)
    }

    private var rows: [Conversation] {
        let query: String = q.trimmingCharacters(in: .whitespaces).lowercased()
        var list: [Conversation] = store.state.conversations.filter { matches($0, query: query) }
        list.sort { (a: Conversation, b: Conversation) -> Bool in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned && a.pinnedAt != b.pinnedAt { return a.pinnedAt > b.pinnedAt }
            return lastDate(a) > lastDate(b)
        }
        return list
    }

    private var archived: [Conversation] {
        store.state.conversations.filter { $0.isArchived }.sorted { lastDate($0) > lastDate($1) }
    }

    private func lastDate(_ c: Conversation) -> Date { c.last?.date ?? store.contact(c.contactId)?.first ?? .distantPast }

    private var title: String {
        guard store.chatSelecting else { return "Чаты" }
        let n: Int = store.chatSelected.count
        return n == 0 ? "Выберите чаты" : "Выбрано: " + ruCount(n, "чат", "чата", "чатов")
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            if store.chatSelecting { selectHeader } else { header }
            Text(title)
                .font(Typo.display(30))
                .tracking(-0.9)
                .foregroundStyle(Pal.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .contentTransition(.numericText())
            search
            chips
            if !store.chatSelecting { collectionChips }
            if store.chatSelecting { selectChips }
            list
        }
        .screenBackground(store.wall)
        .overlay(alignment: .bottom) {
            if store.chatSelecting {
                SelectionBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(get: { folderSheetFor.map(IDBox.init) }, set: { folderSheetFor = $0?.id })) { box in
            FolderSheet(contactId: box.id)
        }
        .sheet(isPresented: $store.chatBatchFolderSheet) {
            BatchFolderSheet(convIds: store.chatSelected)
        }
        .task(id: q) {
            let t = q.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2 else { found = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let r = await store.search(t)
            withAnimation(.easeOut(duration: 0.2)) { found = Array(r.prefix(15)) }
        }
        .chatDeleteDialog($deleting)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PillButton(action: { store.tab = .profile; store.profilePath = [.folders] }) {
                Image(systemName: "folder").font(.system(size: 16))
                Text("Папки")
            }
            Spacer()
            PillButton(action: {
                withAnimation(.spring(response: 0.3)) { net = net == "all" ? "whatsapp" : (net == "whatsapp" ? "telegram" : "all") }
            }) {
                HStack(spacing: -4) {
                    if net != "telegram" { Circle().fill(Color(hex: 0x25D366)).frame(width: 10, height: 10) }
                    if net != "whatsapp" { Circle().fill(Color(hex: 0x2AABEE)).frame(width: 10, height: 10) }
                }
                Text(net == "all" ? "Все" : (net == "whatsapp" ? "WhatsApp" : "Telegram")).font(Typo.body(13, .medium))
            }
            PillButton(action: { store.startSelecting() }) {
                Image(systemName: "checkmark.circle").font(.system(size: 16))
                Text("Выбрать")
            }
            .accessibilityIdentifier("chats-select")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var selectHeader: some View {
        let visible: [String] = rows.map(\.id)
        let all: Bool = !visible.isEmpty && visible.allSatisfy { store.chatSelected.contains($0) }
        return HStack(spacing: 8) {
            PillButton(action: { store.stopSelecting() }) {
                Text("Отменить")
            }
            Spacer()
            PillButton(action: {
                withAnimation(.spring(response: 0.3)) {
                    if all { store.chatSelected.subtract(visible) } else { store.chatSelected.formUnion(visible) }
                }
            }) {
                Image(systemName: all ? "circle" : "checkmark.circle.fill").font(.system(size: 16))
                Text(all ? "Снять все" : "Выбрать все")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Pal.fg.opacity(0.7))
            TextField("", text: $q, prompt: Text("Поиск по клиентам и сообщениям").foregroundColor(Pal.fg3))
                .font(Typo.body(15))
                .foregroundStyle(Pal.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !q.isEmpty {
                Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Pal.fg3) }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glassCapsule()
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Ряд «Все классы · 9 класс · 10 класс · группы…»: фильтр по классам и группам, виден сразу.
    @ViewBuilder private var collectionChips: some View {
        if !store.classes.isEmpty || !store.groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 13)).foregroundStyle(Pal.fg2)
                    Chip(text: "Все классы", on: store.collectionFilter == "all", height: 32, fontSize: 13) {
                        withAnimation(.spring(response: 0.3)) { store.collectionFilter = "all" }
                    }
                    ForEach(store.classes, id: \.self) { k in
                        Chip(text: classTitle(k), on: store.collectionFilter == "class:" + k, height: 32, fontSize: 13) {
                            withAnimation(.spring(response: 0.3)) { store.collectionFilter = store.collectionFilter == "class:" + k ? "all" : "class:" + k }
                        }
                    }
                    ForEach(store.groups, id: \.self) { g in
                        Chip(text: g, dot: Pal.lav, on: store.collectionFilter == "group:" + g, height: 32, fontSize: 13) {
                            withAnimation(.spring(response: 0.3)) { store.collectionFilter = store.collectionFilter == "group:" + g ? "all" : "group:" + g }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.top, 8)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let all = store.state.conversations
                let unreadAll = all.reduce(0) { $0 + $1.unread }
                Chip(text: "Все", count: unreadAll > 0 ? "• \(unreadAll)" : "\(all.count)", on: store.chatFolder == "all") {
                    withAnimation(.spring(response: 0.3)) { store.chatFolder = "all" }
                }
                ForEach(store.folders) { f in
                    let inF = all.filter { store.contact($0.contactId)?.folderId == f.id }
                    let unread = inF.reduce(0) { $0 + $1.unread }
                    Chip(text: f.name, dot: Color(css: f.color), count: unread > 0 ? "• \(unread)" : "\(inF.count)", on: store.chatFolder == f.id) {
                        withAnimation(.spring(response: 0.3)) { store.chatFolder = f.id }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.top, 12)
    }

    /// Быстрый выбор среди видимых чатов: заменяет текущий выбор.
    private func quickChip(_ text: String, _ ids: [String]) -> some View {
        let set = Set(ids)
        let on: Bool = !set.isEmpty && set == store.chatSelected
        return Chip(text: text, count: "\(ids.count)", on: on, height: 32, fontSize: 13) {
            withAnimation(.spring(response: 0.3)) { store.chatSelected = on ? [] : set }
        }
    }

    private var selectChips: some View {
        let items: [Conversation] = rows
        let unread: [String] = items.filter { $0.unread > 0 }.map(\.id)
        let read: [String] = items.filter { $0.unread == 0 }.map(\.id)
        let noReply: [String] = items.filter { (c: Conversation) -> Bool in c.last?.isOut == false }.map(\.id)
        let pinnedIds: [String] = items.filter { store.pinned.contains($0.id) }.map(\.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Выбрать:").font(Typo.body(13, .medium)).foregroundStyle(Pal.fg2)
                quickChip("Непрочитанные", unread)
                quickChip("Прочитанные", read)
                quickChip("Без ответа", noReply)
                if !pinnedIds.isEmpty { quickChip("Закреплённые", pinnedIds) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.top, 10)
    }

    private var footerHint: String {
        if store.chatFolder != "all", let f = store.folder(store.chatFolder), f.id != store.baseFolder?.id {
            return "Убрать из «\(f.name)» или переложить в другую папку — свайп влево по чату. «Выбрать» сверху — сразу несколько чатов"
        }
        return "Вправо по чату — закрепить, влево — папка, без звука, архив, удалить. Потяни список вниз — архив"
    }

    private var list: some View {
        let items = rows
        let selecting: Bool = store.chatSelecting
        let arch = archived
        return List {
            if showArchive && !arch.isEmpty && !selecting && q.isEmpty {
                Button { store.open(.archive) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox.fill").font(.system(size: 20)).foregroundStyle(Pal.fg)
                            .frame(width: 52, height: 52).background(Circle().fill(Pal.fg.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Архив").font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg)
                            Text(arch.map { store.name(store.contact($0.contactId)) }.joined(separator: ", ")).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        let n: Int = arch.reduce(0) { $0 + $1.unread }
                        if n > 0 {
                            Text("\(n)").font(Typo.body(12, .semibold)).foregroundStyle(Pal.page)
                                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22).background(Capsule().fill(Pal.fg3))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(items) { conv in
                ChatRow(conv: conv, selecting: selecting, selected: store.chatSelected.contains(conv.id))
                    .contextMenu { menu(conv) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !selecting {
                            Button { store.togglePinUndoable(conv.id) } label: {
                                Label(conv.isPinned ? "Открепить" : "Закрепить", systemImage: conv.isPinned ? "pin.slash.fill" : "pin.fill")
                            }
                            .tint(Color(hex: 0x1F7A63))
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !selecting { swipes(conv) }
                    }
            }
            if !found.isEmpty {
                Text("В сообщениях").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
                    .padding(.horizontal, 14).padding(.top, 12)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                ForEach(found) { f in
                    Button { store.open(.chat(f.conversationId)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "text.magnifyingglass").font(.system(size: 16)).foregroundStyle(Pal.acc)
                                .frame(width: 40, height: 40).background(Circle().fill(Pal.acc.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name ?? "Клиент").font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                                Text(f.snippet ?? "").font(Typo.body(13.5)).foregroundStyle(Pal.fg2).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if let d = parseISO(f.at) { Text(Fmt.when(d)).font(Typo.body(12)).foregroundStyle(Pal.fg3) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                }
            }
            if items.isEmpty {
                EmptyNote(text: store.state.conversations.isEmpty
                          ? (store.lastError ?? "Чатов пока нет. Подключи WhatsApp или Telegram в веб-версии — переписки появятся тут.")
                          : (q.isEmpty ? "В этой папке пока пусто" : "Ничего не нашлось"))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if !selecting {
                Text(footerHint)
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, 110, for: .scrollContent)
        .refreshable {
            // как в Telegram: потянуть список вниз — открыть скрытый архив
            if !archived.isEmpty { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showArchive = true } }
            await store.loadState(force: true)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: items.map(\.id))
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(Color.clear)
                .glass(.dark, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder private func menu(_ conv: Conversation) -> some View {
        let isPinned: Bool = store.pinned.contains(conv.id)
        Button { store.togglePinUndoable(conv.id) } label: {
            Label(isPinned ? "Открепить" : "Закрепить сверху", systemImage: isPinned ? "pin.slash" : "pin")
        }
        Button { store.toggleMute(conv.id) } label: {
            Label(conv.isMuted ? "Включить звук" : "Без звука", systemImage: conv.isMuted ? "bell" : "bell.slash")
        }
        Button { store.toggleArchive(conv.id) } label: { Label("В архив", systemImage: "archivebox") }
        if conv.unread > 0 {
            Button { store.markRead(conv.id) } label: { Label("Прочитано", systemImage: "checkmark.message") }
        }
        Button { folderSheetFor = conv.contactId } label: { Label("Переложить в папку", systemImage: "folder") }
        if store.canRemoveFromFolder(conv.contactId) {
            let name: String = store.folder(store.contact(conv.contactId)?.folderId)?.name ?? "папки"
            Button { Task { await store.removeFromFolder(conv.contactId) } } label: {
                Label("Убрать из «\(name)»", systemImage: "folder.badge.minus")
            }
        }
        if !store.chatSelecting {
            Button { store.startSelecting(conv.id) } label: { Label("Выбрать несколько", systemImage: "checkmark.circle") }
        }
        Button { store.open(.client(conv.contactId)) } label: { Label("Карточка клиента", systemImage: "person.crop.circle") }
        Button(role: .destructive) { deleting = conv } label: { Label("Удалить чат", systemImage: "trash") }
    }

    /// Влево — как в Telegram: удалить, в архив, без звука.
    @ViewBuilder private func swipes(_ conv: Conversation) -> some View {
        Button { deleting = conv } label: { Label("Удалить", systemImage: "trash.fill") }
            .tint(Color(hex: 0xB3261E))
        Button { store.toggleArchive(conv.id) } label: { Label("В архив", systemImage: "archivebox.fill") }
            .tint(Color(hex: 0x7E8B88))
        Button { store.toggleMute(conv.id) } label: {
            Label(conv.isMuted ? "Со звуком" : "Без звука", systemImage: conv.isMuted ? "bell.fill" : "bell.slash.fill")
        }
        .tint(Color(hex: 0xD98E2B))
        // как в старой версии: папка прямо со свайпа, а в открытой папке ещё и «Убрать»
        if store.chatFolder != "all" && store.canRemoveFromFolder(conv.contactId) {
            Button { Task { await store.removeFromFolder(conv.contactId) } } label: { Label("Убрать", systemImage: "folder.badge.minus") }
                .tint(Pal.rose)
        }
        Button { folderSheetFor = conv.contactId } label: { Label("Папка", systemImage: "folder.fill") }
            .tint(Color(hex: 0x3E7CB1))
    }
}

/// Панель групповых действий вместо таб-бара в режиме выбора.
struct SelectionBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        let sel: Set<String> = store.chatSelected
        let ids: [String] = Array(sel)
        let none: Bool = sel.isEmpty
        let allPinned: Bool = !none && ids.allSatisfy { store.pinned.contains($0) }
        HStack(spacing: 2) {
            item("folder", "В папку", disabled: none) {
                store.chatBatchFolderSheet = true
            }
            item("folder.badge.minus", "Из папки", disabled: none) {
                let cids: [String] = store.contactIds(of: sel)
                store.stopSelecting()
                Task { await store.removeManyFromFolders(cids) }
            }
            item("checkmark.message", "Прочитано", disabled: none) {
                store.stopSelecting()
                store.markReadMany(ids)
            }
            item(allPinned ? "pin.slash" : "pin", allPinned ? "Открепить" : "Закрепить", disabled: none) {
                store.stopSelecting()
                store.pinMany(ids)
            }
        }
        .padding(4)
        .frame(height: 64)
        .glass(.bar, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func item(_ icon: String, _ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19)).frame(height: 24)
                Text(title).font(Typo.body(11, .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(Pal.fg.opacity(disabled ? 0.35 : 0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
    }
}

struct IDBox: Identifiable { let id: String }

struct ChatRow: View {
    @Environment(Store.self) private var store
    let conv: Conversation
    var selecting = false
    var selected = false

    var body: some View {
        let contact = store.contact(conv.contactId)
        let name = store.name(contact)
        let m = conv.last
        Button {
            if selecting {
                haptic()
                withAnimation(.spring(response: 0.25)) { store.toggleSelected(conv.id) }
            } else {
                store.open(.chat(conv.id))
            }
        } label: {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23))
                        .foregroundStyle(selected ? Pal.acc : Pal.fg.opacity(0.45))
                        .transition(.scale.combined(with: .opacity))
                }
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: name, hue: contact?.displayHue ?? 200, url: contact?.avatar, size: 52)
                    NetBadge(net: conv.network).offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                        if let k = contact?.classes.first {
                            Text(k + " кл.").font(Typo.body(11, .semibold)).foregroundStyle(Pal.acc)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Pal.acc.opacity(0.14)))
                                .fixedSize()
                        }
                        if let c = contact, store.bookName(c) != nil {
                            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 11)).foregroundStyle(Pal.acc.opacity(0.8))
                        }
                        if conv.isMuted {
                            Image(systemName: "bell.slash.fill").font(.system(size: 11)).foregroundStyle(Pal.fg3)
                        }
                        if conv.isPinned {
                            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Pal.fg3)
                        }
                        Spacer(minLength: 4)
                        if m?.isOut == true {
                            DoubleCheck(size: 11).foregroundStyle(Pal.mint)
                        }
                        Text(Fmt.when(m?.date ?? contact?.first ?? Date())).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                    }
                    HStack(spacing: 8) {
                        previewLine(m)
                        Spacer(minLength: 0)
                        if conv.unread > 0 {
                            Text("\(conv.unread)").font(Typo.body(12, .semibold)).foregroundStyle(conv.isMuted ? Pal.page : Pal.onAcc)
                                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                                .background(Capsule().fill(conv.isMuted ? Pal.fg3 : Pal.acc))
                                .transition(.scale)
                        }
                    }
                    HStack(spacing: 6) {
                        FolderTag(folder: store.folder(contact?.folderId))
                        ForEach(Array(((contact?.plainTags ?? []) + (contact?.groups.map { "группа:" + $0 } ?? [])).prefix(2)), id: \.self) { t in
                            Text(tagTitle(t)).font(Typo.body(11, .medium)).foregroundStyle(Pal.fg.opacity(0.78))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Pal.fg.opacity(0.08)))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Pal.fg.opacity(selecting && selected ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("chat-row")
    }
}

extension ChatRow {
    @ViewBuilder func previewLine(_ m: Message?) -> some View {
        if let t = store.typing[conv.id], Date().timeIntervalSince(t.at) < 5 {
            Text(t.kind == "recording" ? "записывает голосовое…" : "печатает…").font(Typo.body(14)).foregroundStyle(Pal.acc).lineLimit(1)
        } else if let d = store.drafts[conv.id], !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            (Text("Черновик: ").foregroundColor(Pal.danger) + Text(d).foregroundColor(Pal.fg2)).font(Typo.body(14)).lineLimit(1)
        } else {
            Text(rowPreview(m)).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
        }
    }
}

/// Чип-меню «Классы и группы» в ряду фильтров.
struct CollectionMenu: View {
    @Environment(Store.self) private var store
    var body: some View {
        let f = store.collectionFilter
        let title: String = f == "all" ? "Классы" : (f.hasPrefix("class:") ? classTitle(String(f.dropFirst(6))) : String(f.dropFirst(6)))
        Menu {
            Button { store.collectionFilter = "all" } label: { Label("Все ученики", systemImage: f == "all" ? "checkmark" : "person.2") }
            if !store.classes.isEmpty {
                Section("Классы") {
                    ForEach(store.classes, id: \.self) { k in
                        Button { store.collectionFilter = "class:" + k } label: {
                            if f == "class:" + k { Label(classTitle(k), systemImage: "checkmark") } else { Text(classTitle(k)) }
                        }
                    }
                }
            }
            if !store.groups.isEmpty {
                Section("Группы") {
                    ForEach(store.groups, id: \.self) { g in
                        Button { store.collectionFilter = "group:" + g } label: {
                            if f == "group:" + g { Label(g, systemImage: "checkmark") } else { Text(g) }
                        }
                    }
                }
            }
            Divider()
            Button { store.open(.lists) } label: { Label("Настроить классы и группы", systemImage: "slider.horizontal.3") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap").font(.system(size: 13, weight: .semibold))
                Text(title).font(Typo.body(14, .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(f == "all" ? Pal.fg : Pal.onAcc)
            .padding(.horizontal, 14).frame(height: 36)
            .background { if f != "all" { Capsule().fill(Pal.acc) } }
            .glassCapsule(interactive: true)
        }
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
                    Button("Удалить у меня и у собеседника", role: .destructive) { Task { await store.deleteChat(c.id, everyone: true) } }
                    Button("Удалить только у меня", role: .destructive) { Task { await store.deleteChat(c.id, everyone: false) } }
                } else {
                    Button("Удалить чат", role: .destructive) { Task { await store.deleteChat(c.id, everyone: false) } }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Клиент и переписка пропадут из Sguardo. Вернуть будет нельзя.")
        }
    }
}

extension View {
    func chatDeleteDialog(_ target: Binding<Conversation?>) -> some View { modifier(ChatDeleteDialog(target: target)) }
}

/// Архив: чаты, убранные из списка. Новые сообщения в них приходят без звука.
struct ArchiveView: View {
    @Environment(Store.self) private var store
    @State private var deleting: Conversation?

    var body: some View {
        let list = store.state.conversations.filter { $0.isArchived }.sorted { ($0.last?.at ?? "") > ($1.last?.at ?? "") }
        VStack(spacing: 0) {
            TopBar(back: { store.pop() }, center: { Text("Архив").font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg) }, trailing: { Color.clear.frame(width: 44, height: 44) })
            List {
                if list.isEmpty {
                    EmptyNote(text: "Архив пуст. Смахни чат влево и нажми «В архив».")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(list) { conv in
                    ChatRow(conv: conv)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { deleting = conv } label: { Label("Удалить", systemImage: "trash.fill") }.tint(Color(hex: 0xB3261E))
                            Button { store.toggleArchive(conv.id) } label: { Label("Вернуть", systemImage: "tray.and.arrow.up.fill") }.tint(Color(hex: 0x7E8B88))
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                    .fill(Color.clear)
                    .glass(.dark, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .ignoresSafeArea(edges: .bottom)
        }
        .screenBackground(store.wall)
        .chatDeleteDialog($deleting)
    }
}

func rowPreview(_ m: Message?) -> String {
    guard let m else { return "" }
    return m.isOut ? "Вы: " + m.preview : m.preview
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Pal.fg.opacity(configuration.isPressed ? 0.06 : 0))
    }
}
