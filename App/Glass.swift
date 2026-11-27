import SwiftUI

// Стекло макета (.glass): на iOS 26 — настоящий Liquid Glass (glassEffect), ниже — материал с бликом и кромкой.

private struct GlassFallback<S: Shape>: View {
    let shape: S
    var strong = false
    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(strong ? Th.glass2 : Th.glass)
            shape.fill(LinearGradient(stops: [.init(color: Th.glHi, location: 0), .init(color: .clear, location: 0.45)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.stroke(Th.glassEdge, lineWidth: 0.5)
        }
        .shadow(color: Th.glSh, radius: 13, y: 8)
    }
}

extension View {
    /// Стеклянная подложка в форме shape. strong — плотнее (листы, меню).
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, strong: Bool = false, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.tint(Th.glass.opacity(strong ? 0.7 : 0.35)).interactive()
                                         : Glass.regular.tint(Th.glass.opacity(strong ? 0.7 : 0.35)), in: shape)
        } else {
            self.background(GlassFallback(shape: shape, strong: strong))
        }
        #else
        self.background(GlassFallback(shape: shape, strong: strong))
        #endif
    }

    func glassCapsule(strong: Bool = false, interactive: Bool = false) -> some View {
        glass(Capsule(), strong: strong, interactive: interactive)
    }

    func glassRect(_ r: CGFloat, strong: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: r, style: .continuous), strong: strong)
    }

    /// Карточка-стекло без размытия фона под ней — для длинных списков (дешевле и не мерцает при прокрутке).
    func cardGlass(_ r: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(Th.glass)
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: Th.glHi.opacity(0.6), location: 0), .init(color: .clear, location: 0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Th.glassEdge, lineWidth: 0.5))
                .shadow(color: Th.glSh.opacity(0.6), radius: 10, y: 6)
        )
    }
}

/// Фон экрана: кремовый с тремя пятнами-сияниями (как .layer макета).
struct Aurora: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Th.cream
                blob(Th.au1, cx: 0, cy: 0, rx: 1.2 * w, ry: 0.55 * h, stop: 0.62)
                blob(Th.au2, cx: 1.05 * w, cy: 0.35 * h, rx: 0.9 * w, ry: 0.5 * h, stop: 0.6)
                blob(Th.au3, cx: 0.4 * w, cy: 1.12 * h, rx: 1.1 * w, ry: 0.55 * h, stop: 0.62)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(_ c: Color, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, stop: CGFloat) -> some View {
        Rectangle()
            .fill(EllipticalGradient(gradient: Gradient(stops: [.init(color: c, location: 0), .init(color: c.opacity(0), location: stop)]),
                                     center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: rx * 2, height: ry * 2)
            .position(x: cx, y: cy)
    }
}

/// Нажатие с пружиной (.press макета).
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Строка списка: лёгкое затемнение при нажатии.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Th.hair : Color.clear)
            .contentShape(Rectangle())
    }
}

// MARK: - кнопки

/// Круглая стеклянная кнопка 44 pt (.gcirc).
struct GlassCircle: View {
    let icon: String
    var badge: Int = 0
    var label: String = ""
    var text: String? = nil
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            ZStack {
                if let text { Text(text).font(Typo.body(16, .bold)) } else { Icon(name: icon) }
            }
            .foregroundStyle(Th.fg)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(Circle(), interactive: true)
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text("\(badge)").font(Typo.body(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Th.wine))
                    .offset(x: -6, y: 6)
                    .transition(.scale)
            }
        }
        .accessibilityLabel(label)
    }
}

/// Стеклянная кнопка-капсула с текстом (.gcap), primary — бирюзовая.
struct GlassCap: View {
    let title: String
    var primary = false
    let action: () -> Void
    var body: some View {
        Button { haptic(); action() } label: {
            Text(title).font(Typo.body(15, .semibold))
                .foregroundStyle(primary ? Th.onTeal : Th.fg)
                .padding(.horizontal, 18).frame(height: 44)
                .background { if primary { Capsule().fill(Th.teal) } }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .modifier(GlassIf(on: !primary))
    }
}

struct GlassIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.glassCapsule(interactive: true) } else { content }
    }
}

enum BtnKind { case primary, tonal, text, outline }

/// Кнопка макета (.btn): бирюзовая, тональная, текстовая, с обводкой.
struct Btn: View {
    let title: String
    var icon: String? = nil
    var kind: BtnKind = .primary
    var wide = false
    var small = false
    var danger = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(fg) } else if let icon { Icon(name: icon, size: 16) }
                Text(title).font(Typo.body(small ? 13.5 : (wide ? 16 : 15), .semibold))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 14 : 22)
            .frame(maxWidth: wide ? .infinity : nil)
            .frame(height: small ? 36 : (wide ? 54 : 48))
            .background(bg)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
    }

    private var fg: Color {
        if danger { return Th.danger }
        switch kind {
        case .primary: return Th.onTeal
        case .tonal, .text: return Th.teal
        case .outline: return Th.fg
        }
    }

    @ViewBuilder private var bg: some View {
        switch kind {
        case .primary: Capsule().fill(Th.teal)
        case .tonal: Capsule().fill(Th.tealSoft)
        case .text: Color.clear
        case .outline: Capsule().stroke(Th.hair, lineWidth: 1)
        }
    }
}

/// Переключатель макета (.sw): 51×31, бирюзовый во включённом.
struct Switch: View {
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button { haptic(); action() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Th.teal : Th.fg.opacity(0.16))
                Circle().fill(.white).frame(width: 27, height: 27).shadow(color: .black.opacity(0.2), radius: 3, y: 2).padding(2)
            }
            .frame(width: 51, height: 31)
            .animation(.spring(response: 0.4, dampingFraction: 0.65), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "включено" : "выключено")
    }
}

/// Сегменты с бирюзовым бегунком (.seg).
struct Seg<T: Hashable>: View {
    let items: [(T, String, Int?)]
    @Binding var selection: T
    var glassy = true
    @Namespace private var ns

    var body: some View {
        FlexRow {
            ForEach(items.indices, id: \.self) { i in
                let it = items[i]
                let on = selection == it.0
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { selection = it.0 }
                    haptic()
                } label: {
                    HStack(spacing: 5) {
                        Text(it.1).font(Typo.body(12.5, .semibold)).lineLimit(1).fixedSize()
                        if let n = it.2, n > 0 {
                            Text("\(n)").font(Typo.body(10, .bold))
                                .foregroundStyle(on ? Th.teal : Th.onTeal)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(on ? Th.onTeal : Th.teal))
                        }
                    }
                    .foregroundStyle(on ? Th.onTeal : Th.muted)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background {
                        if on {
                            Capsule().fill(Th.teal).shadow(color: Th.teal.opacity(0.45), radius: 6, y: 4)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .modifier(SegBG(glassy: glassy))
    }
}

private struct SegBG: ViewModifier {
    let glassy: Bool
    func body(content: Content) -> some View {
        if glassy { content.glass(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
        else { content.background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Th.fill6)) }
    }
}

/// Чип-фильтр (.chip): стекло или бирюзовый, когда выбран.
struct ChipBtn: View {
    let title: String
    var on = false
    var dot: Color? = nil
    var icon: String? = nil
    var chevron = false
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 6) {
                if let icon { Icon(name: icon, size: 16) }
                if let dot { Circle().fill(dot).frame(width: 9, height: 9) }
                Text(title).font(Typo.body(13.5, .medium)).lineLimit(1)
                if chevron { Icon(name: "chevD", size: 13) }
            }
            .foregroundStyle(on ? Th.onTeal : Th.fg)
            .padding(.horizontal, 14).frame(height: 36)
            .background { if on { Capsule().fill(Th.teal) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .modifier(GlassIf(on: !on))
    }
}

/// Тот же чип, но как подпись Menu (без собственной кнопки).
struct ChipLabel: View {
    let title: String
    var on = false
    var dot: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 9, height: 9) }
            Text(title).font(Typo.body(13.5, .medium)).lineLimit(1)
            Icon(name: "chevD", size: 13)
        }
        .foregroundStyle(on ? Th.onTeal : Th.fg)
        .padding(.horizontal, 14).frame(height: 36)
        .background { if on { Capsule().fill(Th.teal) } }
        .modifier(GlassIf(on: !on))
    }
}

/// Чип выбора внутри листа (.fchip).
struct FChip: View {
    let title: String
    var on = false
    var dot: Color? = nil
    var network: String? = nil
    let action: () -> Void
    var body: some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 7) {
                if let network { NetBadge(network: network, size: 16, ring: false) }
                if let dot { Circle().fill(dot).frame(width: 9, height: 9) }
                Text(title).font(Typo.body(13.5, .medium)).lineLimit(1)
            }
            .foregroundStyle(on ? Th.cream : Th.fg)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(on ? Th.fg : Color.clear))
            .overlay(Capsule().stroke(on ? Color.clear : Th.hair, lineWidth: 1))
            .scaleEffect(on ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - заголовки и группы

/// Большой заголовок экрана (.ltitle) и подпись.
struct LargeTitle: View {
    let title: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typo.display(31, .bold)).tracking(-0.6).foregroundStyle(Th.fg)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let sub, !sub.isEmpty { Text(sub).font(Typo.body(14)).foregroundStyle(Th.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.bottom, 14)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Верхняя панель (.ibar): слева «назад», справа действия.
struct TopBar<Trailing: View>: View {
    var back: (() -> Void)? = nil
    var title: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let back { GlassCircle(icon: "chevL", label: "Назад", action: back) }
            Spacer(minLength: 0)
            trailing()
        }
        .overlay { if let title { Text(title).font(Typo.body(16, .bold)).foregroundStyle(Th.fg).lineLimit(1).padding(.horizontal, 64) } }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

extension TopBar where Trailing == EmptyView {
    init(back: (() -> Void)? = nil, title: String? = nil) {
        self.back = back; self.title = title; self.trailing = { EmptyView() }
    }
}

/// Заголовок секции (.sect).
struct SectTitle: View {
    let title: String
    var small: String? = nil
    var body: some View {
        HStack {
            Text(title).font(Typo.display(17, .semibold)).foregroundStyle(Th.fg)
            Spacer()
            if let small { Text(small).font(Typo.body(12.5, .medium)).foregroundStyle(Th.muted) }
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
    }
}

/// Группа строк (.grp): стекло, скругление 26, разделители с отступом.
struct Group26<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .glassRect(26)
            .padding(.horizontal, 12)
    }
}

/// Разделитель внутри группы.
struct Hair: View {
    var inset: CGFloat = 56
    var body: some View { Rectangle().fill(Th.hair).frame(height: 0.5).padding(.leading, inset) }
}

/// Строка группы (.gi): бирюзовый квадрат-иконка, заголовок, подпись, правая часть.
struct GI<Right: View>: View {
    var icon: String? = nil
    let title: String
    var sub: String? = nil
    var danger = false
    var lead: AnyView? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var right: () -> Right

    var body: some View {
        let row = HStack(spacing: 14) {
            if let lead { lead }
            if let icon {
                Icon(name: icon, size: 16).foregroundStyle(Th.onTeal)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Th.teal))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(15)).foregroundStyle(danger ? Th.danger : Th.fg)
                if let sub { Text(sub).font(Typo.body(12.5)).foregroundStyle(Th.muted).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 4)
            right()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        if let action {
            Button { haptic(); action() } label: { row }.buttonStyle(RowStyle())
        } else {
            row
        }
    }
}

extension GI where Right == EmptyView {
    init(icon: String? = nil, title: String, sub: String? = nil, danger: Bool = false, lead: AnyView? = nil, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.sub = sub; self.danger = danger; self.lead = lead; self.action = action
        self.right = { EmptyView() }
    }
}

struct Chev: View {
    var body: some View { Icon(name: "chevR", size: 16).foregroundStyle(Th.faint) }
}

/// Подсказка мелким текстом (.ghint).
struct Hint: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.body(12.5)).foregroundStyle(Th.muted).lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 16)
    }
}

// MARK: - аватар

/// Аватар (.av): пастельный круг с инициалами или фото, значок сети снизу справа.
struct Avatar: View {
    let name: String
    var network: String? = nil
    var size: CGFloat = 46
    var url: String? = nil
    var color: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(color ?? Th.avatar(name))
            if name.hasPrefix("+") {
                Icon(name: "user", size: 16).foregroundStyle(Th.ink)
            } else {
                Text(initials(name)).font(Typo.body(size * 0.34, .semibold)).foregroundStyle(Th.ink)
            }
            if let url, let u = API.media(url) {
                AsyncImage(url: u) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() } else { Color.clear }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let network {
                NetBadge(network: network, size: size >= 90 ? 30 : 19).offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - состояния

/// Пустое состояние или ошибка (.empty) с вращающимся пунктирным кольцом.
struct EmptyBlock: View {
    let icon: String
    let title: String
    let text: String
    var error = false
    var button: String? = nil
    var buttonIcon: String? = nil
    var action: (() -> Void)? = nil
    @State private var spin = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(error ? Th.wine.opacity(0.14) : Th.tealSoft)
                Circle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle((error ? Th.wine : Th.teal).opacity(0.3))
                    .padding(-8)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: spin)
                Icon(name: icon, size: 28).foregroundStyle(error ? Th.wine : Th.teal)
            }
            .frame(width: 84, height: 84)
            .padding(.bottom, 6)
            Text(title).font(Typo.display(18, .semibold)).foregroundStyle(Th.fg).multilineTextAlignment(.center)
            Text(text).font(Typo.body(14)).foregroundStyle(Th.muted).multilineTextAlignment(.center).lineSpacing(2)
                .frame(maxWidth: 260)
            if let button, let action {
                Btn(title: button, icon: buttonIcon, action: action).padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.top, 48).padding(.bottom, 24)
        .onAppear { spin = true }
    }
}

/// Мерцающая заглушка загрузки (.skel).
struct Skel: View {
    var w: CGFloat? = nil
    var h: CGFloat
    var r: CGFloat = 10
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(Th.hair)
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Th.fg.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width)
                        .offset(x: phase * g.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
            .frame(width: w, height: h)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct SkelRows: View {
    var n = 7
    var size: CGFloat = 46
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { i in
                HStack(spacing: 12) {
                    Skel(w: size, h: size, r: size / 2)
                    VStack(alignment: .leading, spacing: 8) {
                        Skel(w: CGFloat(150 + (i * 37) % 80), h: 12)
                        Skel(w: CGFloat(190 + (i * 23) % 60), h: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }
}

/// Плашка «Нет интернета» (.offl).
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Icon(name: "wifiOff").foregroundStyle(Th.fg)
            VStack(alignment: .leading, spacing: 1) {
                Text("Нет интернета").font(Typo.body(13.5, .medium)).foregroundStyle(Th.fg)
                Text("Показываем сохранённое. Новое придёт, когда связь вернётся").font(Typo.body(12.5)).foregroundStyle(Th.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassRect(18)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Метка клиента (.tag).
struct TagPill: View {
    let text: String
    var reminder = false
    var body: some View {
        HStack(spacing: 4) {
            if reminder { Icon(name: "bell", size: 11) }
            Text(text).font(Typo.body(11.5, .semibold)).lineLimit(1)
        }
        .foregroundStyle(reminder ? Color.white : Th.fg)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(reminder ? Th.wine : Th.fill8))
    }
}

/// Поле ввода внутри листа (.field.sf).
struct SheetField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false

    var body: some View {
        HStack(spacing: 8) {
            Icon(name: icon, size: 16).foregroundStyle(Th.muted)
            Group {
                if secure { SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Th.faint)) }
                else { TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Th.faint)) }
            }
            .font(Typo.body(15)).foregroundStyle(Th.fg)
            .keyboardType(keyboard)
            .autocorrectionDisabled(keyboard != .default)
            .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Capsule().fill(Th.fill6))
    }
}

/// Подпись поля в листе (.lbl2).
struct Lbl: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.body(12.5, .medium)).foregroundStyle(Th.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2).padding(.top, 12).padding(.bottom, 7)
    }
}

/// Раскладка «в строку с переносом» для чипов.
struct Flow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        let maxX = bounds.minX + (proposal.width ?? bounds.width)
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > maxX + 0.5 { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Ряд: каждый получает естественную ширину плюс равную долю остатка (flex: 1 1 auto).
struct FlexRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let w = sizes.reduce(0) { $0 + $1.width }
        return CGSize(width: proposal.width ?? w, height: sizes.map { $0.height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = sizes.reduce(0) { $0 + $1.width }
        let extra = max(0, bounds.width - total) / CGFloat(max(1, subviews.count))
        let k = total > bounds.width && total > 0 ? bounds.width / total : 1
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            let w = sizes[i].width * k + extra
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w
        }
    }
}

/// Лист макета: заголовок по центру, прокрутка, стеклянный фон.
struct SheetBody<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(title).font(Typo.display(19, .semibold)).foregroundStyle(Th.fg)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22).padding(.bottom, 14)
                content()
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }
}

extension View {
    /// Оформление листа: стекло, крупное скругление, ручка.
    func sheetChrome(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self.presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
            .presentationBackground(.regularMaterial)
    }
}
