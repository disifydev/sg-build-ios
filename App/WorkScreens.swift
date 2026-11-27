import SwiftUI

// Экраны «Работа» в стиле приложения: расписание, классы и предметы, сотрудники; карточка найденной оплаты.

/// Найденная ИИ оплата: «Записать» / «Не оплата», дубль чека помечен.
struct FindingCard: View {
    @Environment(Store.self) private var store
    let f: PaymentFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowIcon(system: "sparkle", color: Pal.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Найдена оплата: " + Fmt.money(f.amount ?? 0, currency: f.currency ?? store.state.workspace?.currency))
                        .font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
                    Text([f.payer ?? store.contact(f.contactId).map { store.name($0) }, f.source == "receipt" ? "чек" : "из переписки", f.purpose]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(2)
                }
            }
            if f.duplicateOf != nil {
                Text("Похоже на повтор уже записанного чека").font(Typo.body(12.5)).foregroundStyle(Pal.danger)
            }
            HStack(spacing: 8) {
                Button { Task { await store.acceptFinding(f, true) } } label: {
                    Text("Записать").font(Typo.body(14, .semibold)).padding(.horizontal, 16).frame(height: 36).primaryFill(18)
                }
                .buttonStyle(PressStyle())
                PillButton(action: { Task { await store.acceptFinding(f, false) } }) { Text("Не оплата").font(Typo.body(14, .medium)) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(22)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: - расписание

struct ScheduleView: View {
    @Environment(Store.self) private var store
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addOpen = false
    @State private var lessonOpen: Lesson?

    var body: some View {
        let list = store.lessons(on: day)
        VStack(spacing: 0) {
            TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: {
                CircleButton(system: "plus", iconSize: 18) { addOpen = true }
            })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Расписание").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4).padding(.top, 14)
                    weekStrip.padding(.top, 14)
                    HStack {
                        Text(dayTitle(day)).font(Typo.display(17)).foregroundStyle(Pal.fg)
                        Spacer()
                        Text(ruCount(list.count, "занятие", "занятия", "занятий")).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 10)
                    if let e = store.lessonsError, list.isEmpty {
                        EmptyNote(text: e)
                    } else if list.isEmpty {
                        VStack(spacing: 10) {
                            Text("Свободный день").font(Typo.display(17)).foregroundStyle(Pal.fg)
                            Text("Занятий нет. Нажми «+», чтобы добавить").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28).glassRect(24)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(list) { l in lessonRow(l) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: day)
            }
            .refreshable { await store.loadLessons() }
        }
        .screenBackground(store.wall)
        .task { await store.loadLessons(week: day) }
        .onChange(of: day) { _, d in
            if Store.monday(of: d) != store.lessonsWeek { Task { await store.loadLessons(week: d) } }
        }
        .sheet(isPresented: $addOpen) { LessonEditSheet(lesson: nil, day: day) }
        .sheet(item: $lessonOpen) { l in LessonSheet(lesson: l) }
    }

    private var weekStrip: some View {
        let monday = Store.monday(of: day)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: monday) ?? monday
                let on = Calendar.current.isDate(d, inSameDayAs: day)
                let has = !store.lessons(on: d).isEmpty
                let today = Calendar.current.isDateInToday(d)
                Button {
                    haptic()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { day = d }
                } label: {
                    VStack(spacing: 3) {
                        Text(Fmt.weekdays[Calendar.current.component(.weekday, from: d) - 1]).font(Typo.body(11, .medium))
                        Text("\(Calendar.current.component(.day, from: d))").font(Typo.body(17, .semibold)).monospacedDigit()
                        Circle().frame(width: 4, height: 4).opacity(has ? 0.7 : 0)
                    }
                    .foregroundStyle(on ? Pal.onAcc : (today ? Pal.acc : Pal.fg))
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Pal.acc : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(6)
        .glassRect(22)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                day = Calendar.current.date(byAdding: .day, value: v.translation.width < 0 ? 7 : -7, to: day) ?? day
            }
        })
        .accessibilityHint("Смахни влево или вправо, чтобы сменить неделю")
    }

    private func lessonRow(_ l: Lesson) -> some View {
        let s = store.subject(of: l)
        return Button { lessonOpen = l } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Fmt.hm(l.start)).font(Typo.body(16, .bold)).monospacedDigit().foregroundStyle(Pal.fg)
                    Text("\(l.minutes) мин").font(Typo.body(12)).foregroundStyle(Pal.fg2)
                }
                .frame(width: 54, alignment: .leading)
                Capsule().fill(Color(css: s?.color ?? "#9CC3D3")).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s?.name ?? "Занятие").font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
                    Text(store.name(store.contact(l.contactId))).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                Spacer(minLength: 0)
                if l.seriesId != nil { Image(systemName: "repeat").font(.system(size: 12)).foregroundStyle(Pal.fg3) }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .glassRect(20)
    }

    private func dayTitle(_ d: Date) -> String {
        let names = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
        let wd = names[Calendar.current.component(.weekday, from: d) - 1]
        if Calendar.current.isDateInToday(d) { return "Сегодня, " + wd }
        return wd.prefix(1).uppercased() + wd.dropFirst() + ", " + Fmt.dayLong(d)
    }
}

/// Занятие: написать, изменить, перенести на завтра, отменить, удалить; для серии — «только это / это и следующие».
struct LessonSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson
    @State private var edit = false
    @State private var ask: String?   // "cancel" / "delete"

    var body: some View {
        let s = store.subject(of: lesson)
        SheetBox(title: s?.name ?? "Занятие", subtitle: store.name(store.contact(lesson.contactId)) + " · " + Fmt.whenFull(lesson.start) + " · \(lesson.minutes) мин") {
            SheetOption(icon: "bubble.left", title: "Написать ученику", action: {
                dismiss()
                store.open(.chat(lesson.conversationId))
            })
            SheetOption(icon: "pencil", title: "Изменить время и предмет", action: { edit = true })
            SheetOption(icon: "arrow.right.circle", title: "Перенести на завтра", subtitle: Fmt.whenFull(lesson.start.addingTimeInterval(86400)), action: {
                dismiss()
                Task { _ = await store.moveLesson(lesson, start: lesson.start.addingTimeInterval(86400), minutes: lesson.minutes, subject: s?.name ?? "") }
            })
            SheetOption(icon: "xmark.circle", iconColor: Pal.apricot, title: "Отменить занятие", subtitle: "останется в истории отменённым", action: { ask = "cancel" })
            SheetOption(icon: "trash", iconColor: Pal.danger, title: "Удалить", color: Pal.danger, action: { ask = "delete" })
        }
        .sheet(isPresented: $edit) { LessonEditSheet(lesson: lesson, day: lesson.start) }
        .confirmationDialog(ask == "cancel" ? "Отменить занятие?" : "Удалить занятие?", isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }), titleVisibility: .visible) {
            let cancel = ask == "cancel"
            Button(lesson.seriesId != nil ? "Только это" : (cancel ? "Отменить" : "Удалить"), role: .destructive) { run(cancel: cancel, following: false) }
            if lesson.seriesId != nil {
                Button("Это и следующие", role: .destructive) { run(cancel: cancel, following: true) }
            }
            Button("Назад", role: .cancel) {}
        } message: { Text("Ученик не получит уведомление.") }
    }

    private func run(cancel: Bool, following: Bool) {
        dismiss()
        Task { await store.dropLesson(lesson, cancel: cancel, following: following) }
    }
}

/// Новое занятие или правка: ученик, день, время, длительность, предмет, повтор по дням недели.
struct LessonEditSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson?
    let day: Date
    @State private var query = ""
    @State private var picked: String?
    @State private var date = Date()
    @State private var time = Date()
    @State private var minutes = 60
    @State private var subject = ""
    @State private var weeks = 1
    @State private var weekdays: Set<Int> = []
    @State private var busy = false

    var body: some View {
        SheetBox(title: lesson == nil ? "Новое занятие" : "Изменить занятие") {
            label("Ученик")
            if lesson == nil {
                field("Имя ученика", text: $query)
                let q = query.trimmingCharacters(in: .whitespaces).lowercased()
                if picked == nil && !q.isEmpty {
                    let list = store.state.contacts.filter { c in store.name(c).lowercased().contains(q) && store.mainConversation(of: c.id) != nil }.prefix(5)
                    ForEach(Array(list)) { c in
                        SheetOption(icon: "person.crop.circle", title: store.name(c), action: { picked = c.id; query = store.name(c) })
                    }
                }
            } else {
                Text(store.name(store.contact(lesson?.contactId))).font(Typo.body(16, .medium)).foregroundStyle(Pal.fg).padding(.horizontal, 12)
            }
            label("Когда")
            HStack {
                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                Spacer()
            }
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .tint(Pal.acc)
            .padding(.horizontal, 8)
            label("Длительность")
            FlowLayout(spacing: 8) {
                ForEach([30, 45, 60, 90, 120], id: \.self) { m in
                    Chip(text: "\(m) мин", on: minutes == m, height: 32, fontSize: 13) { minutes = m }
                }
            }
            .padding(.horizontal, 4)
            label("Предмет")
            FlowLayout(spacing: 8) {
                ForEach(store.subjects, id: \.self) { s in
                    Chip(text: s.name, dot: Color(css: s.color), on: subject == s.name, height: 32, fontSize: 13) { subject = s.name }
                }
            }
            .padding(.horizontal, 4)
            if lesson == nil {
                label("Повторять")
                FlowLayout(spacing: 8) {
                    ForEach([1, 4, 8, 16], id: \.self) { w in
                        Chip(text: w == 1 ? "Не повторять" : ruCount(w, "неделя", "недели", "недель"), on: weeks == w, height: 32, fontSize: 13) { weeks = w }
                    }
                }
                .padding(.horizontal, 4)
                if weeks > 1 {
                    HStack(spacing: 6) {
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in
                            let on = weekdays.contains(d)
                            Button {
                                haptic()
                                if on { weekdays.remove(d) } else { weekdays.insert(d) }
                            } label: {
                                Text(Fmt.weekdays[d]).font(Typo.body(13, .semibold))
                                    .foregroundStyle(on ? Pal.onAcc : Pal.fg)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(on ? Pal.acc : Pal.fill))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.horizontal, 4).padding(.top, 6)
                    Text(weekdays.isEmpty ? "Без выбора — в тот же день недели" : "По выбранным дням")
                        .font(Typo.body(12)).foregroundStyle(Pal.fg3).padding(.horizontal, 8)
                }
            }
            Button { save() } label: {
                ZStack {
                    if busy { ProgressView().tint(Pal.onAcc) } else { Text("Сохранить").font(Typo.body(16, .semibold)) }
                }
                .frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .padding(.top, 14)
        }
        .onAppear {
            subject = store.subjects.first?.name ?? ""
            date = day
            time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
            if let l = lesson {
                picked = l.contactId
                date = l.start
                time = l.start
                minutes = l.minutes
                subject = store.subject(of: l)?.name ?? subject
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Typo.body(13, .medium)).foregroundStyle(Pal.fg2).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Pal.fg3))
            .font(Typo.body(15)).foregroundStyle(Pal.fg)
            .padding(.horizontal, 14).frame(height: 46)
            .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 4)
            .onChange(of: text.wrappedValue) { _, v in if let p = picked, store.name(store.contact(p)) != v { picked = nil } }
    }

    private func save() {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        guard let start = cal.date(bySettingHour: hm.hour ?? 18, minute: hm.minute ?? 0, second: 0, of: date) else { return }
        busy = true
        Task {
            defer { busy = false }
            if let l = lesson {
                if await store.moveLesson(l, start: start, minutes: minutes, subject: subject) { dismiss() }
                return
            }
            guard let c = picked, let conv = store.mainConversation(of: c) else { store.show("Выбери ученика из списка", ok: false); return }
            if await store.addLesson(convId: conv.id, start: start, minutes: minutes, weeks: weeks, weekdays: Array(weekdays).sorted(), subject: subject) { dismiss() }
        }
    }
}

// MARK: - классы, группы, предметы

struct ListsView: View {
    @Environment(Store.self) private var store
    @State private var edit: EditItem?
    @State private var delAsk: EditItem?

    struct EditItem: Identifiable {
        let kind: String     // class / group / subject
        let old: String?
        var id: String { kind + "|" + (old ?? "+") }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { Color.clear.frame(width: 44, height: 44) })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Классы и группы").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4).padding(.top, 14)
                    Text("Классы и группы — для фильтра учеников в чатах и списке клиентов. Назначаются в карточке клиента. Предметы — для расписания.")
                        .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.horizontal, 4).padding(.top, 8)
                    section("Классы", kind: "class", items: store.classes, add: "Новый класс")
                    section("Группы", kind: "group", items: store.groups, add: nil)
                    Cap("Предметы")
                    VStack(spacing: 0) {
                        ForEach(Array(store.subjects.enumerated()), id: \.offset) { i, s in
                            Button { edit = EditItem(kind: "subject", old: s.name) } label: {
                                GroupRow(first: i == 0) {
                                    Circle().fill(Color(css: s.color)).frame(width: 14, height: 14).padding(.horizontal, 8)
                                    Text(s.name).foregroundStyle(Pal.fg)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        Button { edit = EditItem(kind: "subject", old: nil) } label: {
                            GroupRow(first: store.subjects.isEmpty) {
                                Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                                Text("Новый предмет").font(Typo.body(16, .semibold))
                                Spacer()
                            }
                            .foregroundStyle(Pal.acc).contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .glassRect(24)
                    Text("Предметы хранятся на этом телефоне.").font(Typo.body(13)).foregroundStyle(Pal.fg3).padding(.horizontal, 16).padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
        .sheet(item: $edit) { e in ListItemSheet(item: e) }
    }

    private func section(_ title: String, kind: String, items: [String], add: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Cap(title)
            VStack(spacing: 0) {
                if items.isEmpty && add == nil {
                    GroupRow(first: true) { Text("Пока нет — группу ставят в карточке клиента").font(Typo.body(14)).foregroundStyle(Pal.fg2); Spacer() }
                }
                ForEach(Array(items.enumerated()), id: \.element) { i, k in
                    let n = store.members(kind, k)
                    Button { edit = EditItem(kind: kind, old: k) } label: {
                        GroupRow(first: i == 0) {
                            RowIcon(system: kind == "class" ? "graduationcap" : "person.3", color: kind == "class" ? Pal.sky : Pal.lav)
                            Text(kind == "class" ? classTitle(k) : k).foregroundStyle(Pal.fg)
                            Spacer()
                            Text(ruCount(n, "ученик", "ученика", "учеников")).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                if let add {
                    Button { edit = EditItem(kind: kind, old: nil) } label: {
                        GroupRow(first: items.isEmpty) {
                            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                            Text(add).font(Typo.body(16, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Pal.acc).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .glassRect(24)
        }
    }
}

/// Класс, группа или предмет: название (и цвет у предмета), удалить.
struct ListItemSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: ListsView.EditItem
    @State private var name = ""
    @State private var color = "#86C7A6"
    @State private var delAsk = false

    var body: some View {
        let title: String = item.kind == "class" ? (item.old == nil ? "Новый класс" : "Класс") : (item.kind == "group" ? "Группа" : (item.old == nil ? "Новый предмет" : "Предмет"))
        SheetBox(title: title) {
            TextField("", text: $name, prompt: Text(item.kind == "class" ? "Например, 8 или 8 класс" : "Название").foregroundColor(Pal.fg3))
                .font(Typo.body(16)).foregroundStyle(Pal.fg)
                .padding(.horizontal, 14).frame(height: 46)
                .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 4)
            if item.kind == "subject" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Pal.folderHex, id: \.self) { c in
                        Button { haptic(); color = c } label: {
                            Circle().fill(Color(css: c))
                                .overlay(Circle().stroke(color == c ? Pal.fg : .clear, lineWidth: 3).padding(-4))
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            Button { save() } label: {
                Text(item.old == nil ? "Добавить" : "Сохранить").font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
            }
            .buttonStyle(PressStyle())
            .padding(.top, 10)
            if item.old != nil {
                SheetOption(icon: "trash", iconColor: Pal.danger, title: "Удалить", color: Pal.danger, action: { delAsk = true })
            }
        }
        .onAppear {
            name = item.old.map { item.kind == "class" ? classTitle($0) : $0 } ?? ""
            if item.kind == "subject", let s = store.subjects.first(where: { $0.name == item.old }) { color = s.color }
        }
        .confirmationDialog("Удалить «\(name)»?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { remove() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(item.kind == "subject" ? "Занятия по этому предмету останутся в расписании." : "У учеников эта метка снимется.")
        }
    }

    private func clean(_ s: String) -> String {
        var n = s.trimmingCharacters(in: .whitespaces)
        if item.kind == "class", n.hasSuffix(" класс"), Int(n.dropLast(6)) != nil { n = String(n.dropLast(6)) }
        return n
    }

    private func save() {
        let n = clean(name)
        guard !n.isEmpty else { store.show("Впиши название", ok: false); return }
        dismiss()
        switch item.kind {
        case "subject":
            if let old = item.old, let i = store.subjects.firstIndex(where: { $0.name == old }) {
                store.subjects[i] = SubjectItem(name: n, color: color)
                for (k, v) in store.lessonSubject where v == old { store.lessonSubject[k] = n }
            } else {
                store.subjects.append(SubjectItem(name: n, color: color))
            }
            store.saveSubjects()
            store.show(item.old == nil ? "Предмет добавлен" : "Сохранено")
        default:
            if let old = item.old { Task { await store.renameCollection(item.kind, from: old, to: n) } } else { store.addClass(n) }
        }
    }

    private func remove() {
        dismiss()
        guard let old = item.old else { return }
        if item.kind == "subject" {
            store.subjects.removeAll { $0.name == old }
            store.saveSubjects()
            store.show("Удалено")
        } else {
            Task { await store.deleteCollection(item.kind, old) }
        }
    }
}

// MARK: - сотрудники

struct StaffView: View {
    @Environment(Store.self) private var store
    @State private var invite = false
    @State private var role: TeamMember?

    var body: some View {
        let owner = store.user?.isOwner == true
        VStack(spacing: 0) {
            TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: {
                if owner { CircleButton(system: "person.badge.plus", iconSize: 17) { invite = true } } else { Color.clear.frame(width: 44, height: 44) }
            })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Сотрудники").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4).padding(.top, 14)
                    Text("Сотрудники видят чаты кабинета. Роль определяет, что им можно менять.")
                        .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.horizontal, 4).padding(.top, 8)
                    Cap("Команда")
                    VStack(spacing: 0) {
                        ForEach(Array(store.state.team.enumerated()), id: \.element.id) { i, m in
                            let me = m.id == store.user?.id
                            Button { if owner && m.role != "owner" { role = m } } label: {
                                GroupRow(first: i == 0) {
                                    Avatar(name: m.name, hue: Double(stableHash(m.name)), size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.name + (me ? " (вы)" : "")).foregroundStyle(Pal.fg)
                                        Text(m.role == "owner" ? "полный доступ" : (m.email ?? "")).font(Typo.body(12)).foregroundStyle(Pal.fg3).lineLimit(1)
                                    }
                                    .padding(.vertical, 6)
                                    Spacer()
                                    Text(m.roleTitle).font(Typo.body(12, .semibold)).foregroundStyle(Pal.acc)
                                        .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Pal.acc.opacity(0.12)))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        if owner {
                            Button { invite = true } label: {
                                GroupRow(first: store.state.team.isEmpty) {
                                    Image(systemName: "person.badge.plus").font(.system(size: 17, weight: .semibold))
                                    Text("Пригласить сотрудника").font(Typo.body(16, .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Pal.acc).contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)
                    if !owner {
                        Text("Сотрудников приглашает владелец кабинета.").font(Typo.body(13)).foregroundStyle(Pal.fg3).padding(.horizontal, 16).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
        .sheet(isPresented: $invite) { InviteSheet() }
        .sheet(item: $role) { m in RoleSheet(member: m) }
    }
}

private let roleList: [(String, String)] = [("Администратор", "всё, кроме удаления кабинета"), ("Менеджер", "чаты, клиенты и оплаты"), ("Только просмотр", "свои клиенты, без оплат")]

struct RoleSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: TeamMember
    @State private var delAsk = false

    var body: some View {
        SheetBox(title: member.name, subtitle: "Роль сотрудника") {
            ForEach(roleList.indices, id: \.self) { i in
                let r = roleList[i]
                SheetOption(icon: member.roleTitle == r.0 ? "checkmark.circle.fill" : "circle", iconColor: Pal.acc, title: r.0, subtitle: r.1, on: member.roleTitle == r.0, action: {
                    dismiss()
                    Task { await store.setRole(member.id, r.0) }
                })
            }
            SheetOption(icon: "person.badge.minus", iconColor: Pal.danger, title: "Убрать из кабинета", color: Pal.danger, action: { delAsk = true })
        }
        .confirmationDialog("Убрать \(member.name) из кабинета?", isPresented: $delAsk, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) { dismiss(); Task { await store.removeMember(member.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Сотрудник потеряет доступ к чатам.") }
    }
}

/// Приглашение в два шага: имя, почта и пароль → код из письма сотруднику.
struct InviteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var role = "Менеджер"
    @State private var step = 0
    @State private var busy = false

    var body: some View {
        SheetBox(title: step == 0 ? "Пригласить сотрудника" : "Код из письма", subtitle: step == 0 ? nil : "Мы отправили код на \(email). Попроси сотрудника его продиктовать.") {
            if step == 0 {
                input("Имя и фамилия", $name)
                input("Почта сотрудника", $email, keyboard: .emailAddress)
                input("Пароль для входа (от 8 символов)", $password, secure: true)
                ForEach(roleList.indices, id: \.self) { i in
                    let r = roleList[i]
                    SheetOption(icon: role == r.0 ? "checkmark.circle.fill" : "circle", iconColor: Pal.acc, title: r.0, subtitle: r.1, on: role == r.0, action: { role = r.0 })
                }
                button("Отправить приглашение") { invite() }
            } else {
                input("6 цифр", $code, keyboard: .numberPad)
                button("Подтвердить") { confirm() }
            }
        }
    }

    private func input(_ p: String, _ t: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField("", text: t, prompt: Text(p).foregroundColor(Pal.fg3)) }
            else { TextField("", text: t, prompt: Text(p).foregroundColor(Pal.fg3)).keyboardType(keyboard).textInputAutocapitalization(keyboard == .default ? .words : .never).autocorrectionDisabled() }
        }
        .font(Typo.body(15)).foregroundStyle(Pal.fg)
        .padding(.horizontal, 14).frame(height: 46)
        .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(.horizontal, 4).padding(.bottom, 6)
    }

    private func button(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack { if busy { ProgressView().tint(Pal.onAcc) } else { Text(t).font(Typo.body(16, .semibold)) } }
                .frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .padding(.top, 8)
    }

    private func invite() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, e.contains("@") else { store.show("Впиши имя и почту", ok: false); return }
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
            if store.fixture { store.show("\(name) теперь в кабинете"); dismiss(); return }
            if await store.stateCall("POST", "/api/team/", ["email": e, "code": code.filter(\.isNumber)], ok: "\(name) теперь в кабинете") {
                if role != "Менеджер", let m = store.state.team.first(where: { $0.email?.lowercased() == e }) { await store.setRole(m.id, role) }
                dismiss()
            }
        }
    }
}
