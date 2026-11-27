import SwiftUI
import UIKit

// Токены макета sguardo-apps.html (:root, светлая и тёмная тема). Цвета динамические: меняются вместе с темой.
private func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
    Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: da) : UIColor(hex: light, alpha: la)
    })
}

enum Th {
    static let cream = dyn(0xECE6DC, 0x0C1213)
    static let fg = dyn(0x14211F, 0xE8E4DC)
    static let muted = dyn(0x5F6D6A, 0x9AA6A3)
    static let faint = dyn(0x8A9694, 0x6B7875)
    static let teal = dyn(0x0F3D42, 0x9FD3CC)
    static let onTeal = dyn(0xF3EFE8, 0x0B2224)
    static let wine = dyn(0x7B1419, 0xE8918F)
    static let ok = dyn(0x1E6B4A, 0x7FD1A8)
    static let warn = dyn(0x9A6408, 0xE8C070)
    static let danger = dyn(0xC4302B, 0xF08A84)
    static let glass = dyn(0xFFFFFF, 0x263233, 0.5, 0.48)
    static let glass2 = dyn(0xFFFFFF, 0x2C3839, 0.72, 0.8)
    static let glassEdge = dyn(0xFFFFFF, 0xFFFFFF, 0.9, 0.16)
    static let glHi = dyn(0xFFFFFF, 0xFFFFFF, 0.75, 0.14)
    static let glSh = dyn(0x14211F, 0x000000, 0.22, 0.55)
    static let hair = dyn(0x14211F, 0xFFFFFF, 0.08, 0.08)
    static let au1 = dyn(0x8CBAB4, 0x1C5456, 0.6, 0.55)
    static let au2 = dyn(0xF2C6A8, 0x603A28, 0.55, 0.32)
    static let au3 = dyn(0xE2AAAC, 0x642228, 0.5, 0.36)
    static let bubIn = dyn(0xFFFFFF, 0x2E3A3B, 0.72, 0.78)
    static let rowBg = dyn(0xF3EEE7, 0x182223)
    static let bubOut = dyn(0x0F3D42, 0x1F5A5E)
    static let bubOutFg = dyn(0xF3EFE8, 0xEAF4F2)
    static let tBlue = dyn(0xC3DAE3, 0x29434D)
    static let tGreen = dyn(0xBFE0CF, 0x26443A)
    static let tYellow = dyn(0xF0DDA8, 0x4A4127)
    static let tLilac = dyn(0xD9D0EC, 0x3A3450)
    static let tPink = dyn(0xEFC0BC, 0x52302F)
    static let tPeach = dyn(0xF3C9AE, 0x52392A)
    /// подпись на цветной плашке (.stat .sh): тёмная в светлой теме, светлая в тёмной
    static let chipInk = dyn(0x14211F, 0xE8E4DC)
    /// тёмный текст на пастельной заливке (аватарки, вкладки папок) — в обеих темах
    static let ink = Color(hex: 0x14211F)
    /// тонкая подложка полей и групп внутри листа (color-mix fg 6%)
    static let fill6 = dyn(0x14211F, 0xE8E4DC, 0.06, 0.06)
    static let fill8 = dyn(0x14211F, 0xE8E4DC, 0.08, 0.08)
    static let tealSoft = dyn(0x0F3D42, 0x9FD3CC, 0.12, 0.14)

    /// цвета аватарок (PAL макета)
    static let avatarHex: [UInt32] = [0xE3D9C6, 0xC9D9E0, 0xF2C7B0, 0xD9D0EA, 0xC7E2D3, 0xF1E0A8, 0xEFC4C4, 0xD6E3C6]
    /// палитра папок и предметов (PALF макета)
    static let folderHex = ["#9CC3D3", "#B9A9DE", "#E2C06A", "#E9A37E", "#86C7A6", "#E59AA0", "#7FB3E8", "#C7B299", "#A3C97A", "#D68FD6", "#8FA3B8", "#F0A35E"]

    static func avatar(_ name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: avatarHex[sum % avatarHex.count])
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// "#RRGGBB" / "#RGB" из данных кабинета; непонятное — серо-голубой.
    init(css: String?) {
        var s = (css ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6, let v = UInt32(s, radix: 16) { self.init(hex: v) } else { self.init(hex: 0x8FA3B8) }
    }

    /// Пастельная заливка папки: цвет папки 45 % поверх фона (color-mix макета).
    static func tint(_ css: String?) -> Color {
        let base = UIColor(Color(css: css))
        return Color(UIColor { tc in
            let bg = tc.userInterfaceStyle == .dark ? UIColor(hex: 0x0C1213) : UIColor(hex: 0xECE6DC)
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            bg.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let k: CGFloat = tc.userInterfaceStyle == .dark ? 0.55 : 0.45
            return UIColor(red: r1 * k + r2 * (1 - k), green: g1 * k + g2 * (1 - k), blue: b1 * k + b2 * (1 - k), alpha: 1)
        })
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

func initials(_ name: String) -> String {
    let parts = name.split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
    let letters = parts.prefix(2).compactMap { $0.first }.map { String($0) }
    let s = letters.joined().uppercased()
    return s.isEmpty ? "?" : s
}

/// Склонение: pl(5, "занятие", "занятия", "занятий").
func pl(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m = n % 10, h = n % 100
    if m == 1 && h != 11 { return one }
    if m >= 2 && m <= 4 && (h < 10 || h >= 20) { return few }
    return many
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - форматирование

enum Fmt {
    static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "нояб", "дек"]
    static let weekdaysShort = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    static let weekdaysLong = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

    static func hm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func day(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 1) \(months[max(0, (c.month ?? 1) - 1)])"
    }

    /// Время в списке чатов: сегодня — часы, вчера, день недели, дата.
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        if d >= day0 { return hm(d) }
        if d >= day0.addingTimeInterval(-86400) { return "Вчера" }
        if d >= day0.addingTimeInterval(-6 * 86400) { return weekdaysShort[cal.component(.weekday, from: d) - 1] }
        return day(d)
    }

    /// Подпись дня в ленте сообщений.
    static func dayChip(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Сегодня" }
        if cal.isDateInYesterday(d) { return "Вчера" }
        return day(d)
    }

    static func whenFull(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "сегодня в " + hm(d) }
        if cal.isDateInYesterday(d) { return "вчера в " + hm(d) }
        if cal.isDateInTomorrow(d) { return "завтра в " + hm(d) }
        return day(d) + " в " + hm(d)
    }

    static func money(_ v: Double, currency: String? = "RUB") -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}"
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
        return n + "\u{00A0}" + symbol(currency)
    }

    static func symbol(_ c: String?) -> String {
        switch (c ?? "RUB").uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "TRY": return "₺"
        case "KZT": return "₸"
        default: return "₽"
        }
    }

    static func dur(_ s: Double) -> String {
        let t = max(0, Int(s.rounded()))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    static func size(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1f МБ", Double(bytes) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        return "\(max(1, bytes / 1000)) КБ"
    }
}
