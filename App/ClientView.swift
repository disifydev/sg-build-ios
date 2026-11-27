import SwiftUI

struct ClientView: View {
    @Environment(Store.self) private var store
    let contactId: String
    @State private var sheet: ClientSheet?
    @State private var amountText = ""
    @State private var note = ""
    @State private var noteLoaded = false
    @State private var confirmDeal: DealRemoval?

    struct DealRemoval: Identifiable {
        let deal: Deal
        let ok: String
        var id: String { deal.id }
    }
    @FocusState private var focus: Field?
    enum Field { case amount, note }

    @State private var newCollection: String?   // "class" / "group" — поле ввода нового класса или группы
    @State private var collectionName = ""
    @State private var blockAsk = false

    enum ClientSheet: String, Identifiable {
        case write, call, remind, folder, label
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let c = store.contact(contactId) {
                content(c)
            } else {
                VStack {
                    TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { EmptyView() })
                    EmptyNote(text: "Клиент не найден")
                    Spacer()
                }
            }
        }
        .screenBackground(store.wall)
        .sheet(item: $sheet) { s in
            switch s {
            case .write: WriteSheet(contactId: contactId)
            case .call: CallSheet(contactId: contactId)
            case .remind: ReminderSheet(contactId: contactId)
            case .folder: FolderSheet(contactId: contactId)
            case .label: LabelSheet(contactId: contactId)
            }
        }
        .confirmationDialog("Удалить запись о сумме \(Fmt.money(confirmDeal?.deal.amount ?? 0, currency: store.state.workspace?.currency))?",
                            isPresented: Binding(get: { confirmDeal != nil }, set: { if !$0 { confirmDeal = nil } }), titleVisibility: .visible) {
            if let r = confirmDeal {
                Button("Удалить", role: .destructive) {
                    confirmDeal = nil
                    Task { await store.act(["type": "removeDeal", "id": r.deal.id], ok: r.ok) }
                }
            }
            Button("Отмена", role: .cancel) { confirmDeal = nil }
        } message: {
            Text("Сумма пропадёт из сводки и истории клиента.")
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveNote)
        .confirmationDialog("Заблокировать клиента?", isPresented: $blockAsk, titleVisibility: .visible) {
            Button("Заблокировать", role: .destructive) { Task { await store.block(contactId, true) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сообщения от него перестанут считаться непрочитанными. В Telegram и WhatsApp по QR блокировка ставится и в самом мессенджере.")
        }
    }

    private func addChip(_ kind: String, _ title: String) -> some View {
        Button {
            withAnimation { newCollection = newCollection == kind ? nil : kind; collectionName = "" }
        } label: {
            Text(title).font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                .padding(.horizontal, 14).frame(height: 32)
                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Pal.fg.opacity(0.4)))
        }
        .buttonStyle(PressStyle())
    }

    private func addCollection(_ c: Contact, _ kind: String) {
        var n = collectionName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if kind == "class", n.hasSuffix(" класс"), Int(n.dropLast(6)) != nil { n = String(n.dropLast(6)) }
        if kind == "class" { store.setClass(c.id, n) } else { store.setCollection(c.id, kind: "group", name: n, on: true) }
        withAnimation { newCollection = nil; collectionName = "" }
    }

    /// Профиль клиента от ИИ: кто пишет, класс, занятия, сводка; неуверенные догадки — «проверьте».
    @ViewBuilder private func aiBlock(_ c: Contact) -> some View {
        if let p = store.aiProfiles[c.id] {
            let rows: [(String, AIField?)] = [("Кто пишет", p.role), ("Класс", p.grade), ("Занятия", p.lessonType), ("Группа", p.groupName)]
            let shown = rows.filter { !($0.1?.value ?? "").isEmpty }
            if !shown.isEmpty || !(p.summary ?? "").isEmpty {
                Cap("Профиль от ИИ")
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
                        GroupRow(first: i == 0) {
                            Text(r.0).foregroundStyle(Pal.fg2)
                            Spacer()
                            Text(aiValue(r.0, r.1?.value ?? "")).foregroundStyle(Pal.fg).lineLimit(1)
                            if (r.1?.confidence ?? 1) < 0.6 && r.1?.manual != true {
                                Text("проверьте").font(Typo.body(11, .semibold)).foregroundStyle(Pal.ink)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Pal.apricot))
                            }
                        }
                    }
                    if let sum = p.summary, !sum.isEmpty {
                        GroupRow(first: shown.isEmpty) {
                            Text(sum).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineSpacing(2).padding(.vertical, 10)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .glassRect(24)
            }
        }
    }

    private func aiValue(_ key: String, _ v: String) -> String {
        switch (key, v) {
        case ("Кто пишет", "parent"): return "Родитель"
        case ("Кто пишет", "student"): return "Ученик"
        case ("Занятия", "individual"): return "Индивидуальные"
        case ("Занятия", "group"): return "В группе"
        case ("Класс", _): return classTitle(v)
        default: return v
        }
    }

    /// Найденные ИИ оплаты этого клиента: «Записать» / «Не оплата».
    @ViewBuilder private func findingsBlock(_ c: Contact) -> some View {
        let mine = store.findings.filter { $0.contactId == c.id }
        if !mine.isEmpty {
            Cap("Найдена оплата")
            VStack(spacing: 8) {
                ForEach(mine) { f in FindingCard(f: f) }
            }
        }
    }

    /// «Похоже, это тот же человек» — объединить карточки.
    @ViewBuilder private func mergeBlock(_ c: Contact) -> some View {
        if let s = store.suggestions.first(where: { $0.aId == c.id || $0.bId == c.id }) {
            let other: String = s.aId == c.id ? s.bId : s.aId
            let oc = store.contact(other)
            let otherName: String = oc.map { store.name($0) + " · " + NetInfo.of($0.source).name } ?? ((s.aId == c.id ? s.bName : s.aName) ?? "другая карточка")
            VStack(alignment: .leading, spacing: 8) {
                Text("Похоже, это тот же человек: \(otherName)").font(Typo.body(14, .medium)).foregroundStyle(Pal.fg)
                if let r = s.reason { Text(r).font(Typo.body(13)).foregroundStyle(Pal.fg2) }
                HStack(spacing: 8) {
                    PillButton(action: { Task { await store.merge(keep: c.id, drop: other, yes: true) } }) { Text("Объединить").font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc) }
                    PillButton(action: { Task { await store.merge(keep: c.id, drop: other, yes: false) } }) { Text("Это разные люди").font(Typo.body(13, .medium)) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Pal.fg.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .padding(.top, 14)
        }
    }

    private func load() {
        guard !noteLoaded, let c = store.contact(contactId) else { return }
        note = c.note ?? ""
        if let d = store.dealDraft[contactId] {
            amountText = "\(d)"
        } else if let promised = store.deals(of: contactId).last(where: { $0.status == "promised" }), promised.amount > 0 {
            amountText = "\(Int(promised.amount))"
        }
        noteLoaded = true
    }

    private func saveNote() {
        guard noteLoaded, let c = store.contact(contactId), note != (c.note ?? "") else { return }
        let n = note
        Task { await store.act(["type": "setNote", "contactId": contactId, "note": n], ok: "Заметка сохранена") }
    }

    private var amount: Int { Int(amountText.filter(\.isNumber)) ?? 0 }

    private func content(_ c: Contact) -> some View {
        let convs = store.conversations(of: c.id)
        let msgs = convs.flatMap { store.messages($0.id) }.sorted { $0.date < $1.date }
        let ins = msgs.filter { !$0.isOut }.count
        let outs = msgs.count - ins
        var resp: [TimeInterval] = []
        for i in msgs.indices.dropFirst() where msgs[i].isOut && !msgs[i - 1].isOut {
            resp.append(msgs[i].date.timeIntervalSince(msgs[i - 1].date))
        }
        let avg = resp.isEmpty ? nil : resp.reduce(0, +) / Double(resp.count)
        let days = max(1, Int((Date().timeIntervalSince(c.first) / 86400).rounded()))
        let firstOut = msgs.first(where: { $0.isOut })
        let firstIn = msgs.first(where: { !$0.isOut })
        let whoFirst = (firstOut != nil && (firstIn == nil || firstOut!.date < firstIn!.date)) ? "мы" : "клиент"
        let deals = store.deals(of: c.id)
        let paid = deals.filter { $0.status == "paid" }.reduce(0) { $0 + $1.amount }
        let net = NetInfo.of(convs.first?.network ?? c.source)
        let f = store.folder(c.folderId)
        let rem = store.reminder(for: c.id)
        let cur = store.state.workspace?.currency
        let older = convs.reduce(0) { $0 + ($1.older ?? 0) }

        return VStack(spacing: 0) {
            TopBar(back: { saveNote(); store.pop() }, center: {
                Text("карточка клиента").font(Typo.body(12)).foregroundStyle(Pal.fg3)
            }, trailing: { Color.clear.frame(width: 44, height: 44) })
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Avatar(name: c.name, hue: c.displayHue, url: c.avatar, size: 92)
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 14)
                        Text(store.name(c)).font(Typo.display(23)).tracking(-0.7).foregroundStyle(Pal.fg).multilineTextAlignment(.center).padding(.top, 10)
                        Text(joinHandle(net.name, c.handle) + " · с " + Fmt.dayLong(c.first))
                            .font(Typo.body(14)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.top, 4)

                    HStack(spacing: 8) {
                        action("bubble.left", "Написать") { sheet = .write }
                        action("phone", "Позвонить") { sheet = .call }
                        action("bell", "Напомнить") { sheet = .remind }
                        action("creditcard", "Оплатил") { markPaid(c) }
                    }
                    .padding(.top, 18)

                    Cap("Класс и группа")
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 8) {
                            ForEach(store.classes, id: \.self) { k in
                                let on = c.classes.contains(k)
                                Chip(text: classTitle(k), on: on, height: 32, fontSize: 13) { store.setClass(c.id, on ? nil : k) }
                            }
                            addChip("class", "+ Класс")
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(store.groups, id: \.self) { g in
                                let on = c.groups.contains(g)
                                Chip(text: g, dot: Pal.lav, on: on, height: 32, fontSize: 13) { store.setCollection(c.id, kind: "group", name: g, on: !on) }
                            }
                            addChip("group", "+ Группа")
                        }
                        if let kind = newCollection {
                            HStack(spacing: 8) {
                                TextField("", text: $collectionName, prompt: Text(kind == "class" ? "Например, 9 или 9 класс" : "Например, Мини-группа ЕГЭ").foregroundColor(Pal.fg3))
                                    .font(Typo.body(15)).foregroundStyle(Pal.fg)
                                    .submitLabel(.done)
                                    .onSubmit { addCollection(c, kind) }
                                Button { addCollection(c, kind) } label: {
                                    Text("Добавить").font(Typo.body(14, .semibold)).padding(.horizontal, 14).frame(height: 34).primaryFill(17)
                                }
                                .buttonStyle(PressStyle())
                            }
                            .padding(.horizontal, 12).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.fill))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: newCollection)

                    Cap("Статистика")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        Tile(label: "сообщений", value: "\(msgs.count + older)")
                        Tile(label: "от клиента", value: "\(ins)")
                        Tile(label: "от нас", value: "\(outs)")
                        Tile(label: "ответ", value: Fmt.duration(avg), valueSize: 19)
                        Tile(label: "в работе", value: "\(days) дн", valueSize: 19)
                        Tile(label: "оплачено", value: paid > 0 ? Fmt.money(paid, currency: cur) : "—", valueSize: 17, valueColor: Pal.mint)
                    }
                    VStack(spacing: 0) {
                        GroupRow(first: true) { Text("Первым написал(а)").foregroundStyle(Pal.fg2); Spacer(); Text(whoFirst).foregroundStyle(Pal.fg) }
                        GroupRow { Text("Последнее сообщение").foregroundStyle(Pal.fg2); Spacer(); Text(msgs.last.map { Fmt.when($0.date) } ?? "—").foregroundStyle(Pal.fg) }
                        GroupRow { Text("Откуда").foregroundStyle(Pal.fg2); Spacer(); Text(net.name).foregroundStyle(Pal.fg) }
                        if older > 0 {
                            GroupRow { Text("Цифры по последним \(msgs.count) сообщениям").font(Typo.body(13)).foregroundStyle(Pal.fg3); Spacer() }
                        }
                    }
                    .glassRect(24)
                    .padding(.top, 8)

                    Cap("Сделка")
                    VStack(spacing: 0) {
                        Button { sheet = .folder } label: {
                            GroupRow(first: true) {
                                Text("Папка").foregroundStyle(Pal.fg2)
                                Spacer()
                                Circle().fill(Color(css: f?.color)).frame(width: 9, height: 9)
                                Text(f?.name ?? "Без папки").font(Typo.body(16, .medium)).foregroundStyle(Pal.fg)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        GroupRow {
                            Text("Сумма").foregroundStyle(Pal.fg2)
                            Spacer()
                            TextField("", text: $amountText, prompt: Text("0").foregroundColor(Pal.fg3))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(Typo.display(16))
                                .foregroundStyle(Pal.fg)
                                .frame(width: 130)
                                .focused($focus, equals: .amount)
                                .onChange(of: amountText) { _, v in
                                    let n = Int(v.filter(\.isNumber)) ?? 0
                                    store.dealDraft[contactId] = n > 0 ? n : nil
                                }
                            Text(Fmt.symbol(cur)).foregroundStyle(Pal.fg)
                        }
                        Button { promise(c) } label: {
                            GroupRow {
                                Image(systemName: "clock").font(.system(size: 16))
                                Text("Обещал(а) оплатить завтра").font(Typo.body(16, .semibold))
                                Spacer()
                            }
                            .foregroundStyle(Pal.apricot)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        ForEach(deals.suffix(4).reversed()) { d in
                            dealRow(d, contactId: c.id, cur: cur)
                        }
                        if !deals.isEmpty {
                            GroupRow {
                                Text("Удержи запись, чтобы удалить ошибочную").font(Typo.body(12)).foregroundStyle(Pal.fg3)
                                Spacer()
                            }
                        }
                    }
                    .glassRect(24)

                    Cap("Метки")
                    FlowLayout(spacing: 8) {
                        ForEach(store.labels.filter { tagIcon($0) == nil }, id: \.self) { l in
                            let on = (c.tags ?? []).contains(l)
                            Chip(text: on ? l + "  ✕" : l, on: false, height: 32, fontSize: 13, fill: on ? labelColor(l) : nil) { toggleTag(c, l) }
                                .accessibilityLabel(on ? "Метка \(l), нажми, чтобы снять" : "Метка \(l), нажми, чтобы поставить")
                        }
                        Button { sheet = .label } label: {
                            Text("+ Метка").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                                .padding(.horizontal, 14).frame(height: 32)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Pal.fg.opacity(0.4)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)

                    aiBlock(c)
                    findingsBlock(c)
                    mergeBlock(c)

                    Cap("Напоминание")
                    Group {
                        if let rem {
                            GroupRow(first: true) {
                                Image(systemName: "clock").foregroundStyle(Pal.apricot)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.whenFull(rem.date)).font(Typo.body(16, .medium)).foregroundStyle(Pal.fg)
                                    Text(rem.text).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                                }
                                .padding(.vertical, 8)
                                Spacer()
                                PillButton(action: { Task { await store.perform([["type": "doneReminder", "id": rem.id]], contactId: c.id, ok: "Напоминание выполнено") } }) {
                                    Text("Готово").font(Typo.body(13, .medium))
                                }
                                Button { Task { await store.perform([["type": "removeReminder", "id": rem.id]], contactId: c.id, ok: "Напоминание удалено") } } label: {
                                    Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Удалить напоминание")
                            }
                        } else {
                            Button { sheet = .remind } label: {
                                GroupRow(first: true) {
                                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    Text("Поставить напоминание").font(Typo.body(16, .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Pal.acc)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)

                    Cap("Заметка")
                    TextField("", text: $note, prompt: Text("Что важно помнить о клиенте").foregroundColor(Pal.fg3), axis: .vertical)
                        .lineLimit(3...10)
                        .font(Typo.body(15))
                        .foregroundStyle(Pal.fg)
                        .focused($focus, equals: .note)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .glassRect(24)

                    Cap("Контакты")
                    VStack(spacing: 0) {
                        ForEach(Array(convs.enumerated()), id: \.element.id) { i, conv in
                            let n = NetInfo.of(conv.network)
                            GroupRow(first: i == 0) {
                                Circle().fill(n.color).frame(width: 10, height: 10).padding(.horizontal, 6)
                                Text(n.name).foregroundStyle(Pal.fg)
                                Spacer()
                                Text(c.handle ?? c.name).foregroundStyle(Pal.fg2).lineLimit(1)
                            }
                        }
                        if let p = phoneOf(c, convs) {
                            GroupRow(first: convs.isEmpty) {
                                Image(systemName: "phone").foregroundStyle(Pal.fg.opacity(0.7))
                                Text("Телефон").foregroundStyle(Pal.fg)
                                Spacer()
                                Text(p).foregroundStyle(Pal.fg2).textSelection(.enabled)
                            }
                        }
                        if store.inBook(c) {
                            GroupRow {
                                Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Pal.acc)
                                Text("В контактах телефона").foregroundStyle(Pal.fg)
                                Spacer()
                            }
                        } else {
                            Button { store.addToBook(c) } label: {
                                GroupRow {
                                    Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Pal.acc)
                                    Text("Добавить в контакты").font(Typo.body(16, .semibold)).foregroundStyle(Pal.acc)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        if let e = c.email, !e.isEmpty {
                            GroupRow {
                                Image(systemName: "envelope").foregroundStyle(Pal.fg.opacity(0.7))
                                Text("Почта").foregroundStyle(Pal.fg)
                                Spacer()
                                Text(e).foregroundStyle(Pal.fg2).lineLimit(1).textSelection(.enabled)
                            }
                        }
                    }
                    .glassRect(24)

                    ClientMaterials(contactId: c.id).padding(.top, 22)

                    VStack(spacing: 0) {
                        Button { blockAsk = true } label: {
                            GroupRow(first: true) {
                                Image(systemName: "hand.raised").foregroundStyle(Pal.danger)
                                Text("Заблокировать").font(Typo.body(16, .semibold)).foregroundStyle(Pal.danger)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .glassRect(24)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
            .refreshable { await store.loadState(force: true) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    if focus == .note { saveNote() }
                    focus = nil
                }
                .font(Typo.body(16, .semibold))
            }
        }
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: { haptic(); run() }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(Pal.fg)
                    .frame(width: 54, height: 54)
                    .glass(.light, in: Circle(), interactive: true)
                Text(title).font(Typo.body(12, .medium)).foregroundStyle(Pal.fg)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
    }

    private func markPaid(_ c: Contact) {
        guard amount > 0 else {
            store.show("Сначала впиши сумму сделки", ok: false)
            focus = .amount
            return
        }
        let promised = store.deals(of: c.id).last { $0.status == "promised" }
        var body: [String: Any] = ["type": "pay", "contactId": c.id, "productId": NSNull(), "amount": amount]
        if let promised { body["dealId"] = promised.id }
        let a = amount
        Task {
            if await store.perform([body], contactId: c.id, ok: "Оплата \(Fmt.money(Double(a), currency: store.state.workspace?.currency)) — в «Оплатил»") {
                store.dealDraft[c.id] = nil
                amountText = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func promise(_ c: Contact) {
        let body: [String: Any] = ["type": "promise", "contactId": c.id, "productId": NSNull(), "amount": amount, "remindAt": isoString(RemPreset.tomorrow.date)]
        Task { await store.perform([body], contactId: c.id, ok: "В «Оплатит позже», напомню завтра в 10:00") }
    }

    private func toggleTag(_ c: Contact, _ t: String) {
        var tags = c.tags ?? []
        let had = tags.contains(t)
        if had { tags.removeAll { $0 == t } } else { tags.append(t) }
        let body: [String: Any] = ["type": "updateContact", "contactId": c.id, "tags": tags]
        Task { await store.perform([body], contactId: c.id, ok: had ? "Метка «\(t)» снята" : "Метка «\(t)» добавлена") }
    }

    /// Строка оплаты/обещания: удержание — удалить (с «Отменить» нельзя: запись пропадает на сервере целиком).
    private func dealRow(_ d: Deal, contactId: String, cur: String?) -> some View {
        let icon: String = d.status == "paid" ? "checkmark.circle.fill" : (d.status == "refund" ? "arrow.uturn.left.circle" : "clock")
        let color: Color = d.status == "paid" ? Pal.mint : (d.status == "refund" ? Pal.danger : Pal.apricot)
        let title: String = d.status == "paid" ? "Оплата" : (d.status == "refund" ? "Возврат" : "Обещал(а)")
        return GroupRow {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).foregroundStyle(Pal.fg2)
            Spacer()
            Text(Fmt.money(d.amount, currency: cur)).font(Typo.display(14)).foregroundStyle(Pal.fg)
            Text(Fmt.dayLong(d.day)).font(Typo.body(13)).foregroundStyle(Pal.fg3)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if d.status == "promised" {
                Button(role: .destructive) { removeDeal(d, contactId: contactId, ok: "Обещание снято") } label: { Label("Снять обещание", systemImage: "xmark.circle") }
            } else {
                Button(role: .destructive) { removeDeal(d, contactId: contactId, ok: "Запись об оплате удалена") } label: { Label("Удалить запись", systemImage: "trash") }
            }
        }
    }

    private func removeDeal(_ d: Deal, contactId: String, ok: String) {
        confirmDeal = DealRemoval(deal: d, ok: ok)
    }
}

/// Перенос чипов по строкам.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
