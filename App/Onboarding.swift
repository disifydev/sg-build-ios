import SwiftUI
import UserNotifications

/// Первый запуск после входа: объяснение перед запросом уведомлений, затем доступ к контактам.
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var step = 0

    var body: some View {
        ZStack {
            if step == 0 {
                page(dots: 0, art: AnyView(NotifyArt()), title: "Не пропускайте клиентов",
                     text: "Пришлём уведомление, когда напишет клиент или подойдёт время напомнить об оплате. Нажатие сразу открывает нужный чат.",
                     primary: "Включить уведомления", secondary: "Позже",
                     onPrimary: askNotify, onSecondary: { next(1) })
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                page(dots: 1, art: AnyView(BookArt()), title: "Имена из контактов",
                     text: "WhatsApp и MAX присылают только номер. Если он записан у вас в телефоне, в чатах будет имя из контактов. Выключается в разделе «Ещё».",
                     primary: "Разрешить доступ к контактам", secondary: "Не сейчас",
                     onPrimary: askContacts, onSecondary: { store.setContactsOn(false); store.finishOnboarding() })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: step)
        .onAppear {
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"), i + 1 < ProcessInfo.processInfo.arguments.count,
               ProcessInfo.processInfo.arguments[i + 1] == "onboard-contacts" { step = 1 }
            #endif
        }
    }

    private func page(dots: Int, art: AnyView, title: String, text: String, primary: String, secondary: String,
                      onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            art.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(i == dots ? Th.teal : Th.hair).frame(width: i == dots ? 22 : 8, height: 8)
                }
            }
            .padding(.bottom, 18)
            Text(title).font(Typo.display(25, .bold)).tracking(-0.5).foregroundStyle(Th.fg).padding(.bottom, 10)
            Text(text).font(Typo.body(15)).foregroundStyle(Th.muted).lineSpacing(4).padding(.bottom, 18)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                Btn(title: primary, wide: true, action: onPrimary)
                Btn(title: secondary, kind: .text, wide: true, action: onSecondary)
            }
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12)
    }

    private func next(_ s: Int) { withAnimation { step = s } }

    private func askNotify() {
        if store.fixture { next(1); return }
        store.setPush(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { next(1) }
    }

    private func askContacts() {
        if store.fixture { store.finishOnboarding(); return }
        store.setContactsOn(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.finishOnboarding() }
    }
}

/// Стопка уведомлений с колокольчиком (.nstack).
private struct NotifyArt: View {
    @State private var float = false
    @State private var ring = false
    private let cards = [("Наталья Фёдорова", "Лучше в четверг вечером"), ("Напоминание", "Николай Попов обещал оплатить сегодня"), ("Мария Козлова · Telegram", "А рассрочка есть?")]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 10) {
                    Image("BrandIcon").resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cards[i].0).font(Typo.body(13, .semibold)).foregroundStyle(Th.fg)
                        Text(cards[i].1).font(Typo.body(12.5)).foregroundStyle(Th.muted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 270)
                .glassRect(22)
                .scaleEffect(i == 0 ? 0.88 : (i == 1 ? 0.94 : 1))
                .opacity(i == 0 ? 0.55 : (i == 1 ? 0.8 : 1))
                .offset(y: CGFloat([20, 70, 124][i]) + (float ? -8 : 0))
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(Double(i) * 0.5), value: float)
            }
            Icon(name: "bell").foregroundStyle(Th.onTeal)
                .frame(width: 54, height: 54).background(Circle().fill(Th.teal))
                .rotationEffect(.degrees(ring ? 12 : -10), anchor: .top)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: ring)
                .offset(x: 210, y: -6)
        }
        .frame(width: 270, height: 250)
        .onAppear { float = true; ring = true }
    }
}

/// Карточка «номер → имя из книги» (.cbook).
private struct BookArt: View {
    @State private var swap = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Ирина Белова", "+7 916 204-18-33", "whatsapp")
            row("Ольга Никитина", "+7 903 771-52-09", "max").opacity(0.75)
            HStack(spacing: 8) {
                Icon(name: "book", size: 16)
                Text("имена из вашей телефонной книги").font(Typo.body(12.5))
            }
            .foregroundStyle(Th.muted)
        }
        .padding(18)
        .frame(width: 270)
        .glassRect(26)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).delay(1.2).repeatForever(autoreverses: true)) { swap = true }
        }
    }

    private func row(_ name: String, _ phone: String, _ net: String) -> some View {
        HStack(spacing: 12) {
            Avatar(name: name, network: net, size: 48)
            ZStack(alignment: .leading) {
                Text(phone).opacity(swap ? 0 : 1).offset(y: swap ? -22 : 0)
                Text(name).opacity(swap ? 1 : 0).offset(y: swap ? 0 : 22)
            }
            .font(Typo.body(15.5, .semibold)).foregroundStyle(Th.fg)
            .frame(height: 22).clipped()
        }
    }
}
