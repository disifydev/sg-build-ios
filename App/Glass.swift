import SwiftUI

/// Стекло макета: `.lg` — светлое (кнопки, поля, чипы), `.lgd` — тёмное (группы, карточки, листы).
/// На iOS 26 — настоящий Liquid Glass (`glassEffect`), ниже — материал с той же кромкой.
enum GlassKind {
    case light, dark, bar
}

private struct GlassFallback<S: Shape>: View {
    let shape: S
    let kind: GlassKind
    var body: some View {
        ZStack {
            switch kind {
            case .light:
                shape.fill(.ultraThinMaterial)
                shape.fill(dyn(0xFFFFFF, 0x263233, 0.45, 0.45))
            case .dark:
                shape.fill(.ultraThinMaterial)
                shape.fill(dyn(0xFFFFFF, 0x1A2425, 0.55, 0.6))
            case .bar:
                shape.fill(.ultraThinMaterial)
                shape.fill(dyn(0xFFFFFF, 0x223031, 0.6, 0.55))
            }
            shape.stroke(LinearGradient(colors: [dyn(0xFFFFFF, 0xFFFFFF, 0.9, 0.18), dyn(0xFFFFFF, 0xFFFFFF, 0.35, 0.05)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
        }
        .shadow(color: dyn(0x14211F, 0x000000, 0.12, 0.3), radius: 12, y: 6)
    }
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ kind: GlassKind = .light, in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            switch kind {
            case .light:
                self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
            case .dark:
                self.glassEffect(Glass.regular.tint(dyn(0xFFFFFF, 0x0E1819, 0.35, 0.55)), in: shape)
            case .bar:
                self.glassEffect(Glass.regular.tint(dyn(0xFFFFFF, 0x152021, 0.25, 0.35)).interactive(), in: shape)
            }
        } else {
            self.background(GlassFallback(shape: shape, kind: kind))
        }
        #else
        self.background(GlassFallback(shape: shape, kind: kind))
        #endif
    }

    func glassCapsule(_ kind: GlassKind = .light, interactive: Bool = false) -> some View {
        glass(kind, in: Capsule(), interactive: interactive)
    }

    func glassRect(_ radius: CGFloat, _ kind: GlassKind = .dark) -> some View {
        glass(kind, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Главная кнопка макета (`.pri`): светло-сиреневая заливка с бликом.
struct PrimaryFill: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Pal.onAcc)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Pal.acc)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8).blendMode(.overlay))
                    .shadow(color: Pal.acc.opacity(0.3), radius: 9, y: 6)
            )
    }
}

extension View {
    func primaryFill(_ radius: CGFloat = 18) -> some View { modifier(PrimaryFill(radius: radius)) }
}

/// Нажатие с пружиной — у всех кастомных кнопок.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Строка группы (`.ln`) с разделителем сверху.
struct GroupRow<Content: View>: View {
    var first = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Pal.line).frame(height: 0.5) }
            HStack(spacing: 12) { content() }
                .font(Typo.body(16))
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
        }
    }
}

/// Подпись секции (`.cap`).
struct Cap: View {
    let text: String
    var color: Color = Pal.fg2
    init(_ text: String, color: Color = Pal.fg2) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(Typo.body(12, .semibold))
            .tracking(0.96)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

/// Цветная иконка строки (`.ic`).
struct RowIcon: View {
    let system: String
    let color: Color
    var body: some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Pal.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
    }
}

/// Плитка статистики (`.tile`).
struct Tile: View {
    let label: String
    let value: String
    var valueSize: CGFloat = 24
    var valueColor: Color = Pal.fg
    var labelSize: CGFloat = 12
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.body(labelSize)).foregroundStyle(Pal.fg2).lineLimit(1)
            Text(value).font(Typo.display(valueSize)).tracking(-0.03 * valueSize).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassRect(22)
    }
}

/// Переключатель макета (`.sw`).
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
            haptic()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Pal.acc : Pal.fg.opacity(0.18))
                Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.25), radius: 3, y: 2).padding(2)
            }
            .frame(width: 52, height: 32)
        }
        .buttonStyle(.plain)
    }
}

/// Сегменты (`.seg`).
struct GlassSegment<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = item.0 }
                    haptic()
                } label: {
                    Text(item.1)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(selection == item.0 ? Pal.onAcc : Pal.fg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selection == item.0 {
                                Capsule().fill(Pal.acc).shadow(color: Pal.acc.opacity(0.35), radius: 5, y: 3)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 40)
        .glassCapsule()
    }
}

/// Круглая стеклянная кнопка (`.circ.lg`).
struct CircleButton: View {
    let system: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 19
    let action: () -> Void
    var body: some View {
        Button(action: { haptic(); action() }) {
            Image(systemName: system)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Pal.fg)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: Circle(), interactive: true)
    }
}

struct PillButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) { label() }
                .font(Typo.body(15, .medium))
                .foregroundStyle(Pal.fg)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .glassCapsule(interactive: true)
    }
}
