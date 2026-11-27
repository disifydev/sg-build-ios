import SwiftUI

/// Профиль клиента как в Telegram: действия, контакты, папка, класс, ответственный, заметка, «Добавить в контакты»,
/// «тот же человек», вкладки медиа / файлы / ссылки / голосовые, удаление чата.
struct ProfileView: View {
    @Environment(Store.self) private var store
    let contactId: String
    @State private var tab = "media"
    @State private var note = ""
    @State private var delTarget: Conversation?
    @FocusState private var noteFocus: Bool

    var body: some View {
        let c = store.contact(contactId)
        let conv = store.mainConversation(of: contactId)
        Screen(bottom: 60) {
            TopBar(back: { store.pop() }) {
                GlassCap(title: "Изменить") { store.open(.editContact(contactId)) }
            }
            if let c {
                hero(c, conv)
                actions(c, conv)
                info(c)
                book(c)
                merge(c)
                Seg(items: [("media", "Медиа", nil), ("files", "Файлы", nil), ("links", "Ссылки", nil), ("voice", "Голосовые", nil)], selection: $tab)
                    .padding(.horizontal, 16).padding(.top, 18)
                ProfileMedia(contactId: contactId, tab: tab)
                Group26 {
                    GI(title: "Удалить чат", danger: true) {
                        if let conv { delTarget = conv } else { Task { await store.deleteChat(contactId: contactId); store.pop() } }
                    }
                }
                .padding(.top, 16)
            } else {
                EmptyBlock(icon: "user", title: "Клиент не найден", text: "Возможно, его удалили")
            }
        }
        .onAppear { note = c?.note ?? "" }
        .onDisappear { store.setNote(contactId, note) }
        .onChange(of: noteFocus) { _, f in if !f { store.setNote(contactId, note) } }
        .chatDeleteDialog($delTarget)
        .onChange(of: store.contact(contactId) == nil) { _, gone in if gone { store.pop() } }
    }

    private func hero(_ c: Contact, _ conv: Conversation?) -> some View {
        VStack(spacing: 4) {
            Avatar(name: store.avatarName(c), network: conv?.network ?? c.source, size: 104, url: c.avatar)
            Text(store.name(c)).font(Typo.display(23, .semibold)).foregroundStyle(Th.fg).multilineTextAlignment(.center)
                .padding(.top, 10)
            HStack(spacing: 6) {
                Text(Net.name(conv?.network ?? c.source))
                if let s = conv.flatMap({ store.statusLine($0.id) }) { Text("· " + s) }
                else if let conv { Text("· последнее сообщение " + Fmt.when(store.lastDate(conv)).lowercased()) }
            }
            .font(Typo.body(13)).foregroundStyle(Th.muted)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    private func actions(_ c: Contact, _ conv: Conversation?) -> some View {
        HStack(spacing: 8) {
            Tile(icon: "chat", title: "Чат") { if let conv { store.openChat(conv.id) } else { store.show("С этим клиентом ещё нет переписки") } }
            Tile(icon: conv?.isMuted == true ? "bell" : "bellOff", title: conv?.isMuted == true ? "Со звуком" : "Без звука") {
                if let conv { store.setFlag(conv.id, "muted", !conv.isMuted, toast: conv.isMuted ? "Уведомления включены" : "Уведомления выключены") }
            }
            Tile(icon: "card", title: "Оплата") { store.sheet = .newPay(contactId: c.id) }
            Tile(icon: "bell", title: "Напомнить") {
                let at = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
                store.remind(c.id, at: at)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
    }

    private func info(_ c: Contact) -> some View {
        VStack(spacing: 0) {
            if let p = store.phoneOf(c) {
                IRow(label: "мобильный") { Text(p).foregroundStyle(Th.teal) } action: { UIPasteboard.general.string = p; store.show("Номер скопирован") }
                Hair(inset: 16)
            }
            if let h = c.handle, !h.isEmpty, !PhoneBook.looksLikePhone(h) {
                IRow(label: "имя пользователя") { Text(h).foregroundStyle(Th.teal) } action: { UIPasteboard.general.string = h; store.show("Ссылка на профиль скопирована") }
                Hair(inset: 16)
            }
            Menu {
                ForEach(store.folders) { f in
                    Button { store.setFolder(c.id, f.id) } label: {
                        if f.id == c.folderId { Label(f.name, systemImage: "checkmark") } else { Text(f.name) }
                    }
                }
            } label: {
                IRowLabel(label: "папка") {
                    HStack(spacing: 7) {
                        Circle().fill(Color(css: store.folder(c.folderId)?.color)).frame(width: 9, height: 9)
                        Text(store.folder(c.folderId)?.name ?? "Без папки")
                    }
                }
            }
            Hair(inset: 16)
            Menu {
                Button { store.setClass(c.id, nil) } label: { if c.classes.isEmpty { Label("Без класса", systemImage: "checkmark") } else { Text("Без класса") } }
                ForEach(store.classes, id: \.self) { k in
                    Button { store.setClass(c.id, k) } label: {
                        if c.classes.contains(k) { Label(classTitle(k), systemImage: "checkmark") } else { Text(classTitle(k)) }
                    }
                }
            } label: {
                IRowLabel(label: "класс") { Text(c.classes.first.map(classTitle) ?? "не указан") }
            }
            Hair(inset: 16)
            Menu {
                ForEach(store.state.team) { m in
                    Button { store.setAssignee(c.id, m) } label: {
                        if m.name == c.assignee { Label(m.name, systemImage: "checkmark") } else { Text(m.name) }
                    }
                }
            } label: {
                IRowLabel(label: "ответственный") { Text((c.assignee ?? "").isEmpty ? (store.user?.name ?? "—") : (c.assignee ?? "")) }
            }
            Hair(inset: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("заметка").font(Typo.body(12.5)).foregroundStyle(Th.muted)
                TextField("", text: $note, prompt: Text("Что важно помнить об этом клиенте").foregroundColor(Th.faint), axis: .vertical)
                    .font(Typo.body(15)).foregroundStyle(Th.fg)
                    .lineLimit(2...8)
                    .focused($noteFocus)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .glassRect(26)
        .padding(.horizontal, 12)
    }

    @ViewBuilder private func book(_ c: Contact) -> some View {
        if store.inBook(c) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) { Icon(name: "book", size: 16); Text("В контактах телефона") }.font(Typo.body(15.5)).foregroundStyle(Th.fg)
                Text("Имя совпадает с телефонной книгой").font(Typo.body(12.5)).foregroundStyle(Th.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassRect(26).padding(.horizontal, 12).padding(.top, 12)
        } else {
            Button { store.addToBook(c) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) { Icon(name: "userPlus", size: 16); Text("Добавить в контакты") }.font(Typo.body(15.5)).foregroundStyle(Th.teal)
                    Text("Имя и \(store.phoneOf(c) != nil ? "номер" : "ссылка на соцсеть") появятся в телефонной книге").font(Typo.body(12.5)).foregroundStyle(Th.muted)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowStyle())
            .glassRect(26).padding(.horizontal, 12).padding(.top, 12)
        }
    }

    @ViewBuilder private func merge(_ c: Contact) -> some View {
        if let s = store.suggestions.first(where: { $0.aId == c.id || $0.bId == c.id }) {
            let other = s.aId == c.id ? s.bId : s.aId
            let oc = store.contact(other)
            VStack(alignment: .leading, spacing: 2) {
                Text("Похоже, это тот же человек: \(store.name(c)) в \(Net.name(c.source)) и \(oc.map { store.name($0) + " в " + Net.name($0.source) } ?? (s.aId == c.id ? s.bName : s.aName) ?? "другой карточке")")
                    .font(Typo.body(13.5)).foregroundStyle(Th.fg).lineSpacing(2)
                if let r = s.reason { Text(r).font(Typo.body(13.5)).foregroundStyle(Th.muted) }
                HStack(spacing: 8) {
                    Btn(title: "Объединить", small: true) { Task { await store.merge(keep: c.id, drop: other, yes: true) } }
                    Btn(title: "Это разные люди", kind: .outline, small: true) { Task { await store.merge(keep: c.id, drop: other, yes: false) } }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Th.fg.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .padding(.horizontal, 12).padding(.top, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

/// Плитка действия в профиле (.pact).
private struct Tile: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button { haptic(); action() } label: {
            VStack(spacing: 4) {
                Icon(name: icon)
                Text(title).font(Typo.body(11.5, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Th.teal)
            .frame(maxWidth: .infinity).frame(height: 62)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressStyle())
        .glassRect(18)
    }
}

/// Строка «подпись сверху, значение снизу» (.irow).
struct IRow<V: View>: View {
    let label: String
    @ViewBuilder var value: () -> V
    var action: (() -> Void)? = nil
    var body: some View {
        Button { action?() } label: { IRowLabel(label: label, value: value) }
            .buttonStyle(RowStyle())
            .disabled(action == nil)
    }
}

struct IRowLabel<V: View>: View {
    let label: String
    @ViewBuilder var value: () -> V
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.body(12.5)).foregroundStyle(Th.muted)
            value().font(Typo.body(15.5)).foregroundStyle(Th.fg)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Вкладки профиля: всё из переписок клиента.
struct ProfileMedia: View {
    @Environment(Store.self) private var store
    let contactId: String
    let tab: String

    private var all: [Message] {
        store.conversations(of: contactId).flatMap { store.messages($0.id) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let msgs = all
        Group {
            switch tab {
            case "media":
                let media = msgs.filter { $0.kind == "image" || $0.kind == "round" || $0.kind == "video" }
                if media.isEmpty { empty("Фото и видео из переписки появятся здесь") } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(media) { m in mediaCell(m) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 12).padding(.top, 12)
                }
            case "files":
                let files = msgs.filter { $0.kind == "file" }
                if files.isEmpty { empty("Файлов пока нет") } else {
                    VStack(spacing: 2) {
                        ForEach(files) { m in
                            frow(icon: AnyView(Icon(name: "file").foregroundStyle(Th.onTeal)), title: m.att?.name ?? "Файл", sub: Fmt.day(m.date))
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12)
                }
            case "links":
                let links = linksOf(msgs)
                if links.isEmpty { empty("Ссылок пока нет") } else {
                    VStack(spacing: 2) {
                        ForEach(links, id: \.self) { u in
                            Button { UIApplication.shared.open(u) } label: {
                                frow(icon: AnyView(Text(String((u.host ?? "?").replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                                    .font(Typo.body(16, .bold)).foregroundStyle(Th.ink)),
                                     title: u.host ?? u.absoluteString, sub: u.absoluteString, link: true, bg: Th.tBlue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12)
                }
            default:
                let voices = msgs.filter { $0.kind == "audio" }
                if voices.isEmpty { empty("Голосовых пока нет") } else {
                    VStack(spacing: 2) {
                        ForEach(voices) { m in
                            frow(icon: AnyView(Icon(name: "play", size: 16).foregroundStyle(Th.onTeal)), title: "Голосовое · " + Fmt.dur(m.att?.duration ?? 0),
                                 sub: (Calendar.current.isDateInToday(m.date) ? "сегодня, " + Fmt.hm(m.date) : Fmt.day(m.date)), round: true)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: tab)
    }

    @ViewBuilder private func mediaCell(_ m: Message) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if m.kind == "round" {
                ZStack { Th.fill8; CamPlaceholderOrThumb(m: m).clipShape(Circle()).padding(14) }
            } else if m.kind == "video" {
                VideoThumb(a: m.att!)
            } else {
                PhotoThumb(a: m.att!)
            }
            if m.kind == "round" {
                Text(Fmt.dur(m.att?.duration ?? 0)).font(Typo.body(11)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.black.opacity(0.45))).padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
    }

    private func frow(icon: AnyView, title: String, sub: String, link: Bool = false, round: Bool = false, bg: Color = Th.teal) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: round ? 22 : 12, style: .continuous).fill(bg))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.body(14.5, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                Text(sub).font(Typo.body(12.5)).foregroundStyle(link ? Th.teal : Th.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
    }

    private func empty(_ t: String) -> some View {
        Text(t).font(Typo.body(14)).foregroundStyle(Th.muted).frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func linksOf(_ msgs: [Message]) -> [URL] {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var out: [URL] = [], seen = Set<String>()
        for m in msgs where !m.body.isEmpty {
            let ns = m.body as NSString
            for r in det.matches(in: m.body, range: NSRange(location: 0, length: ns.length)) {
                if let u = r.url, !seen.contains(u.absoluteString) { seen.insert(u.absoluteString); out.append(u) }
            }
        }
        return out
    }
}

/// Кружок в сетке медиа: демо-кадр или первый кадр видео.
struct CamPlaceholderOrThumb: View {
    let m: Message
    @State private var img: UIImage?
    var body: some View {
        Group {
            if m.att?.url.hasPrefix("fixture:") == true { CamPlaceholder(back: m.att?.url == "fixture:back") }
            else if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Th.fill8 }
        }
        .task { if let a = m.att, !a.url.hasPrefix("fixture:"), let u = API.media(a.url) { img = await Thumbs.frame(u) } }
    }
}

/// Правка контакта: имя и фамилия (видите только вы), сохранить в телефонной книге, удалить.
struct EditContactView: View {
    @Environment(Store.self) private var store
    let contactId: String
    @State private var first = ""
    @State private var last = ""
    @State private var toBook = false
    @State private var delAsk = false
    @State private var busy = false

    var body: some View {
        let c = store.contact(contactId)
        Screen(bottom: 40) {
            HStack {
                GlassCap(title: "Отмена") { store.pop() }
                Spacer()
                Btn(title: "Готово", small: false, busy: busy) { save() }
                    .frame(height: 44)
            }
            .overlay { Text("Изменить").font(Typo.body(16, .bold)).foregroundStyle(Th.fg) }
            .padding(.horizontal, 16).frame(height: 52)
            VStack(spacing: 4) {
                Avatar(name: c.map { store.avatarName($0) } ?? "?", size: 96, url: c?.avatar)
                Btn(title: "Выбрать фото", kind: .text, small: true) { store.show("Фото берём из профиля клиента в соцсети") }
            }
            .padding(.top, 6).padding(.bottom, 16)
            VStack(spacing: 0) {
                TextField("", text: $first, prompt: Text("Имя").foregroundColor(Th.faint))
                    .font(Typo.body(16)).foregroundStyle(Th.fg).padding(.horizontal, 16).frame(height: 50)
                Hair(inset: 16)
                TextField("", text: $last, prompt: Text("Фамилия").foregroundColor(Th.faint))
                    .font(Typo.body(16)).foregroundStyle(Th.fg).padding(.horizontal, 16).frame(height: 50)
            }
            .glassRect(26).padding(.horizontal, 12)
            Hint(text: "Это имя видите только вы. Клиент его не узнает.")
            Group26 {
                GI(title: "Сохранить в контактах телефона", sub: c.flatMap { store.phoneOf($0) } ?? "Имя и ссылка на \(Net.name(c?.source))") {
                    Switch(on: toBook) { toBook.toggle() }
                }
            }
            Group26 {
                GI(title: "Удалить контакт", danger: true) { delAsk = true }
            }
            .padding(.top, 14)
        }
        .onAppear {
            let n = c.map { store.name($0) } ?? ""
            let parts = n.split(separator: " ", maxSplits: 1).map(String.init)
            first = parts.first ?? ""
            last = parts.count > 1 ? parts[1] : ""
            toBook = c.map { store.inBook($0) } ?? false
        }
        .confirmationDialog("Удалить контакт?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Удалить контакт", role: .destructive) {
                Task { await store.deleteChat(contactId: contactId); store.path = [] }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Клиент и его переписки пропадут из кабинета.") }
    }

    private func save() {
        guard let c = store.contact(contactId) else { return }
        let n = [first, last].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        busy = true
        Task {
            if !n.isEmpty && n != store.name(c) { _ = await store.rename(contactId, n) }
            if toBook && !store.inBook(c) { store.addToBook(store.contact(contactId) ?? c) } else { store.show("Контакт сохранён") }
            busy = false
            store.pop()
        }
    }
}
