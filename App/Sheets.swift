import SwiftUI

/// Все листы приложения в одном месте: открываются через store.sheet.
struct SheetHost: View {
    @Environment(Store.self) private var store
    let kind: SheetKind

    var body: some View {
        Group {
            switch kind {
            case .newPay(let c): NewPaySheet(presetContact: c)
            case .newClient: NewClientSheet()
            case .invite: InviteSheet()
            case .staff(let id): StaffSheet(memberId: id)
            case .classItem(let k): ClassSheet(old: k)
            case .subject(let i): SubjectSheet(index: i)
            case .folder(let f): FolderSheet(folderId: f)
            case .lesson(let l): LessonSheet(lessonId: l)
            case .addLesson(let e): AddLessonSheet(editId: e)
            case .forward(let c, let m): ForwardSheet(conv: c, mids: m)
            case .attach(let c): AttachSheet(conv: c)
            case .schedSend(let c, let t): SchedSendSheet(conv: c, text: t)
            case .scheduledList(let c): ScheduledListSheet(conv: c)
            case .password: PasswordSheet()
            }
        }
        .environment(store)
        .preferredColorScheme(store.colorScheme)
        .sheetChrome(detents(kind))
    }

    private func detents(_ k: SheetKind) -> Set<PresentationDetent> {
        switch k {
        case .attach, .schedSend, .lesson, .classItem, .password: return [.medium]
        default: return [.large]
        }
    }
}

@MainActor private func close(_ store: Store) { store.sheet = nil }

/// Сетка цветов (.sw-grid).
struct Swatches: View {
    @Binding var color: String
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            ForEach(Th.folderHex, id: \.self) { c in
                Button { haptic(); withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { color = c } } label: {
                    Circle().fill(Color(css: c))
                        .overlay(Circle().stroke(Th.cream, lineWidth: 2).padding(3))
                        .overlay(Circle().stroke(color == c ? Th.fg : .clear, lineWidth: 3))
                        .aspectRatio(1, contentMode: .fit)
                        .scaleEffect(color == c ? 1.12 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Цвет")
            }
        }
    }
}

/// Выбор клиента по имени: поле и подходящие варианты.
struct ContactPicker: View {
    @Environment(Store.self) private var store
    @Binding var query: String
    @Binding var picked: String?
    var onlyWithChat = false

    var body: some View {
        VStack(spacing: 6) {
            SheetField(icon: "user", placeholder: "Имя клиента", text: $query)
                .onChange(of: query) { _, q in
                    if let p = picked, store.name(store.contact(p)) != q { picked = nil }
                }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if picked == nil && !q.isEmpty {
                let list = store.state.contacts.filter { c in
                    store.name(c).lowercased().contains(q) && (!onlyWithChat || store.mainConversation(of: c.id) != nil)
                }.prefix(5)
                ForEach(Array(list)) { c in
                    Button {
                        picked = c.id
                        query = store.name(c)
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(name: store.avatarName(c), network: c.source, size: 32)
                            Text(store.name(c)).font(Typo.body(15)).foregroundStyle(Th.fg)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowStyle())
                }
            }
        }
    }
}

// MARK: - оплата

struct NewPaySheet: View {
    @Environment(Store.self) private var store
    let presetContact: String?
    @State private var query = ""
    @State private var picked: String?
    @State private var product: String?
    @State private var amount = ""
    @State private var status = "paid"
    @State private var busy = false

    var body: some View {
        SheetBody(title: "Новая оплата") {
            Lbl("Клиент")
            if presetContact != nil {
                SheetField(icon: "user", placeholder: "Имя клиента", text: .constant(query)).disabled(true)
            } else {
                ContactPicker(query: $query, picked: $picked)
            }
            Lbl("Товар или услуга")
            VStack(spacing: 7) {
                ForEach(store.state.products) { p in
                    Button { haptic(); product = p.id; amount = String(Int(p.price)) } label: {
                        HStack {
                            Text(p.name).font(Typo.body(14.5)).foregroundStyle(Th.fg)
                            Spacer()
                            Text(store.money(p.price)).font(Typo.body(14.5, .semibold)).foregroundStyle(Th.fg).monospacedDigit()
                        }
                        .padding(.horizontal, 16).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(product == p.id ? Th.tealSoft : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(product == p.id ? Th.teal : Th.hair, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Lbl(store.state.products.isEmpty ? "Сумма" : "Сумма (можно изменить)")
            SheetField(icon: "wallet", placeholder: "Например, 3500", text: $amount, keyboard: .numberPad)
            Lbl("Статус")
            Seg(items: [("paid", "Оплачено", nil), ("promised", "Обещал оплатить", nil)], selection: $status, glassy: false)
            Btn(title: "Добавить" + (amountValue > 0 ? " · " + store.money(amountValue) : ""), icon: "check", wide: true, busy: busy) { save() }
                .padding(.top, 18)
        }
        .onAppear {
            if let c = presetContact { picked = c; query = store.name(store.contact(c)) }
        }
    }

    private var amountValue: Double { Double(amount.filter(\.isNumber)) ?? 0 }

    private func save() {
        guard let c = picked else { store.show("Выберите клиента из списка", ok: false); return }
        guard amountValue > 0 else { store.show("Укажите сумму или выберите товар", ok: false); return }
        busy = true
        Task {
            await store.addPayment(contactId: c, productId: product, amount: amountValue, paid: status == "paid")
            busy = false
            close(store)
        }
    }
}

// MARK: - клиент

struct NewClientSheet: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var phone = ""
    @State private var net = "telegram"
    @State private var folder: String?
    @State private var klass: String?
    @State private var busy = false
    private let nets = ["telegram", "whatsapp", "instagram", "vk", "max", "avito"]

    var body: some View {
        SheetBody(title: "Новый клиент") {
            Lbl("Имя")
            SheetField(icon: "user", placeholder: "Имя и фамилия", text: $name)
            Lbl("Телефон")
            SheetField(icon: "phone", placeholder: "+7", text: $phone, keyboard: .phonePad)
            Lbl("Соцсеть")
            Flow { ForEach(nets, id: \.self) { n in FChip(title: Net.name(n), on: net == n, network: n) { net = n } } }
            Lbl("Папка")
            Flow { ForEach(store.folders) { f in FChip(title: f.name, on: folder == f.id, dot: Color(css: f.color)) { folder = f.id } } }
            if !store.classes.isEmpty {
                Lbl("Класс")
                Flow { ForEach(store.classes, id: \.self) { k in FChip(title: classTitle(k), on: klass == k) { klass = klass == k ? nil : k } } }
            }
            Btn(title: "Добавить клиента", icon: "check", wide: true, busy: busy) { save() }.padding(.top, 18)
        }
        .onAppear { folder = store.folders.first?.id }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { store.show("Укажите имя клиента", ok: false); return }
        busy = true
        Task {
            await store.addClient(name: n, phone: phone.trimmingCharacters(in: .whitespaces), network: net, folderId: folder, klass: klass)
            busy = false
            close(store)
        }
    }
}

// MARK: - сотрудники

private let roles: [(String, String)] = [("Администратор", "всё, кроме удаления кабинета"), ("Менеджер", "чаты, клиенты и оплаты"), ("Только просмотр", "только свои клиенты, без оплат")]

private struct RolePicker: View {
    @Binding var role: String
    var body: some View {
        VStack(spacing: 7) {
            ForEach(roles.indices, id: \.self) { i in
                let r = roles[i]
                Button { haptic(); role = r.0 } label: {
                    HStack {
                        Text(r.0).font(Typo.body(14.5)).foregroundStyle(Th.fg)
                        Spacer()
                        Text(r.1).font(Typo.body(12)).foregroundStyle(Th.muted)
                    }
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(role == r.0 ? Th.tealSoft : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(role == r.0 ? Th.teal : Th.hair, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct InviteSheet: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var role = "Менеджер"
    @State private var step = 0
    @State private var busy = false

    var body: some View {
        SheetBody(title: step == 0 ? "Пригласить сотрудника" : "Код из письма") {
            if step == 0 {
                Lbl("Имя")
                SheetField(icon: "user", placeholder: "Имя и фамилия", text: $name)
                Lbl("Почта")
                SheetField(icon: "mail", placeholder: "Куда отправить приглашение", text: $email, keyboard: .emailAddress)
                Lbl("Пароль для входа")
                SheetField(icon: "lock", placeholder: "Не короче 8 символов", text: $password, secure: true)
                Lbl("Роль")
                RolePicker(role: $role)
                Btn(title: "Отправить приглашение", icon: "check", wide: true, busy: busy) { invite() }.padding(.top, 18)
            } else {
                Text("Мы отправили код на \(email). Попросите сотрудника продиктовать его.").font(Typo.body(14)).foregroundStyle(Th.muted)
                    .multilineTextAlignment(.center)
                Lbl("Код")
                SheetField(icon: "lock", placeholder: "6 цифр", text: $code, keyboard: .numberPad)
                Btn(title: "Подтвердить", icon: "check", wide: true, busy: busy) { confirm() }.padding(.top, 18)
            }
        }
    }

    private func invite() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, e.contains("@") else { store.show("Укажите имя и почту", ok: false); return }
        busy = true
        Task {
            defer { busy = false }
            if store.fixture { withAnimation { step = 1 }; return }
            do {
                _ = try await API.send("POST", "/api/team/", json: ["name": name, "email": e, "password": password])
                withAnimation { step = 1 }
            } catch { store.show(friendly(error), ok: false) }
        }
    }

    private func confirm() {
        busy = true
        Task {
            defer { busy = false }
            let e = email.trimmingCharacters(in: .whitespaces).lowercased()
            if store.fixture { store.show("Приглашение для \(name) принято"); close(store); return }
            if await store.stateCall("POST", "/api/team/", ["email": e, "code": code.filter(\.isNumber)], ok: "\(name) теперь в кабинете") {
                if let m = store.state.team.first(where: { $0.email?.lowercased() == e }), role != "Менеджер" { await store.setRole(m.id, role) }
                close(store)
            }
        }
    }
}

struct StaffSheet: View {
    @Environment(Store.self) private var store
    let memberId: String
    @State private var role = "Менеджер"
    @State private var delAsk = false
    @State private var busy = false

    var body: some View {
        let m = store.member(memberId)
        SheetBody(title: m?.name ?? "Сотрудник") {
            Lbl("Роль")
            RolePicker(role: $role)
            Btn(title: "Сохранить", icon: "check", wide: true, busy: busy) {
                busy = true
                Task { await store.setRole(memberId, role); busy = false; close(store) }
            }
            .padding(.top, 18)
            Btn(title: "Убрать из кабинета", kind: .text, wide: true, danger: true) { delAsk = true }.padding(.top, 6)
        }
        .onAppear { role = m?.roleTitle ?? "Менеджер" }
        .confirmationDialog("Убрать \(m?.name ?? "сотрудника") из кабинета?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) { Task { await store.removeMember(memberId); close(store) } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Сотрудник потеряет доступ к чатам.") }
    }
}

// MARK: - классы, предметы, папки

struct ClassSheet: View {
    @Environment(Store.self) private var store
    let old: String?
    @State private var name = ""
    @State private var delAsk = false

    var body: some View {
        SheetBody(title: old == nil ? "Новый класс" : "Класс") {
            Lbl("Название")
            SheetField(icon: "edit", placeholder: "Например, 8 класс", text: $name)
            Btn(title: old == nil ? "Добавить" : "Сохранить", icon: "check", wide: true) {
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { store.show("Введите название", ok: false); return }
                store.saveClass(old: old, new: name)
                close(store)
            }
            .padding(.top, 18)
            if old != nil { Btn(title: "Удалить", kind: .text, wide: true, danger: true) { delAsk = true }.padding(.top, 6) }
        }
        .onAppear { name = old ?? "" }
        .confirmationDialog("Удалить «\(old.map(classTitle) ?? "")»?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let old { store.deleteClass(old) }; close(store) }
            Button("Отмена", role: .cancel) {}
        } message: { Text("У учеников этого класса поле станет пустым.") }
    }
}

struct SubjectSheet: View {
    @Environment(Store.self) private var store
    let index: Int?
    @State private var name = ""
    @State private var color = "#86C7A6"

    var body: some View {
        SheetBody(title: index == nil ? "Новый предмет" : "Предмет") {
            Lbl("Название")
            SheetField(icon: "edit", placeholder: "Например, Английский", text: $name)
            Lbl("Цвет в расписании")
            Swatches(color: $color)
            Btn(title: index == nil ? "Добавить" : "Сохранить", icon: "check", wide: true) { save() }.padding(.top, 18)
            if let i = index {
                Btn(title: "Удалить", kind: .text, wide: true, danger: true) {
                    store.subjects.remove(at: i); store.saveSubjects(); store.show("Удалено"); close(store)
                }
                .padding(.top, 6)
            }
        }
        .onAppear {
            if let i = index, i < store.subjects.count { name = store.subjects[i].name; color = store.subjects[i].color }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { store.show("Введите название", ok: false); return }
        if let i = index, i < store.subjects.count {
            let old = store.subjects[i].name
            store.subjects[i] = SubjectItem(name: n, color: color)
            for (k, v) in store.lessonSubject where v == old { store.lessonSubject[k] = n }
        } else {
            store.subjects.append(SubjectItem(name: n, color: color))
        }
        store.saveSubjects()
        store.show(index == nil ? "Добавлено" : "Сохранено")
        close(store)
    }
}

struct FolderSheet: View {
    @Environment(Store.self) private var store
    let folderId: String?
    @State private var name = ""
    @State private var color = "#E59AA0"
    @State private var delAsk = false
    @State private var busy = false

    var body: some View {
        SheetBody(title: folderId == nil ? "Новая папка" : "Папка") {
            Lbl("Название")
            SheetField(icon: "edit", placeholder: "Например, Пробное занятие", text: $name)
            Lbl("Цвет")
            Swatches(color: $color)
            Btn(title: folderId == nil ? "Создать папку" : "Сохранить", icon: "check", wide: true, busy: busy) {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { store.show("Введите название папки", ok: false); return }
                busy = true
                Task { await store.saveFolder(id: folderId, name: n, color: color); busy = false; close(store) }
            }
            .padding(.top, 18)
            if folderId != nil && store.folders.count > 1 {
                Btn(title: "Удалить папку", kind: .text, wide: true, danger: true) { delAsk = true }.padding(.top, 6)
            }
        }
        .onAppear {
            if let f = store.folder(folderId) { name = f.name; color = f.color ?? color }
        }
        .confirmationDialog("Удалить папку «\(name)»?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Удалить папку", role: .destructive) { if let id = folderId { Task { await store.removeFolder(id); close(store) } } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Клиенты из неё перейдут в «\(store.folders.first { $0.id != folderId }?.name ?? "другую папку")».") }
    }
}

// MARK: - занятия

struct LessonSheet: View {
    @Environment(Store.self) private var store
    let lessonId: String
    @State private var delAsk = false

    var body: some View {
        let l = store.lessons.first { $0.id == lessonId }
        SheetBody(title: l.flatMap { store.subject(of: $0)?.name } ?? "Занятие") {
            if let l {
                VStack(spacing: 0) {
                    IRowLabel(label: "когда") { Text(Fmt.day(l.start) + ", " + Fmt.hm(l.start)) }
                    Hair(inset: 16)
                    IRowLabel(label: "длительность") { Text("\(l.minutes) мин") }
                    Hair(inset: 16)
                    IRowLabel(label: "ученик") { Text(store.name(store.contact(l.contactId))) }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Th.fill6))
                Flow(spacing: 8) {
                    Btn(title: "Написать", icon: "chat", small: true) { close(store); store.openChat(l.conversationId) }
                    Btn(title: "Изменить", icon: "edit", kind: .outline, small: true) { store.sheet = .addLesson(editId: l.id) }
                    Btn(title: "На завтра", icon: "clock", kind: .outline, small: true) {
                        Task {
                            _ = await store.moveLesson(l, start: l.start.addingTimeInterval(86400), minutes: l.minutes, subject: store.subject(of: l)?.name ?? "")
                            close(store)
                        }
                    }
                    Btn(title: "Удалить", icon: "trash", kind: .outline, small: true, danger: true) { delAsk = true }
                }
                .padding(.top, 16)
            } else {
                Text("Занятие не найдено").font(Typo.body(14)).foregroundStyle(Th.muted)
            }
        }
        .confirmationDialog("Удалить занятие?", isPresented: $delAsk, titleVisibility: .visible) {
            if let l {
                Button(l.seriesId != nil ? "Только это" : "Удалить занятие", role: .destructive) { Task { await store.deleteLesson(l, following: false); close(store) } }
                if l.seriesId != nil {
                    Button("Это и следующие", role: .destructive) { Task { await store.deleteLesson(l, following: true); close(store) } }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Ученик не получит уведомление об отмене.") }
    }
}

struct AddLessonSheet: View {
    @Environment(Store.self) private var store
    let editId: String?
    @State private var query = ""
    @State private var picked: String?
    @State private var date = Date()
    @State private var time = "18:30"
    @State private var minutes = 60
    @State private var subject = ""
    @State private var weeks = 1
    @State private var busy = false
    private let times = ["09:00", "10:00", "12:00", "14:00", "16:00", "17:00", "18:30", "19:30"]

    var body: some View {
        SheetBody(title: editId == nil ? "Новое занятие" : "Изменить занятие") {
            Lbl("Ученик")
            if editId == nil { ContactPicker(query: $query, picked: $picked, onlyWithChat: true) }
            else { SheetField(icon: "user", placeholder: "", text: .constant(query)).disabled(true) }
            Lbl("День")
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden()
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Lbl("Время")
            Flow { ForEach(times, id: \.self) { t in FChip(title: t, on: time == t) { time = t } } }
            Lbl("Длительность")
            Flow { ForEach([30, 45, 60, 90], id: \.self) { m in FChip(title: "\(m) мин", on: minutes == m) { minutes = m } } }
            Lbl("Предмет")
            Flow { ForEach(store.subjects, id: \.self) { s in FChip(title: s.name, on: subject == s.name, dot: Color(css: s.color)) { subject = s.name } } }
            if editId == nil {
                Lbl("Повторять")
                Flow {
                    ForEach([1, 4, 8, 16], id: \.self) { w in
                        FChip(title: w == 1 ? "Не повторять" : "\(w) \(pl(w, "неделя", "недели", "недель"))", on: weeks == w) { weeks = w }
                    }
                }
            }
            Btn(title: "Сохранить", icon: "check", wide: true, busy: busy) { save() }.padding(.top, 18)
        }
        .onAppear {
            subject = store.subjects.first?.name ?? ""
            date = Store.monday(of: store.lessonsWeek) > Date() ? store.lessonsWeek : Date()
            if let id = editId, let l = store.lessons.first(where: { $0.id == id }) {
                picked = l.contactId
                query = store.name(store.contact(l.contactId))
                date = l.start
                time = Fmt.hm(l.start)
                minutes = l.minutes
                subject = store.subject(of: l)?.name ?? subject
            }
        }
    }

    private func save() {
        let hm = time.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, let start = Calendar.current.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: date) else { return }
        busy = true
        Task {
            defer { busy = false }
            if let id = editId, let l = store.lessons.first(where: { $0.id == id }) {
                if await store.moveLesson(l, start: start, minutes: minutes, subject: subject) { close(store) }
                return
            }
            guard let c = picked, let conv = store.mainConversation(of: c) else { store.show("Выберите ученика из списка", ok: false); return }
            if await store.addLesson(convId: conv.id, start: start, minutes: minutes, weeks: weeks, subject: subject) { close(store) }
        }
    }
}

// MARK: - чат: переслать, вложения, отложенная отправка

struct ForwardSheet: View {
    @Environment(Store.self) private var store
    let conv: String
    let mids: [String]

    var body: some View {
        SheetBody(title: "Переслать " + (mids.count > 1 ? "\(mids.count) \(pl(mids.count, "сообщение", "сообщения", "сообщений"))" : "сообщение")) {
            ForEach(store.sortChats(store.liveChats.filter { $0.id != conv })) { c in
                let ct = store.contact(c.contactId)
                Button {
                    close(store)
                    Task { await store.forward(conv, mids, to: c.id) }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: store.avatarName(ct), network: c.network, size: 36)
                        Text(store.name(ct)).font(Typo.body(15)).foregroundStyle(Th.fg)
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
            }
        }
    }
}

struct AttachSheet: View {
    @Environment(Store.self) private var store
    let conv: String

    var body: some View {
        SheetBody(title: "Вложения") {
            HStack(spacing: 8) {
                tile("image", "Галерея") { pick("photo") }
                tile("file", "Файл") { pick("file") }
                tile("card", "Оплата", primary: true) {
                    let cid = store.conversation(conv)?.contactId
                    store.sheet = .newPay(contactId: cid)
                }
                tile("bolt", "Шаблон") { pick("templates") }
            }
        }
    }

    private func pick(_ what: String) {
        close(store)
        NotificationCenter.default.post(name: .attachPick, object: conv, userInfo: ["what": what])
    }

    private func tile(_ icon: String, _ title: String, primary: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            VStack(spacing: 5) {
                Icon(name: icon)
                Text(title).font(Typo.body(12, .semibold))
            }
            .foregroundStyle(primary ? Th.onTeal : Th.fg)
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(primary ? Th.teal : Th.fill6))
        }
        .buttonStyle(PressStyle())
    }
}

struct SchedSendSheet: View {
    @Environment(Store.self) private var store
    let conv: String
    let text: String
    @State private var custom = false
    @State private var at = Date().addingTimeInterval(3600)

    var body: some View {
        SheetBody(title: "Отправить позже") {
            Text("«\(text)»").font(Typo.body(13.5)).foregroundStyle(Th.muted).lineLimit(2).padding(.bottom, 8)
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                Button { send(o.2) } label: {
                    HStack(spacing: 12) {
                        Icon(name: "clock", size: 16)
                        Text(o.0).font(Typo.body(15))
                        Spacer()
                        Text(o.1).font(Typo.body(13)).foregroundStyle(Th.muted)
                    }
                    .foregroundStyle(Th.fg)
                    .padding(.horizontal, 16).frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
            }
            Button { withAnimation { custom.toggle() } } label: {
                HStack(spacing: 12) {
                    Icon(name: "cal", size: 16)
                    Text("Выбрать дату и время").font(Typo.body(15))
                    Spacer()
                }
                .foregroundStyle(Th.fg)
                .padding(.horizontal, 16).frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowStyle())
            if custom {
                DatePicker("", selection: $at, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .tint(Th.teal)
                Btn(title: "Запланировать", icon: "clock", wide: true) { send(at) }
            }
        }
    }

    private var options: [(String, String, Date)] {
        let cal = Calendar.current
        var out: [(String, String, Date)] = []
        let now = Date()
        if let ev = cal.date(bySettingHour: 19, minute: 0, second: 0, of: now), ev > now.addingTimeInterval(1800) { out.append(("Сегодня вечером", "19:00", ev)) }
        if let tm = cal.date(byAdding: .day, value: 1, to: now), let t10 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: tm) { out.append(("Завтра утром", "10:00", t10)) }
        let monday = cal.date(byAdding: .day, value: 7, to: Store.monday(of: now)) ?? now
        if let m9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: monday) { out.append(("В понедельник", "09:00", m9)) }
        return out
    }

    private func send(_ d: Date) {
        close(store)
        Task { _ = await store.schedule(conv, text: text, at: d) }
    }
}

struct ScheduledListSheet: View {
    @Environment(Store.self) private var store
    let conv: String

    var body: some View {
        SheetBody(title: "Запланировано") {
            let items = (store.scheduled[conv] ?? []).sorted { $0.date < $1.date }
            if items.isEmpty { Text("Отложенных сообщений нет").font(Typo.body(14)).foregroundStyle(Th.muted).padding(.vertical, 20) }
            ForEach(items) { s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Icon(name: "clock", size: 13)
                        Text(Fmt.whenFull(s.date).prefix(1).uppercased() + Fmt.whenFull(s.date).dropFirst())
                        if s.status == "failed" { Text("· не отправлено").foregroundStyle(Th.danger) }
                    }
                    .font(Typo.body(12.5, .semibold)).foregroundStyle(Th.teal)
                    Text(s.text ?? "Вложение").font(Typo.body(15)).foregroundStyle(Th.fg)
                    if let e = s.error, !e.isEmpty { Text(e).font(Typo.body(12.5)).foregroundStyle(Th.danger) }
                    HStack(spacing: 8) {
                        Btn(title: "Отправить сейчас", kind: .tonal, small: true) { Task { await store.sendScheduledNow(s) } }
                        Btn(title: "Отменить", kind: .outline, small: true, danger: true) { Task { await store.cancelScheduled(s) } }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Th.fill6))
                .padding(.bottom, 8)
            }
        }
        .task { await store.loadScheduled(conv) }
    }
}

// MARK: - пароль

struct PasswordSheet: View {
    @Environment(Store.self) private var store
    @State private var step = 0
    @State private var code = ""
    @State private var pass = ""
    @State private var busy = false

    var body: some View {
        SheetBody(title: "Сменить пароль") {
            if step == 0 {
                Text("Пришлём код на \(store.user?.email ?? "почту для входа"). Затем введите его и новый пароль.")
                    .font(Typo.body(14)).foregroundStyle(Th.muted).multilineTextAlignment(.center)
                Btn(title: "Отправить код", icon: "mail", wide: true, busy: busy) {
                    busy = true
                    Task {
                        defer { busy = false }
                        if store.fixture { step = 1; return }
                        do { _ = try await API.send("POST", "/api/account/password/code/"); withAnimation { step = 1 } }
                        catch { store.show(friendly(error), ok: false) }
                    }
                }
                .padding(.top, 18)
            } else {
                Lbl("Код из письма")
                SheetField(icon: "mail", placeholder: "6 цифр", text: $code, keyboard: .numberPad)
                Lbl("Новый пароль")
                SheetField(icon: "lock", placeholder: "Не короче 8 символов", text: $pass, secure: true)
                Btn(title: "Сохранить пароль", icon: "check", wide: true, busy: busy) {
                    busy = true
                    Task {
                        defer { busy = false }
                        if store.fixture { store.show("Пароль изменён"); close(store); return }
                        do {
                            _ = try await API.send("POST", "/api/account/password/", json: ["code": code.filter(\.isNumber), "password": pass])
                            store.show("Пароль изменён")
                            close(store)
                        } catch { store.show(friendly(error), ok: false) }
                    }
                }
                .padding(.top, 18)
            }
        }
    }
}
