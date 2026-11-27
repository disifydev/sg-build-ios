import SwiftUI

/// Превью первой ссылки в сообщении (/api/link-preview, кэш на час на сервере и в памяти приложения).
struct LinkPreviewCard: View {
    @Environment(Store.self) private var store
    let url: URL
    let out: Bool
    @State private var preview: LinkPreview?

    var body: some View {
        Group {
            if let p = preview, (p.title ?? "").isEmpty == false || (p.description ?? "").isEmpty == false {
                Button { UIApplication.shared.open(url) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(out ? Pal.onAcc.opacity(0.6) : Pal.acc).frame(width: 3).clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.site ?? url.host ?? "").font(Typo.body(12, .semibold))
                                .foregroundStyle(out ? Pal.onAcc.opacity(0.85) : Pal.acc).lineLimit(1)
                            if let t = p.title, !t.isEmpty {
                                Text(t).font(Typo.body(13.5, .semibold)).foregroundStyle(out ? Pal.onAcc : Pal.fg).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            if let d = p.description, !d.isEmpty {
                                Text(d).font(Typo.body(12.5)).foregroundStyle((out ? Pal.onAcc : Pal.fg).opacity(0.7)).lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                        if let img = p.image, !img.isEmpty {
                            RemoteImage(raw: img, quiet: true)
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: 260, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((out ? Pal.onAcc : Pal.fg).opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .task(id: url) {
            let p = await store.linkPreview(url)
            withAnimation(.easeOut(duration: 0.2)) { preview = p }
        }
    }
}

/// «Печатает…» — три точки в пузыре входящего.
struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Pal.fg2).frame(width: 7, height: 7)
                    .offset(y: on ? -4 : 0)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous).fill(Pal.bubIn))
        .onAppear { on = true }
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
        .accessibilityLabel("Клиент печатает")
    }
}

/// Отправить позже: быстрые варианты и выбор даты.
struct ScheduleSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    let onPick: (Date) -> Void
    @State private var custom = Date().addingTimeInterval(3600)
    @State private var showCustom = false

    private var presets: [(String, Date)] {
        let cal = Calendar.current, now = Date()
        var out: [(String, Date)] = [("Через час", now.addingTimeInterval(3600))]
        if let ev = cal.date(bySettingHour: 19, minute: 0, second: 0, of: now), ev > now.addingTimeInterval(1800) { out.append(("Сегодня вечером", ev)) }
        out.append(("Завтра утром", RemPreset.tomorrow.date))
        out.append(("В понедельник", RemPreset.monday.date))
        return out
    }

    var body: some View {
        SheetBox(title: "Отправить позже", subtitle: text.isEmpty ? nil : "«\(text.prefix(80))»") {
            ForEach(presets.indices, id: \.self) { i in
                let p = presets[i]
                SheetOption(icon: "clock", title: p.0, subtitle: Fmt.whenFull(p.1), action: { pick(p.1) })
            }
            SheetOption(icon: "calendar", title: "Выбрать дату и время", action: { withAnimation { showCustom.toggle() } })
            if showCustom {
                DatePicker("", selection: $custom, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Pal.acc)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                Button { pick(custom) } label: {
                    Text("Отправить " + Fmt.whenFull(custom)).font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private func pick(_ d: Date) {
        dismiss()
        onPick(d)
    }
}

/// Список отложенных сообщений чата: отправить сейчас или отменить.
struct ScheduledListSheet: View {
    @Environment(Store.self) private var store
    let convId: String

    var body: some View {
        let items: [ScheduledMessage] = (store.scheduled[convId] ?? []).sorted { $0.date < $1.date }
        SheetBox(title: "Запланировано", subtitle: items.isEmpty ? "Отложенных сообщений нет" : ruCount(items.count, "сообщение", "сообщения", "сообщений")) {
            ForEach(items) { s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: s.status == "failed" ? "exclamationmark.circle.fill" : "clock")
                        Text(Fmt.whenFull(s.date))
                        if s.status == "failed" { Text("· не отправлено") }
                    }
                    .font(Typo.body(12.5, .semibold))
                    .foregroundStyle(s.status == "failed" ? Pal.danger : Pal.acc)
                    Text(s.text ?? "Вложение").font(Typo.body(15)).foregroundStyle(Pal.fg).lineLimit(4)
                    if let e = s.error, !e.isEmpty { Text(e).font(Typo.body(12)).foregroundStyle(Pal.danger) }
                    HStack(spacing: 8) {
                        PillButton(action: { Task { await store.sendScheduledNow(s) } }) { Text("Отправить сейчас").font(Typo.body(13, .medium)) }
                        PillButton(action: { Task { await store.cancelScheduled(s) } }) { Text("Отменить").font(Typo.body(13, .medium)).foregroundStyle(Pal.danger) }
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.fill))
                .padding(.bottom, 6)
            }
        }
        .task { await store.loadScheduled(convId) }
    }
}
