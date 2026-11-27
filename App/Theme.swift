import SwiftUI
import UIKit

// Цвета сайта sguardo.ru: светлая тема — крем и бирюза, тёмная — глубокий бирюзовый.
// Все токены динамические: меняются вместе с темой (Система / Светлая / Тёмная в Профиле).
func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
    Color(UIColor { tc in
        let h = tc.userInterfaceStyle == .dark ? dark : light
        let a = tc.userInterfaceStyle == .dark ? da : la
        return UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a)
    })
}

enum Pal {
    /// тёмный текст на пастельной заливке (метки, аватарки, значки) — в обеих темах
    static let ink = Color(hex: 0x14211F)
    /// текст на бирюзовой заливке (кнопки, свои сообщения, счётчики)
    static let onAcc = dyn(0xF3EFE8, 0x0B2224)
    static let fg = dyn(0x14211F, 0xE8E4DC)
    static let fg2 = dyn(0x5F6D6A, 0x9AA6A3)
    static let fg3 = dyn(0x8A9694, 0x6B7875)
    static let acc = dyn(0x0F3D42, 0x9FD3CC)
    static let wine = dyn(0x7B1419, 0xE8918F)
    static let mint = dyn(0x86C7A6, 0x7FD1A8)
    static let rose = dyn(0xE59AA0, 0xEFA3A0)
    static let apricot = dyn(0xE2C06A, 0xE8C070)
    static let sky = dyn(0x9CC3D3, 0x8EC0D3)
    static let lav = dyn(0xB9A9DE, 0xB9A9DE)
    static let teal = dyn(0x8FD0C8, 0x9FD3CC)
    static let danger = dyn(0xC4302B, 0xF08A84)
    static let line = dyn(0x14211F, 0xFFFFFF, 0.1, 0.1)
    static let page = dyn(0xECE6DC, 0x0C1213)
    static let chipOn = acc
    /// входящее сообщение (без размытия — лента остаётся лёгкой)
    static let bubIn = dyn(0xFFFFFF, 0x2A3637, 0.82, 0.92)
    /// мягкая подложка внутри карточек и листов
    static let fill = dyn(0x14211F, 0xFFFFFF, 0.06, 0.08)

    /// Палитра меток и цветов папок (как в вебе).
    static let labelHex = ["#E2C06A", "#9CC3D3", "#B9A9DE", "#E9A37E", "#86C7A6", "#8FD0C8"]
    static let folderHex = ["#9CC3D3", "#B9A9DE", "#E2C06A", "#E9A37E", "#86C7A6", "#E59AA0", "#7FB3E8", "#C7B299", "#A3C97A", "#D68FD6", "#8FA3B8", "#F0A35E"]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// "#RRGGBB" / "#RGB" из данных кабинета; непонятное — серый.
    init(css: String?) {
        var s = (css ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6, let v = UInt32(s, radix: 16) {
            self.init(hex: v)
        } else {
            self.init(hex: 0xB9B2B5)
        }
    }

    /// hsl(h 75% 82%) из макета — пастельный фон аватарки.
    static func avatar(hue: Double) -> Color {
        let l = 0.82, s = 0.75
        let v = l + s * min(l, 1 - l)
        let sv = v == 0 ? 0 : 2 * (1 - l / v)
        return Color(hue: (hue.truncatingRemainder(dividingBy: 360)) / 360, saturation: sv, brightness: v)
    }
}

enum Typo {
    /// Unbounded — заголовки и цифры.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Unbounded-Bold"
        case .medium, .regular, .light: name = "Unbounded-Medium"
        default: name = "Unbounded-SemiBold"
        }
        return .custom(name, size: size)
    }

    /// Onest — текст.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Onest-Bold"
        case .semibold: name = "Onest-SemiBold"
        case .medium: name = "Onest-Medium"
        default: name = "Onest-Regular"
        }
        return .custom(name, size: size)
    }
}

/// Хэш строки как в вебе (hue в макете) — для меток без цвета.
func stableHash(_ s: String) -> Int {
    var h = 0
    for u in s.unicodeScalars { h = (h &* 31 &+ Int(u.value)) % 360 }
    return abs(h)
}

func labelColor(_ name: String) -> Color {
    Color(css: Pal.labelHex[stableHash(name) % Pal.labelHex.count])
}

func initials(_ name: String) -> String {
    let cleaned = name.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " }
    let parts = String(String.UnicodeScalarView(cleaned)).split(separator: " ").map(String.init)
    guard let first = parts.first, !first.isEmpty else { return "?" }
    if parts.count > 1, let a = first.first, let b = parts[1].first { return "\(a)\(b)".uppercased() }
    return String(first.prefix(2)).uppercased()
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}
