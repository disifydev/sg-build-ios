import SwiftUI
import LocalAuthentication
import UserNotifications

@main
struct SguardoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(store.colorScheme)
                .task {
                    delegate.store = store
                    await store.bootstrap()
                    if let u = delegate.pendingURL, store.phase == .ready { delegate.pendingURL = nil; store.openURL(u) }
                }
                .onChange(of: store.phase) { _, p in
                    if p == .ready, let u = delegate.pendingURL { delegate.pendingURL = nil; store.openURL(u) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if store.phase == .ready {
                            Task { await store.loadState() }
                            store.startLive()
                            store.refreshBook()
                        }
                    case .background:
                        store.stopLive()
                        if store.faceOn && store.phase == .ready { store.locked = true }
                    case .inactive:
                        if store.faceOn && store.phase == .ready { store.locked = true }
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            Aurora()
            switch store.phase {
            case .launching:
                SplashView().transition(.opacity.combined(with: .scale(scale: 1.06)))
            case .login:
                LoginView().transition(.opacity)
            case .onboarding:
                OnboardingView().transition(.opacity)
            case .ready:
                MainView().transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
            if store.locked && store.phase == .ready {
                LockView().transition(.opacity).zIndex(5)
            }
            ToastView().zIndex(10)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: store.phase)
        .animation(.easeInOut(duration: 0.25), value: store.locked)
    }
}

// MARK: - заставка

/// Экран загрузки макета: глаз, слово Sguardo, подпись.
struct SplashView: View {
    @State private var shown = false
    var body: some View {
        VStack(spacing: 22) {
            Image("BrandIcon").resizable().scaledToFit()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 23.4, style: .continuous))
                .shadow(color: Color(hex: 0x0F3D42).opacity(0.35), radius: 15, y: 20)
                .scaleEffect(shown ? 1 : 0.4).opacity(shown ? 1 : 0)
            VStack(spacing: 22) {
                Text("Sguardo").font(Typo.display(30, .bold)).tracking(-0.6).foregroundStyle(Th.fg)
                Text("все клиенты в одном окне").font(Typo.body(14)).foregroundStyle(Th.muted)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
        }
        .task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sguardo, загрузка")
    }
}

// MARK: - главный экран и вкладки

struct MainView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .bottom) {
            Group {
                switch store.tab {
                case .home: NavigationStack(path: $store.homePath) { SummaryView().destinations() }
                case .messages: NavigationStack(path: $store.messagesPath) { MessagesView().destinations() }
                case .clients: NavigationStack(path: $store.clientsPath) { ClientsView().destinations() }
                case .payments: NavigationStack(path: $store.paymentsPath) { PaymentsView().destinations() }
                case .more: NavigationStack(path: $store.morePath) { MoreView().destinations() }
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
            if store.path.isEmpty {
                TabBar().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.path.isEmpty)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $store.sheet) { s in SheetHost(kind: s) }
    }
}

extension View {
    func destinations() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .chat(let id): ChatView(convId: id)
                case .profile(let id): ProfileView(contactId: id)
                case .editContact(let id): EditContactView(contactId: id)
                case .archive: ArchiveView()
                case .notifications: NotificationsView()
                case .schedule: ScheduleView()
                case .folders: FoldersView()
                case .lists: ListsView()
                case .staff: StaffView()
                case .account: AccountView()
                case .security: SecurityView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Фон и прокрутка вложенного экрана.
struct Screen<Content: View>: View {
    var bottom: CGFloat = 40
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Aurora()
            ScrollView {
                VStack(spacing: 0) { content() }
                    .padding(.bottom, bottom)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// Плавающая стеклянная панель вкладок с «линзой» (.itab). Лупы нет — по решению владелицы.
struct TabBar: View {
    @Environment(Store.self) private var store
    @Namespace private var ns
    @State private var boing = false

    private let items: [(Tab, String, String)] = [
        (.home, "grid", "Сводка"), (.messages, "chat", "Сообщения"), (.clients, "users", "Клиенты"), (.payments, "card", "Оплаты"), (.more, "ell", "Ещё"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let it = items[i]
                let on = store.tab == it.0
                Button { select(it.0) } label: {
                    VStack(spacing: 2) {
                        Icon(name: it.1)
                        Text(it.2).font(Typo.body(10, .semibold)).tracking(-0.1).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Th.teal : Th.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            Capsule().fill(Th.teal.opacity(0.13))
                                .overlay(Capsule().stroke(Th.glHi, lineWidth: 0.5))
                                .matchedGeometryEffect(id: "lens", in: ns)
                                .scaleEffect(x: boing ? 1.22 : 1, y: boing ? 0.9 : 1)
                        }
                    }
                    .overlay(alignment: .top) { badge(it.0) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(it.2)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(height: 64)
        .glass(Capsule(), interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 0)
    }

    private func select(_ t: Tab) {
        haptic()
        if store.tab == t {
            withAnimation { store.path = [] }
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { store.tab = t; boing = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.16)) { boing = false }
    }

    @ViewBuilder private func badge(_ t: Tab) -> some View {
        let n = t == .messages ? store.totalUnread : 0
        if n > 0 {
            Text(n > 99 ? "99+" : "\(n)")
                .font(Typo.body(10, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(Th.wine))
                .overlay(Capsule().stroke(Th.cream, lineWidth: 1.5))
                .offset(x: 12, y: 5)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Шапка вкладки: справа колокольчик и кабинет (или свои кнопки).
struct TabHeader<Actions: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { Spacer(); actions() }
                .padding(.horizontal, 16).frame(height: 52)
            LargeTitle(title: title, sub: sub)
        }
    }
}

/// Стандартные кнопки шапки: уведомления и кабинет.
struct BellAndAccount: View {
    @Environment(Store.self) private var store
    var body: some View {
        GlassCircle(icon: "bell", badge: store.newNotes, label: "Уведомления") { store.open(.notifications) }
        GlassCircle(icon: "user", label: "Кабинет", text: String((store.user?.name ?? "В").prefix(1)).uppercased()) { store.open(.account) }
    }
}

// MARK: - тост

struct ToastView: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack {
            Spacer()
            if let t = store.toast {
                HStack(spacing: 12) {
                    if !t.ok { Icon(name: "alert", size: 16).foregroundStyle(Th.danger) }
                    Text(t.text).font(Typo.body(14, .medium)).foregroundStyle(Th.fg).multilineTextAlignment(.leading)
                    if t.undo {
                        Button("Отменить") { store.runUndo() }.font(Typo.body(14, .bold)).foregroundStyle(Th.teal)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 46)
                .glassCapsule(strong: true)
                .padding(.horizontal, 24)
                .padding(.bottom, store.path.isEmpty ? 84 : 76)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .id(t.id)
                .onTapGesture { withAnimation { store.toast = nil } }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(store.toast != nil)
    }
}

// MARK: - блокировка Face ID

struct LockView: View {
    @Environment(Store.self) private var store
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Aurora()
            VStack(spacing: 18) {
                Image("BrandIcon").resizable().frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Sguardo").font(Typo.display(26, .bold)).foregroundStyle(Th.fg)
                if let message {
                    Text(message).font(Typo.body(14)).foregroundStyle(Th.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Btn(title: "Войти по Face ID", icon: "faceid", busy: busy) { unlock() }
                Btn(title: "Войти заново", kind: .text) { Task { await store.logout() } }
            }
        }
        .onAppear { unlock() }
    }

    /// Блокировка снимается только после успешной проверки; при любой ошибке экран остаётся.
    private func unlock() {
        guard !busy else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            message = "Face ID и код-пароль недоступны на этом телефоне. Войдите заново по почте."
            return
        }
        busy = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Вход в кабинет Sguardo") { ok, _ in
            Task { @MainActor in
                busy = false
                if ok { store.locked = false } else { message = "Не получилось подтвердить, попробуйте ещё раз" }
            }
        }
    }
}

// Свайп «назад» от края при скрытой навигационной панели.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

func appVersion() -> String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(v) (\(b))"
}
