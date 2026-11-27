import SwiftUI

/// Сводка: лиды, оплаты, ждут ответа (только «Сегодня»), напомнить, входящие по дням, «Написать сегодня».
struct SummaryView: View {
    @Environment(Store.self) private var store
    @State private var period = "week"

    var body: some View {
        Screen(bottom: 120) {
            TabHeader(title: "Сводка", sub: "лиды, оплаты и кому написать сегодня") { BellAndAccount() }
            Seg(items: [("today", "Сегодня", nil), ("week", "Неделя", nil), ("month", "Месяц", nil)], selection: $period)
                .padding(.horizontal, 16)
            content
        }
        .refreshable { await store.loadState(force: true) }
    }

    @ViewBuilder private var content: some View {
        switch dataState(store) {
        case .loading:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in Skel(h: 112, r: 24) }
            }
            .padding(.horizontal, 12).padding(.top, 16)
            Skel(h: 180, r: 26).padding(12)
        case .error:
            EmptyBlock(icon: "alert", title: "Не получилось загрузить", text: "Сервер не ответил. Проверьте связь и попробуйте ещё раз", error: true,
                       button: "Повторить", buttonIcon: "refresh") { Task { await store.loadState(force: true) } }
        case .empty:
            EmptyBlock(icon: "trend", title: "Пока тихо", text: "Сводка заполнится, когда клиенты начнут писать")
        case .ready:
            if store.offline || store.demo == .offline { OfflineBanner().padding(.top, 12) }
            cards
            chart
            todo
        }
    }

    private var days: Int { period == "today" ? 1 : (period == "week" ? 7 : 30) }
    private var per: String { period == "today" ? "за сегодня" : (period == "week" ? "за неделю" : "за месяц") }

    private var cards: some View {
        let s = store.stats(days: days)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatCard(tint: Th.tBlue, icon: "userPlus", label: "Новых лидов", value: "\(s.leads)", cap: per) { store.tab = .clients }
                StatCard(tint: Th.tGreen, icon: "wallet", label: "Оплатили", value: "\(s.paid)", cap: per) { store.tab = .payments }
            }
            if period == "today" {
                HStack(spacing: 10) {
                    StatCard(tint: Th.tYellow, icon: "trend", label: "Выручка", value: store.money(s.revenue), cap: per) { store.tab = .payments }
                    StatCard(tint: Th.tLilac, icon: "msgSq", label: "Ждут ответа", value: "\(s.waiting)", cap: "клиент написал, мы молчим") {
                        store.messagesFilter = "wait"; store.tab = .messages
                    }
                }
            } else {
                StatCard(tint: Th.tYellow, icon: "trend", label: "Выручка", value: store.money(s.revenue), cap: per) { store.tab = .payments }
            }
            WideStat(tint: Th.tPink, icon: "bell", label: "Напомнить сегодня", value: "\(s.remind)", cap: "включая просроченные") {
                store.show(s.remind == 0 ? "На сегодня напоминаний нет" : "\(s.remind) \(pl(s.remind, "напоминание", "напоминания", "напоминаний")) на сегодня")
            }
        }
        .padding(.horizontal, 12).padding(.top, 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: period)
    }

    private var chart: some View {
        let s = store.stats(days: 14)
        let mx = max(1, s.bars.max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Входящие по дням").font(Typo.display(15, .semibold)).foregroundStyle(Th.fg)
                Spacer()
                Text("последние 14 дней").font(Typo.body(12, .medium)).foregroundStyle(Th.muted)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<14, id: \.self) { i in
                    BarCol(value: s.bars[i], max: mx, day: i < s.barDays.count ? s.barDays[i] : 0, today: i == 13, index: i)
                }
            }
            .frame(height: 120)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
        .glassRect(26)
        .padding(.horizontal, 12).padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Входящие за 14 дней: \(s.bars.reduce(0, +)), сегодня \(s.bars.last ?? 0)")
    }

    private var todo: some View {
        let list = store.todos
        return VStack(spacing: 0) {
            SectTitle(title: "Написать сегодня", small: "\(list.count)")
            if list.isEmpty {
                Text("На сегодня всё сделано").font(Typo.body(14)).foregroundStyle(Th.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 18).glassRect(20).padding(.horizontal, 12)
            }
            VStack(spacing: 8) {
                ForEach(list) { t in
                    TodoRow(t: t)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

enum DataState { case loading, error, empty, ready }

@MainActor
func dataState(_ store: Store) -> DataState {
    switch store.demo {
    case .loading: return .loading
    case .error: return .error
    case .empty: return .empty
    default: break
    }
    if !store.loaded && !store.fixture {
        if store.lastError != nil && store.state.conversations.isEmpty { return .error }
        if store.state.conversations.isEmpty && store.state.contacts.isEmpty { return .loading }
    }
    if store.state.conversations.isEmpty && store.state.contacts.isEmpty { return .empty }
    return .ready
}

/// Карточка сводки (.stat): цветная плашка сверху, цифра и подпись слева.
struct StatCard: View {
    let tint: Color
    let icon: String
    let label: String
    let value: String
    let cap: String
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Icon(name: icon, size: 18, weight: 2)
                    Text(label).font(Typo.body(13, .semibold)).lineLimit(1)
                }
                .foregroundStyle(Th.chipInk)
                .padding(.horizontal, 12).frame(height: 34)
                .background(Capsule().fill(tint))
                VStack(alignment: .leading, spacing: 4) {
                    Text(value).font(Typo.display(25, .semibold)).tracking(-0.5).foregroundStyle(Th.fg)
                        .lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(cap).font(Typo.body(12)).foregroundStyle(Th.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(PressStyle())
        .glassRect(24)
        .accessibilityElement(children: .combine)
    }
}

/// Широкая карточка в одну строку (.stat.full).
struct WideStat: View {
    let tint: Color
    let icon: String
    let label: String
    let value: String
    let cap: String
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Icon(name: icon, size: 18, weight: 2)
                    Text(label).font(Typo.body(13, .semibold)).lineLimit(1)
                }
                .fixedSize()
                .foregroundStyle(Th.chipInk)
                .padding(.horizontal, 12).frame(height: 34)
                .background(Capsule().fill(tint))
                Text(value).font(Typo.display(22, .semibold)).foregroundStyle(Th.fg).monospacedDigit().padding(.leading, 6)
                Text(cap).font(Typo.body(12)).foregroundStyle(Th.muted).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(6)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(PressStyle())
        .glassRect(24)
        .accessibilityElement(children: .combine)
    }
}

private struct BarCol: View {
    let value: Int
    let max: Int
    let day: Int
    let today: Bool
    let index: Int
    @State private var grown = false

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(value)").font(Typo.body(9.5, today ? .bold : .regular)).foregroundStyle(today ? Th.fg : Th.muted)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(today ? Th.teal : Th.fg.opacity(0.11))
                .frame(height: Swift.max(5, CGFloat(value) / CGFloat(max) * 72))
                .scaleEffect(y: grown ? 1 : 0, anchor: .bottom)
            Text("\(day)").font(Typo.body(9.5, today ? .bold : .regular)).foregroundStyle(today ? Th.fg : Th.muted)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(Double(index) * 0.03)) { grown = true } }
    }
}

private struct TodoRow: View {
    @Environment(Store.self) private var store
    let t: Store.Todo

    var body: some View {
        let c = store.contact(t.contactId)
        Button { store.openChat(contactId: t.contactId) } label: {
            HStack(spacing: 12) {
                Avatar(name: store.avatarName(c), size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(store.name(c)).font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg).lineLimit(1)
                        if let n = c?.source { NetBadge(network: n, size: 15, ring: false) }
                    }
                    HStack(spacing: 8) {
                        Text(t.text).font(Typo.body(14)).foregroundStyle(Th.muted).lineLimit(1)
                        Spacer(minLength: 4)
                        HStack(spacing: 3) {
                            Icon(name: "clock", size: 13)
                            Text(Calendar.current.isDateInToday(t.due) ? Fmt.hm(t.due) : Fmt.day(t.due))
                        }
                        .font(Typo.body(11.5, .semibold))
                        .foregroundStyle(t.late ? Th.wine : Th.muted)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .cardGlass(20)
        .contextMenu {
            if let r = t.reminderId { Button { store.doneReminder(r) } label: { Label("Готово", systemImage: "checkmark") } }
            Button { store.remind(t.contactId, at: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()) } label: {
                Label("Напомнить завтра", systemImage: "bell")
            }
        }
    }
}
