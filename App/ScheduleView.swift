import SwiftUI

/// Расписание: неделя, занятия дня, добавление и правка (POST /api/schedule), предметы — локально.
struct ScheduleView: View {
    @Environment(Store.self) private var store
    @State private var day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let lessons = store.lessons(on: day)
        Screen {
            TopBar(back: { store.pop() }) {
                GlassCircle(icon: "plus", label: "Новое занятие") { store.sheet = .addLesson(editId: nil) }
            }
            LargeTitle(title: "Расписание")
            week
            HStack {
                Text(label(day)).font(Typo.display(17, .semibold)).foregroundStyle(Th.fg)
                Spacer()
                Text("\(lessons.count) \(pl(lessons.count, "занятие", "занятия", "занятий"))").font(Typo.body(12.5, .medium)).foregroundStyle(Th.muted)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
            if let e = store.lessonsError, lessons.isEmpty {
                EmptyBlock(icon: "cal", title: "Расписание недоступно", text: e)
            } else if lessons.isEmpty {
                EmptyBlock(icon: "cal", title: "Свободный день", text: "Занятий нет. Нажмите «+», чтобы добавить")
            } else {
                VStack(spacing: 8) {
                    ForEach(lessons) { l in LessonCard(l: l) }
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
        }
        .task { await store.loadLessons(week: day) }
        .onChange(of: day) { _, d in
            if Store.monday(of: d) != store.lessonsWeek { Task { await store.loadLessons(week: d) } }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: day)
    }

    private var week: some View {
        let monday = Store.monday(of: day)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: monday) ?? monday
                let on = Calendar.current.isDate(d, inSameDayAs: day)
                let has = !store.lessons(on: d).isEmpty
                Button {
                    haptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { day = d }
                } label: {
                    VStack(spacing: 2) {
                        Text(Fmt.weekdaysShort[Calendar.current.component(.weekday, from: d) - 1]).font(Typo.body(11, .medium))
                        Text("\(Calendar.current.component(.day, from: d))").font(Typo.body(17, .semibold)).monospacedDigit()
                            .foregroundStyle(on ? Th.onTeal : Th.fg)
                        Circle().frame(width: 4, height: 4).opacity(has ? 0.6 : 0)
                    }
                    .foregroundStyle(on ? Th.onTeal : Th.muted)
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Th.teal : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(6)
        .glassRect(24)
        .padding(.horizontal, 12).padding(.bottom, 14)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            let shift = v.translation.width < 0 ? 7 : -7
            withAnimation { day = Calendar.current.date(byAdding: .day, value: shift, to: day) ?? day }
        })
        .accessibilityHint("Смахните влево или вправо, чтобы сменить неделю")
    }

    private func label(_ d: Date) -> String {
        let wd = Fmt.weekdaysLong[Calendar.current.component(.weekday, from: d) - 1]
        if Calendar.current.isDateInToday(d) { return "Сегодня, " + wd }
        return wd.prefix(1).uppercased() + wd.dropFirst() + ", " + Fmt.day(d)
    }
}

private struct LessonCard: View {
    @Environment(Store.self) private var store
    let l: Lesson

    var body: some View {
        let s = store.subject(of: l)
        let c = store.contact(l.contactId)
        Button { store.sheet = .lesson(l.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.hm(l.start)).font(Typo.body(15, .bold)).monospacedDigit().foregroundStyle(Th.fg)
                    Text("\(l.minutes) мин").font(Typo.body(12, .medium)).foregroundStyle(Th.muted)
                }
                .frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s?.name ?? "Занятие").font(Typo.body(15, .semibold)).foregroundStyle(Th.fg)
                    Text(store.name(c)).font(Typo.body(13)).foregroundStyle(Th.muted)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color(css: s?.color ?? "#9CC3D3")).frame(width: 3) }
                Spacer(minLength: 0)
                if l.seriesId != nil { Icon(name: "refresh", size: 13).foregroundStyle(Th.faint) }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .cardGlass(22)
    }
}
