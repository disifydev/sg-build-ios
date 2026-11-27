import SwiftUI

/// «Ещё»: кабинет, работа, уведомления, телефонная книга, оформление. Тарифа и подключения соцсетей нет (решение владелицы).
struct MoreView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Screen(bottom: 120) {
            TabHeader(title: "Ещё") { EmptyView() }
            Button { store.open(.account) } label: {
                HStack(spacing: 14) {
                    Avatar(name: store.user?.name ?? "Владелец", size: 56, color: Color(hex: 0xC7E2D3))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.user?.name ?? "Кабинет").font(Typo.body(17, .semibold)).foregroundStyle(Th.fg)
                        Text(store.account?.workspaceName ?? (store.user?.email ?? "")).font(Typo.body(13)).foregroundStyle(Th.muted)
                    }
                    Spacer()
                    Chev()
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .glassRect(26)
            .padding(.horizontal, 12)

            SectTitle(title: "Работа")
            Group26 {
                let n = store.lessons(on: Date()).count
                GI(icon: "cal", title: "Расписание", sub: "Сегодня \(n) \(pl(n, "занятие", "занятия", "занятий"))", action: { store.open(.schedule) }) { Chev() }
                Hair()
                GI(icon: "sliders", title: "Папки", sub: "Названия, цвета и порядок", action: { store.open(.folders) }) { Chev() }
                Hair()
                GI(icon: "book", title: "Классы и предметы",
                   sub: "\(store.classes.count) \(pl(store.classes.count, "класс", "класса", "классов")), \(store.subjects.count) \(pl(store.subjects.count, "предмет", "предмета", "предметов"))",
                   action: { store.open(.lists) }) { Chev() }
                Hair()
                GI(icon: "shield", title: "Вход и устройства", sub: "Это устройство и другие сеансы", action: { store.open(.security) }) { Chev() }
            }

            SectTitle(title: "Уведомления")
            Group26 {
                GI(icon: "chat", title: "Новые сообщения", sub: store.pushOn ? "Имя клиента и текст сообщения" : "Выключены", action: { store.setPush(!store.pushOn) }) {
                    Switch(on: store.pushOn) { store.setPush(!store.pushOn) }
                }
                Hair()
                GI(icon: "bell", title: "Напоминания", sub: "Об оплатах и занятиях", action: { store.setReminders(!store.remindersOn) }) {
                    Switch(on: store.remindersOn) { store.setReminders(!store.remindersOn) }
                }
            }

            SectTitle(title: "ИИ-помощник")
            Group26 {
                GI(icon: "bolt", title: "Перевод и расшифровка через ИИ",
                   sub: "Текст сообщений и звук голосовых отправляются в ИИ-сервисы (Google Gemini, DeepL, Groq и другие) для перевода и расшифровки. Подробнее — в политике конфиденциальности",
                   action: { toggleAI() }) {
                    Switch(on: store.translateOn) { toggleAI() }
                }
            }

            SectTitle(title: "Защита")
            Group26 {
                GI(icon: "faceid", title: "Вход по Face ID", sub: "Спрашивать при открытии приложения", action: { store.setFace(!store.faceOn) }) {
                    Switch(on: store.faceOn) { store.setFace(!store.faceOn) }
                }
            }

            SectTitle(title: "Телефонная книга")
            Group26 {
                let on = store.contactsOn && store.bookAccess != false
                GI(icon: "book", title: "Брать имена из контактов телефона",
                   sub: store.bookAccess == false ? "Нет доступа к контактам. Нажмите, чтобы разрешить" : "Если номер клиента WhatsApp или MAX есть в контактах телефона, покажем имя оттуда",
                   action: { toggleBook(on) }) {
                    Switch(on: on) { toggleBook(on) }
                }
            }

            SectTitle(title: "Оформление")
            Group26 {
                themeRow(.system, "Как в системе", "Светлая днём, тёмная ночью", "phone")
                Hair()
                themeRow(.light, "Светлая", nil, "star")
                Hair()
                themeRow(.dark, "Тёмная", nil, "moon")
            }
            Text("Sguardo для iPhone · версия \(appVersion())").font(Typo.body(12)).foregroundStyle(Th.faint).padding(.top, 22)
            Button { UIApplication.shared.open(URL(string: "https://sguardo.ru/lk/privacy")!) } label: {
                Text("Политика конфиденциальности").font(Typo.body(12, .medium)).foregroundStyle(Th.teal)
            }
            .padding(.top, 6)
        }
        .confirmationDialog("Разрешить отправку в ИИ-сервисы?", isPresented: $aiAsk, titleVisibility: .visible) {
            Button("Разрешить") { Task { await store.setTranslate(true) } }
            Button("Не разрешать", role: .cancel) {}
        } message: {
            Text("Для перевода и расшифровки текст сообщений клиентов и звук голосовых будут передаваться сторонним ИИ-сервисам: Google (Gemini), DeepL, Groq, Cerebras, Mistral, OpenRouter, Anthropic. Выключить можно здесь же в любой момент.")
        }
    }

    @State private var aiAsk = false

    private func toggleAI() {
        if store.user?.isOwner == false { store.show("Перевод включает владелец кабинета", ok: false); return }
        if store.translateOn { Task { await store.setTranslate(false) } } else { aiAsk = true }
    }

    private func toggleBook(_ on: Bool) {
        if store.bookAccess == false, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            return
        }
        store.setContactsOn(!on)
    }

    private func themeRow(_ t: ThemeMode, _ title: String, _ sub: String?, _ icon: String) -> some View {
        GI(icon: icon, title: title, sub: sub, action: { store.setTheme(t) }) {
            if store.theme == t { Icon(name: "check", size: 16).foregroundStyle(Th.teal) }
        }
    }
}

/// Кабинет: имя, роль, сотрудники, почта, вход и устройства, веб-кабинет, выход.
struct AccountView: View {
    @Environment(Store.self) private var store
    @State private var logoutAsk = false
    @State private var deleteAsk = false
    @State private var deleteSure = false

    var body: some View {
        Screen {
            TopBar(back: { store.pop() })
            VStack(spacing: 4) {
                Avatar(name: store.user?.name ?? "В", size: 96, color: Color(hex: 0xC7E2D3))
                Text(store.user?.name ?? "Кабинет").font(Typo.display(23, .semibold)).foregroundStyle(Th.fg).padding(.top, 10)
                Text((store.user?.isOwner == true ? "владелец" : "сотрудник") + (store.account?.workspaceName.map { " · " + $0 } ?? ""))
                    .font(Typo.body(13)).foregroundStyle(Th.muted)
            }
            .padding(.bottom, 16)
            Group26 {
                GI(icon: "users", title: "Сотрудники", sub: store.state.team.map { String($0.name.split(separator: " ").first ?? "") }.joined(separator: ", "),
                   action: { store.open(.staff) }) { Chev() }
            }
            Group26 {
                GI(icon: "mail", title: "Почта для входа", sub: store.user?.email ?? store.account?.email ?? "—")
                Hair()
                GI(icon: "shield", title: "Вход и устройства", sub: "Это устройство и другие сеансы", action: { store.open(.security) }) { Chev() }
            }
            .padding(.top, 12)
            Group26 {
                Button { logoutAsk = true } label: {
                    Text("Выйти из кабинета").font(Typo.body(15)).foregroundStyle(Th.danger).frame(maxWidth: .infinity).frame(height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
                Hair(inset: 0)
                Button { deleteAsk = true } label: {
                    Text("Удалить аккаунт").font(Typo.body(15)).foregroundStyle(Th.danger).frame(maxWidth: .infinity).frame(height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
            }
            .padding(.top, 16)
            Text(store.user?.isOwner == false
                 ? "Удаление сотрудника стирает только вашу учётную запись, кабинет остаётся у владельца."
                 : "Удаление аккаунта владельца удаляет кабинет целиком: переписки, клиентов, оплаты и сотрудников. Вернуть их будет нельзя.")
                .font(Typo.body(12.5)).foregroundStyle(Th.muted).multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 10)
        }
        .confirmationDialog("Удалить аккаунт навсегда?", isPresented: $deleteAsk, titleVisibility: .visible) {
            Button("Удалить аккаунт", role: .destructive) { deleteSure = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(store.user?.isOwner == false ? "Ваша учётная запись будет удалена." : "Кабинет, переписки, клиенты и оплаты будут удалены без возможности восстановления.")
        }
        .alert("Точно удалить?", isPresented: $deleteSure) {
            Button("Удалить", role: .destructive) { Task { _ = await store.deleteAccount() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Это действие нельзя отменить.") }
        .confirmationDialog("Выйти из кабинета?", isPresented: $logoutAsk, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await store.logout() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("На этом телефоне перестанут приходить уведомления.") }
    }
}

/// Сотрудники с ролями и приглашением.
struct StaffView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Screen {
            TopBar(back: { store.pop() }) {
                if store.user?.isOwner == true { GlassCircle(icon: "userPlus", label: "Пригласить") { store.sheet = .invite } }
            }
            LargeTitle(title: "Сотрудники")
            Hint(text: "Сотрудники видят чаты кабинета. Роль определяет, что им можно менять.").padding(.top, -14)
            Group26 {
                ForEach(Array(store.state.team.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Hair() }
                    let me = m.id == store.user?.id
                    GI(title: m.name + (me ? " (вы)" : ""), sub: m.role == "owner" ? "Полный доступ" : (m.email ?? "Видит чаты кабинета"),
                       lead: AnyView(Avatar(name: m.name, size: 36)),
                       action: { if me || m.role == "owner" { store.show(me ? "Это вы, владелец кабинета" : "Владелец кабинета") } else if store.user?.isOwner == true { store.sheet = .staff(m.id) } }) {
                        Text(m.roleTitle).font(Typo.body(12, .semibold)).foregroundStyle(Th.teal)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Th.tealSoft))
                    }
                }
            }
            if store.user?.isOwner == true {
                Btn(title: "Пригласить сотрудника", icon: "userPlus", kind: .tonal) { store.sheet = .invite }.padding(.top, 14)
            }
        }
    }
}

/// Вход и устройства: это устройство, выход на других, смена пароля, Face ID.
struct SecurityView: View {
    @Environment(Store.self) private var store
    @State private var busy = false

    var body: some View {
        Screen {
            TopBar(back: { store.pop() })
            LargeTitle(title: "Вход и устройства")
            Group26 {
                GI(icon: "phone", title: UIDevice.current.name + " · это устройство", sub: "Сейчас")
                Hair()
                GI(icon: "laptop", title: "Другие устройства", sub: "Компьютер, другие телефоны") {
                    Btn(title: "Выйти", kind: .outline, small: true, busy: busy) {
                        busy = true
                        Task {
                            if !store.fixture {
                                do { _ = try await API.send("DELETE", "/api/account/sessions/"); store.show("Сеансы на других устройствах завершены") }
                                catch { store.show(friendly(error), ok: false) }
                            } else { store.show("Сеансы на других устройствах завершены") }
                            busy = false
                        }
                    }
                }
            }
            SectTitle(title: "Пароль")
            Group26 {
                GI(icon: "mail", title: "Сменить пароль", sub: "Пришлём код на почту", action: { store.sheet = .password }) { Chev() }
            }
            SectTitle(title: "Защита")
            Group26 {
                GI(icon: "faceid", title: "Вход по Face ID", sub: "Спрашивать при открытии приложения", action: { store.setFace(!store.faceOn) }) {
                    Switch(on: store.faceOn) { store.setFace(!store.faceOn) }
                }
            }
        }
    }
}

/// Классы (для фильтра учеников) и предметы (для расписания).
struct ListsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Screen {
            TopBar(back: { store.pop() })
            LargeTitle(title: "Классы и предметы")
            Hint(text: "Классы нужны для фильтра учеников, предметы для расписания. Нажмите, чтобы переименовать или удалить.").padding(.top, -14)
            SectTitle(title: "Классы")
            if store.classes.isEmpty {
                Text("Классов пока нет").font(Typo.body(14)).foregroundStyle(Th.muted).padding(.vertical, 10)
            } else {
                Group26 {
                    ForEach(Array(store.classes.enumerated()), id: \.element) { i, k in
                        if i > 0 { Hair() }
                        let n = store.classCount(k)
                        GI(icon: "users", title: classTitle(k), sub: "\(n) \(pl(n, "ученик", "ученика", "учеников"))", action: { store.sheet = .classItem(k) }) {
                            Icon(name: "edit", size: 16).foregroundStyle(Th.faint)
                        }
                    }
                }
            }
            Btn(title: "Добавить класс", icon: "plus", kind: .tonal) { store.sheet = .classItem(nil) }.padding(.top, 12)
            SectTitle(title: "Предметы")
            Group26 {
                ForEach(Array(store.subjects.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Hair(inset: 46) }
                    GI(title: s.name, lead: AnyView(Circle().fill(Color(css: s.color)).frame(width: 14, height: 14).padding(.horizontal, 8)),
                       action: { store.sheet = .subject(i) }) {
                        Icon(name: "edit", size: 16).foregroundStyle(Th.faint)
                    }
                }
            }
            Btn(title: "Добавить предмет", icon: "plus", kind: .tonal) { store.sheet = .subject(nil) }.padding(.top, 12)
            Text("Предметы хранятся на этом телефоне").font(Typo.body(12)).foregroundStyle(Th.faint).padding(.top, 14)
        }
    }
}

/// Папки: имя, цвет, порядок перетаскиванием.
struct FoldersView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            Aurora()
            List {
                Group {
                    TopBar(back: { store.pop() }) {
                        GlassCircle(icon: "plus", label: "Новая папка") { store.sheet = .folder(nil) }
                    }
                    LargeTitle(title: "Папки")
                    Hint(text: "Папка показывает, на каком этапе клиент. Зажмите папку и перетащите, чтобы поменять порядок. Нажмите на папку, чтобы переименовать или сменить цвет.")
                        .padding(.top, -14)
                }
                .plainRow()
                ForEach(Array(store.folders.enumerated()), id: \.element.id) { i, f in
                    let n = store.state.contacts.filter { $0.folderId == f.id }.count
                    Button { store.sheet = .folder(f.id) } label: {
                        HStack(spacing: 14) {
                            Circle().fill(Color(css: f.color)).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(Typo.body(15)).foregroundStyle(Th.fg)
                                Text("\(n) \(pl(n, "клиент", "клиента", "клиентов"))").font(Typo.body(12.5)).foregroundStyle(Th.muted)
                            }
                            Spacer()
                            Icon(name: "edit", size: 16).foregroundStyle(Th.faint)
                        }
                        .padding(.horizontal, 2).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cardRow(cardPos(i, count: store.folders.count))
                }
                .onMove { from, to in store.moveFolders(from: from, to: to) }
                Group {
                    Btn(title: "Создать папку", icon: "plus", kind: .tonal) { store.sheet = .folder(nil) }
                        .frame(maxWidth: .infinity).padding(.top, 14)
                    Color.clear.frame(height: 60)
                }
                .plainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }
}

/// Уведомления: новые сообщения, оплаты, напоминания, занятия за сутки.
struct NotificationsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let list = store.notes
        Screen {
            TopBar(back: { store.pop() })
            LargeTitle(title: "Уведомления")
            if list.isEmpty {
                EmptyBlock(icon: "bell", title: "Новых уведомлений нет", text: "Здесь появятся сообщения клиентов и напоминания")
            } else {
                Group26 {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Hair(inset: 68) }
                        row(n)
                    }
                }
                Hint(text: "Здесь собраны новые сообщения, напоминания об оплатах и занятиях за последние сутки.")
            }
        }
        .onDisappear { store.seeNotes() }
    }

    private func row(_ n: NoteItem) -> some View {
        let (icon, tint): (String, Color) = {
            switch n.kind {
            case .msg: return ("chat", Th.tBlue)
            case .pay: return ("wallet", Th.tPink)
            case .rem: return ("bell", Th.tYellow)
            case .les: return ("cal", Th.tGreen)
            }
        }()
        let fresh = n.at > store.notifSeen
        return Button { go(n) } label: {
            HStack(alignment: .top, spacing: 12) {
                Icon(name: icon, size: 16).foregroundStyle(Th.chipInk).frame(width: 40, height: 40).background(Circle().fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title).font(Typo.body(15, .semibold)).foregroundStyle(Th.fg)
                    Text(n.sub).font(Typo.body(14)).foregroundStyle(Th.muted).lineSpacing(1).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Text(Fmt.when(n.at)).font(Typo.body(12)).foregroundStyle(Th.faint)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .bottomTrailing) {
                if fresh { Circle().fill(Th.teal).frame(width: 9, height: 9).padding(16) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
    }

    private func go(_ n: NoteItem) {
        switch n.kind {
        case .les: store.path = [.schedule]
        case .pay: store.path = []; store.tab = .payments
        default:
            if let c = n.convId { store.path = []; store.openChat(c) }
        }
    }
}
