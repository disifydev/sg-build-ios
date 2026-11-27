import SwiftUI

/// Клиенты: «Все клиенты» и папки-вкладки с цветом, фильтр по классам, карточки.
struct ClientsView: View {
    @Environment(Store.self) private var store
    @State private var folderSel = "all"
    @State private var klass = "all"

    var body: some View {
        Screen(bottom: 120) {
            TabHeader(title: "Клиенты", sub: "папки по статусу") {
                GlassCircle(icon: "sliders", label: "Настроить папки") { store.open(.folders) }
                GlassCircle(icon: "plus", label: "Новый клиент") { store.sheet = .newClient }
            }
            if store.offline || store.demo == .offline { OfflineBanner() }
            folderTabs
            classChips.padding(.top, 10).padding(.bottom, 10)
            switch dataState(store) {
            case .loading: SkelRows(n: 6, size: 40)
            case .error:
                EmptyBlock(icon: "alert", title: "Не получилось загрузить", text: "Сервер не ответил. Проверьте связь и попробуйте ещё раз", error: true,
                           button: "Повторить", buttonIcon: "refresh") { Task { await store.loadState(force: true) } }
            case .empty:
                EmptyBlock(icon: "users", title: "Клиентов пока нет", text: "Они появятся, когда вам напишут, или добавьте клиента сами",
                           button: "Добавить клиента", buttonIcon: "plus") { store.sheet = .newClient }
            case .ready:
                list
            }
        }
        .refreshable { await store.loadState(force: true) }
    }

    private var contacts: [Contact] {
        var cs = store.state.contacts
        if folderSel != "all" { cs = cs.filter { $0.folderId == folderSel } }
        if klass != "all" { cs = cs.filter { $0.classes.contains(klass) } }
        return cs.sorted { lastAt($0) > lastAt($1) }
    }

    private func lastAt(_ c: Contact) -> Date {
        store.mainConversation(of: c.id).map { store.lastDate($0) } ?? c.first
    }

    private var folderTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ftab(id: "all", title: "Все клиенты", count: store.state.contacts.count, color: nil)
                    ForEach(store.folders) { f in
                        ftab(id: f.id, title: f.name, count: store.state.contacts.filter { $0.folderId == f.id }.count, color: f.color)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: folderSel) { _, v in withAnimation { proxy.scrollTo(v, anchor: .center) } }
        }
    }

    private func ftab(id: String, title: String, count: Int, color: String?) -> some View {
        let on = folderSel == id
        return Button {
            haptic()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { folderSel = id }
        } label: {
            HStack(spacing: 8) {
                if let color {
                    Circle().fill(on ? Th.ink : Color(css: color)).frame(width: 10, height: 10).scaleEffect(on ? 0.8 : 1)
                }
                Text(title).font(Typo.body(14, .semibold))
                Text("\(count)").font(Typo.body(12)).opacity(0.6).monospacedDigit()
            }
            .foregroundStyle(on ? Th.ink : Th.fg)
            .padding(.leading, 12).padding(.trailing, 14).frame(height: 40)
            .background { if on { Capsule().fill(color.map { Color(css: $0) } ?? Color(hex: 0xD9D0EC)) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .modifier(GlassIf(on: !on))
        .id(id)
    }

    private var classChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ChipBtn(title: "Все классы", on: klass == "all") { klass = "all" }
                ForEach(store.classes, id: \.self) { k in
                    ChipBtn(title: classTitle(k), on: klass == k) { klass = k }
                }
                ChipBtn(title: "Настроить", icon: "sliders") { store.open(.lists) }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var list: some View {
        let cs = contacts
        if cs.isEmpty {
            EmptyBlock(icon: "users", title: "Здесь пока никого", text: klass == "all" ? "В этой папке пока нет клиентов" : "Нет учеников с классом «\(classTitle(klass))»")
        } else {
            LazyVStack(spacing: 8) {
                ForEach(cs) { c in ClientCard(c: c, showFolder: folderSel == "all") }
            }
            .padding(.horizontal, 12)
        }
        Btn(title: "Добавить клиента", icon: "plus", kind: .tonal) { store.sheet = .newClient }
            .padding(.top, 12)
    }
}

/// Карточка клиента (.ccard).
struct ClientCard: View {
    @Environment(Store.self) private var store
    let c: Contact
    var showFolder = false

    var body: some View {
        let conv = store.mainConversation(of: c.id)
        let rem = store.reminder(for: c.id)
        let f = store.folder(c.folderId)
        Button { store.open(.profile(c.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Avatar(name: store.avatarName(c), size: 42, url: c.avatar)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(store.name(c)).font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                        Spacer(minLength: 4)
                        NetBadge(network: conv?.network ?? c.source, size: 15, ring: false)
                    }
                    HStack(spacing: 5) {
                        if showFolder, let f {
                            Circle().fill(Color(css: f.color)).frame(width: 9, height: 9)
                            Text(f.name + " ·")
                        }
                        Text(conv.map { Fmt.when(store.lastDate($0)) } ?? Fmt.when(c.first))
                    }
                    .font(Typo.body(12.5)).foregroundStyle(Th.muted)
                    let tags = c.classes.map(classTitle) + c.plainTags
                    if !tags.isEmpty || rem != nil {
                        Flow(spacing: 5) {
                            ForEach(tags, id: \.self) { TagPill(text: $0) }
                            if let rem { TagPill(text: "напомнить " + Fmt.day(rem.date), reminder: true) }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(PressStyle())
        .cardGlass(22)
    }
}

/// Оплаты: оплачено, обещали, просрочено; фильтр; отметить оплату; найденные ИИ оплаты.
struct PaymentsView: View {
    @Environment(Store.self) private var store
    @State private var filter = "all"

    var body: some View {
        Screen(bottom: 120) {
            TabHeader(title: "Оплаты", sub: "товары, обещания и оплаченные сделки") {
                GlassCircle(icon: "plus", label: "Новая оплата") { store.sheet = .newPay(contactId: nil) }
                GlassCircle(icon: "user", label: "Ещё", text: String((store.user?.name ?? "В").prefix(1)).uppercased()) { store.tab = .more }
            }
            if store.offline || store.demo == .offline { OfflineBanner() }
            switch dataState(store) {
            case .loading:
                VStack(spacing: 10) {
                    Skel(h: 104, r: 24)
                    HStack(spacing: 10) { Skel(h: 96, r: 24); Skel(h: 96, r: 24) }
                }
                .padding(.horizontal, 12)
                SkelRows(n: 5, size: 40)
            case .error:
                EmptyBlock(icon: "alert", title: "Не получилось загрузить", text: "Сервер не ответил. Проверьте связь и попробуйте ещё раз", error: true,
                           button: "Повторить", buttonIcon: "refresh") { Task { await store.loadState(force: true) } }
            case .empty:
                EmptyBlock(icon: "wallet", title: "Оплат пока нет", text: "Отмечайте оплаты и обещания, а мы напомним о просроченных",
                           button: "Новая оплата", buttonIcon: "plus") { store.sheet = .newPay(contactId: nil) }
            case .ready:
                if store.state.deals.isEmpty && store.findings.isEmpty {
                    EmptyBlock(icon: "wallet", title: "Оплат пока нет", text: "Отмечайте оплаты и обещания, а мы напомним о просроченных",
                               button: "Новая оплата", buttonIcon: "plus") { store.sheet = .newPay(contactId: nil) }
                } else {
                    totals
                    findings
                    Seg(items: [("all", "Все", nil), ("promised", "Обещали", nil), ("paid", "Оплачено", nil), ("late", "Просрочено", nil)], selection: $filter)
                        .padding(.horizontal, 16).padding(.top, 14)
                    rows
                }
            }
        }
        .refreshable { await store.loadState(force: true); await store.loadFindings() }
    }

    private var totals: some View {
        let d = store.state.deals
        let paid = d.filter { $0.status == "paid" }.reduce(0) { $0 + $1.amount }
        let prom = d.filter { $0.status == "promised" && !$0.isLate }.reduce(0) { $0 + $1.amount }
        let late = d.filter { $0.isLate }.count
        return VStack(spacing: 10) {
            PayStat(tint: Th.tGreen, label: "Оплачено", value: store.money(paid))
            HStack(spacing: 10) {
                PayStat(tint: Th.tYellow, label: "Обещали оплатить", value: store.money(prom))
                PayStat(tint: Th.tPink, label: "Просрочено", value: "\(late)")
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var findings: some View {
        ForEach(store.findings.prefix(3)) { f in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Icon(name: "wallet", size: 16).foregroundStyle(Th.ok)
                    Text("Найдена оплата: \(store.money(f.amount ?? 0))").font(Typo.body(15, .semibold)).foregroundStyle(Th.fg)
                }
                Text([f.payer ?? store.contact(f.contactId).map { store.name($0) }, f.source == "receipt" ? "чек" : "из переписки", f.purpose]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Typo.body(13)).foregroundStyle(Th.muted)
                if f.duplicateOf != nil { Text("Похоже на повтор уже записанного чека").font(Typo.body(12.5)).foregroundStyle(Th.warn) }
                HStack(spacing: 8) {
                    Btn(title: "Записать", small: true) { Task { await store.acceptFinding(f, true) } }
                    Btn(title: "Не оплата", kind: .outline, small: true) { Task { await store.acceptFinding(f, false) } }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardGlass(22)
            .padding(.horizontal, 12).padding(.top, 10)
        }
    }

    private var rows: some View {
        let list = store.state.deals.filter { d in
            switch filter {
            case "promised": return d.status == "promised" && !d.isLate
            case "paid": return d.status == "paid"
            case "late": return d.isLate
            default: return d.status != "refund"
            }
        }.sorted { $0.day > $1.day }
        return LazyVStack(spacing: 8) {
            if list.isEmpty {
                Text("Здесь пока пусто").font(Typo.body(14)).foregroundStyle(Th.muted).padding(.vertical, 24)
            }
            ForEach(list) { d in PayRow(d: d) }
        }
        .padding(.horizontal, 12).padding(.top, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: filter)
    }
}

private struct PayStat: View {
    let tint: Color
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(Typo.body(13, .semibold)).foregroundStyle(Th.chipInk).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(tint))
            Text(value).font(Typo.display(25, .semibold)).tracking(-0.5).foregroundStyle(Th.fg)
                .lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(24)
    }
}

private struct PayRow: View {
    @Environment(Store.self) private var store
    let d: Deal
    @State private var justPaid = false

    var body: some View {
        let c = store.contact(d.contactId)
        let product = store.state.products.first { $0.id == d.productId }?.name ?? "Оплата"
        HStack(spacing: 12) {
            Avatar(name: store.avatarName(c), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.name(c)).font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                Text(product + " · " + Fmt.day(d.day)).font(Typo.body(13)).foregroundStyle(Th.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.money(d.amount)).font(Typo.body(15, .semibold)).foregroundStyle(Th.fg).monospacedDigit()
                Text(status).font(Typo.body(11, .semibold)).foregroundStyle(color)
            }
            .padding(.trailing, 2)
            if d.status != "paid" {
                Button {
                    justPaid = true
                    store.markPaid(d)
                } label: {
                    Icon(name: "check", size: 16).foregroundStyle(Th.fg)
                        .frame(width: 38, height: 38).overlay(Circle().stroke(Th.hair, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Отметить оплату")
            } else if justPaid {
                Icon(name: "check", size: 16).foregroundStyle(.white).frame(width: 38, height: 38).background(Circle().fill(Th.ok))
                    .transition(.scale)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .cardGlass(20)
        .onTapGesture { if c != nil { store.open(.profile(d.contactId)) } }
    }

    private var status: String {
        if d.status == "paid" { return "оплачено" }
        if d.isLate { return "просрочено с " + Fmt.day(d.due ?? d.day) }
        return "обещал" + (d.due.map { " до " + Fmt.day($0) } ?? "")
    }

    private var color: Color { d.status == "paid" ? Th.ok : (d.isLate ? Th.wine : Th.warn) }
}
