import SwiftUI

struct ProfileView: View {
    @Environment(Store.self) private var store
    @State private var showDelete = false
    @State private var confirmLogout = false


    @State private var modules: CabinetModules.Flags?

    /// «5 папок · 3 метки» вместо голой цифры.
    private var foldersSummary: String {
        let f: String = ruCount(store.folders.count, "папка", "папки", "папок")
        let n: Int = store.labels.filter { tagIcon($0) == nil }.count
        return n > 0 ? f + " · " + ruCount(n, "метка", "метки", "меток") : f
    }

    var body: some View {
        let user = store.user
        let version: String = appVersion()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Профиль").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4)
                HStack(spacing: 14) {
                    Image("BrandIcon").resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.account?.workspaceName.flatMap { $0.isEmpty ? nil : $0 } ?? "Мой кабинет").font(Typo.body(17, .semibold)).foregroundStyle(Pal.fg)
                        Text((user?.email ?? "") + " · " + (user?.isOwner == true ? "владелец" : "сотрудник")).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(16)
                .glassRect(24)
                .padding(.top, 16)

                Cap("Работа")
                VStack(spacing: 0) {
                    navRow(first: true, icon: "calendar", color: Pal.mint, title: "Расписание", value: todayLessons) { store.open(.schedule) }
                    navRow(first: false, icon: "folder", color: Pal.sky, title: "Папки и метки", value: foldersSummary) { store.open(.folders) }
                    navRow(first: false, icon: "graduationcap", color: Pal.apricot, title: "Классы и группы", value: classesSummary) { store.open(.lists) }
                    navRow(first: false, icon: "person.2", color: Pal.lav, title: "Сотрудники", value: "\(max(1, store.state.team.count))") { store.open(.staff) }
                    if canSeePartners {
                        navRow(first: false, icon: "chart.bar", color: Pal.teal, title: "Партнёры", value: "") { store.open(.partners) }
                    }
                }
                .glassRect(24)

                Cap("Уведомления")
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        RowIcon(system: "bell", color: Pal.rose)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Новые сообщения и напоминания").foregroundStyle(Pal.fg)
                            Text("пуш на этот телефон").font(Typo.body(12)).foregroundStyle(Pal.fg3)
                        }
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.pushOn }, set: { store.setPush($0) }))
                    }
                    GroupRow {
                        RowIcon(system: "moon", color: Pal.lav)
                        Text("Тихие часы 23:00–08:00").foregroundStyle(Pal.fg)
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.quietOn }, set: { store.setQuiet($0) }))
                    }
                }
                .glassRect(24)

                Cap("Телефонная книга")
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        RowIcon(system: "person.crop.circle", color: Pal.sky)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Имена из контактов телефона").foregroundStyle(Pal.fg)
                            Text(store.bookAccess == false ? "нет доступа — разреши в настройках iPhone" : "для номеров WhatsApp и MAX").font(Typo.body(12)).foregroundStyle(Pal.fg3)
                        }
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.contactsOn && store.bookAccess != false }, set: { on in
                            if store.bookAccess == false, let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } else { store.setContactsOn(on) }
                        }))
                    }
                }
                .glassRect(24)

                Cap("Оформление")
                HStack(spacing: 8) {
                    ForEach([ThemeMode.system, .light, .dark], id: \.self) { m in
                        let t: (ThemeMode, String) = (m, m == .system ? "Система" : (m == .light ? "Светлая" : "Тёмная"))
                        Button { store.setTheme(t.0); haptic() } label: {
                            Text(t.1).font(Typo.body(14, .semibold))
                                .foregroundStyle(store.theme == t.0 ? Pal.onAcc : Pal.fg)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background {
                                    if store.theme == t.0 { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.acc) }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(8)
                .glassRect(24)

                Cap("Вход и защита")
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        RowIcon(system: "faceid", color: Pal.mint)
                        Text("Вход по Face ID").foregroundStyle(Pal.fg)
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.faceOn }, set: { store.requestFace($0) }))
                    }
                    Button { logoutOthers() } label: {
                        GroupRow {
                            RowIcon(system: "iphone.and.arrow.forward", color: Pal.apricot)
                            Text("Выйти на других устройствах").foregroundStyle(Pal.fg)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                .glassRect(24)

                Cap("Подключённые аккаунты")
                VStack(spacing: 0) {
                    if store.state.channels.isEmpty {
                        GroupRow(first: true) { Text("Пока ничего не подключено").foregroundStyle(Pal.fg2) }
                    }
                    ForEach(Array(store.state.channels.enumerated()), id: \.element.id) { i, ch in
                        let n = NetInfo.of(ch.type)
                        GroupRow(first: i == 0) {
                            Circle().fill(n.color).frame(width: 12, height: 12).padding(.horizontal, 9)
                            Text(n.name).foregroundStyle(Pal.fg)
                            Spacer()
                            Text(ch.name.replacingOccurrences(of: "WhatsApp ", with: "")).foregroundStyle(Pal.fg2).lineLimit(1).frame(maxWidth: 170, alignment: .trailing)
                            Circle().fill(ch.status == "connected" ? Pal.mint : (ch.status == "error" ? Pal.danger : Pal.apricot)).frame(width: 8, height: 8)
                        }
                    }
                }
                .glassRect(24)

                VStack(spacing: 0) {
                    Button { Task { await store.loadState(force: true); store.show("Обновлено") } } label: {
                        GroupRow(first: true) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 16))
                            Text("Обновить данные").font(Typo.body(16, .semibold))
                            Spacer()
                            if store.loading { ProgressView().tint(Pal.fg) }
                        }
                        .foregroundStyle(Pal.acc).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Button { confirmLogout = true } label: {
                        GroupRow {
                            Text("Выйти").font(Typo.body(16, .semibold)); Spacer()
                        }
                        .foregroundStyle(Pal.acc).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Button { showDelete = true } label: {
                        GroupRow {
                            Text("Удалить аккаунт").font(Typo.body(16, .semibold)); Spacer()
                        }
                        .foregroundStyle(Pal.danger).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                .glassRect(24)
                .padding(.top, 22)

                Text("Sguardo для iPhone · \(version)")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                if let e = store.lastError {
                    Text("Связь: \(e)").font(Typo.body(12)).foregroundStyle(Pal.danger).frame(maxWidth: .infinity).padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 130)
        }
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
        .refreshable { await store.loadState(force: true); await store.loadAccount() }
        .screenBackground(store.wall)
        .sheet(isPresented: $showDelete) { DeleteSheet() }
        .confirmationDialog("Выйти из кабинета на этом телефоне?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await store.logout() } }
            Button("Отмена", role: .cancel) {}
        }
        .task {
            if store.account == nil { await store.loadAccount() }
            if !store.fixture { modules = try? await API.get(CabinetModules.self, "/api/me/modules/").modules }
            if store.lessons.isEmpty { await store.loadLessons() }
        }
    }

    private var canSeePartners: Bool { store.fixture || modules?.partners == true || store.user?.features?.partners == true }

    private var todayLessons: String {
        let n = store.lessons(on: Date()).count
        return n > 0 ? "сегодня " + ruCount(n, "занятие", "занятия", "занятий") : ""
    }

    private var classesSummary: String {
        let c = store.classes.count, g = store.groups.count
        if c == 0 && g == 0 { return "" }
        return ruCount(c, "класс", "класса", "классов") + (g > 0 ? " · " + ruCount(g, "группа", "группы", "групп") : "")
    }

    private func logoutOthers() {
        Task {
            if store.fixture { store.show("Другие устройства вышли из кабинета"); return }
            do {
                _ = try await API.send("DELETE", "/api/account/sessions/")
                store.show("Другие устройства вышли из кабинета")
            } catch { store.show(friendly(error), ok: false) }
        }
    }

    private func navRow(first: Bool, icon: String, color: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            GroupRow(first: first) {
                RowIcon(system: icon, color: color)
                Text(title).foregroundStyle(Pal.fg)
                Spacer()
                Text(value).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

func appVersion() -> String {
    let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
    let short: String = info["CFBundleShortVersionString"] as? String ?? "1.0"
    let build: String = info["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
}

struct FoldersView: View {
    @Environment(Store.self) private var store
    @State private var names: [String: String] = [:]
    @State private var showLabel = false
    @State private var deleting: Folder?
    @State private var removingLabel: String?

    private func askRemove(_ l: String) {
        let used = store.state.contacts.contains { ($0.tags ?? []).contains(l) }
        if used { removingLabel = l } else { store.removeExtraLabel(l); store.show("Метка «\(l)» удалена") }
    }

    /// Снять метку со всех клиентов (по одному действию на клиента) и из списка приложения.
    private func removeEverywhere(_ l: String) async {
        let owners = store.state.contacts.filter { ($0.tags ?? []).contains(l) }
        var failed = 0
        for c in owners {
            let tags: [String] = (c.tags ?? []).filter { $0 != l }
            let ok = await store.act(["type": "updateContact", "contactId": c.id, "tags": tags])
            if !ok { failed += 1 }
        }
        store.removeExtraLabel(l)
        if failed == 0 { store.show("Метка «\(l)» снята у \(owners.count) клиентов") }
    }

    var body: some View {
        let owner = store.user?.isOwner == true
        VStack(spacing: 0) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { commitNames(); store.pop() }
                Spacer()
                Button { commitNames(); store.pop() } label: {
                    Text("Готово").font(Typo.body(15, .semibold)).padding(.horizontal, 16).frame(height: 40).primaryFill(20)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Папки").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4).padding(.top, 14)
                    Text(owner ? "Папка — этап сделки, у клиента она одна. Нажми на название, чтобы переименовать." : "Папки настраивает владелец кабинета.")
                        .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.horizontal, 4).padding(.top, 8)
                    Cap("Мои папки")
                    VStack(spacing: 0) {
                        ForEach(Array(store.folders.enumerated()), id: \.element.id) { i, f in
                            GroupRow(first: i == 0) {
                                Button { cycleColor(f) } label: {
                                    Circle().fill(Color(css: f.color)).frame(width: 22, height: 22)
                                }
                                .disabled(!owner)
                                TextField("", text: Binding(get: { names[f.id] ?? f.name }, set: { names[f.id] = $0 }))
                                    .font(Typo.body(16)).foregroundStyle(Pal.fg)
                                    .disabled(!owner)
                                    .submitLabel(.done)
                                    .onSubmit { commit(f) }
                                Text("\(store.state.contacts.filter { $0.folderId == f.id }.count)").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                                if owner {
                                    Button { Task { await store.act(["type": "moveFolder", "id": f.id, "dir": -1]) } } label: {
                                        Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 30)
                                    }
                                    .foregroundStyle(Pal.fg.opacity(i == 0 ? 0.2 : 0.7))
                                    .disabled(i == 0)
                                    Button { deleting = f } label: {
                                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
                                    }
                                    .foregroundStyle(Pal.fg.opacity(0.55))
                                }
                            }
                        }
                        if owner {
                            Button { Task { await store.act(["type": "addFolder", "name": "Новая папка", "color": "#B9A9DE"], ok: "Папка добавлена") } } label: {
                                GroupRow {
                                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                                    Text("Новая папка").font(Typo.body(16, .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Pal.acc).contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)
                    .buttonStyle(PressStyle())

                    Cap("Метки")
                    FlowLayout(spacing: 8) {
                        ForEach(store.labels.filter { tagIcon($0) == nil }, id: \.self) { l in
                            HStack(spacing: 4) {
                                Text(l).font(Typo.body(13, .semibold))
                                Button { askRemove(l) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20) }
                                    .accessibilityLabel("Удалить метку \(l)")
                            }
                            .foregroundStyle(Pal.ink)
                            .padding(.leading, 14).padding(.trailing, 6)
                            .frame(height: 32)
                            .background(Capsule().fill(labelColor(l)))
                        }
                        Button { showLabel = true } label: {
                            Text("+ Метка").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                                .padding(.horizontal, 14).frame(height: 32)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Pal.fg.opacity(0.4)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)
                    Text("Снять метку с одного клиента — крестик на метке в чате или нажатие в карточке. Крестик здесь удаляет метку у всех клиентов.")
                        .font(Typo.body(13)).foregroundStyle(Pal.fg3).lineSpacing(3).padding(.horizontal, 16).padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
        .sheet(isPresented: $showLabel) { LabelSheet(contactId: nil) }
        .confirmationDialog("Удалить метку «\(removingLabel ?? "")» у всех клиентов?", isPresented: Binding(get: { removingLabel != nil }, set: { if !$0 { removingLabel = nil } }), titleVisibility: .visible) {
            if let l = removingLabel {
                Button("Удалить у всех", role: .destructive) {
                    removingLabel = nil
                    Task { await removeEverywhere(l) }
                }
            }
            Button("Отмена", role: .cancel) { removingLabel = nil }
        }
        .confirmationDialog("Удалить папку «\(deleting?.name ?? "")»?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let f = deleting, let to = store.folders.first(where: { $0.id != f.id }) {
                Button("Удалить, клиентов — в «\(to.name)»", role: .destructive) {
                    Task { await store.act(["type": "removeFolder", "id": f.id, "moveTo": to.id], ok: "Папка удалена, клиенты — в «\(to.name)»") }
                    deleting = nil
                }
            }
            Button("Отмена", role: .cancel) { deleting = nil }
        }
    }

    private func commit(_ f: Folder) {
        guard let n = names[f.id]?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != f.name else { return }
        Task { await store.act(["type": "updateFolder", "id": f.id, "name": String(n.prefix(60))], ok: "Переименовано") }
    }

    private func commitNames() {
        for f in store.folders { commit(f) }
    }

    private func cycleColor(_ f: Folder) {
        let pal = Pal.folderHex
        let i = pal.firstIndex(of: (f.color ?? "").uppercased()) ?? -1
        let next = pal[(i + 1) % pal.count]
        Task { await store.act(["type": "updateFolder", "id": f.id, "color": next]) }
    }
}
