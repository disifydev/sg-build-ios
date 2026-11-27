import SwiftUI

// Иконки макета: те же SVG-строки, что в константах IC и NET (viewBox 0 0 24 24), разбираются в Path один раз.

enum Paint: Equatable { case none, current, hex(UInt32) }

struct SVGElement {
    let path: Path
    let fill: Paint
    let stroke: Paint
    let strokeWidth: CGFloat?
}

enum SVG {
    private static var cache: [String: [SVGElement]] = [:]

    /// defaultStroke: true — как у иконок интерфейса (stroke=currentColor, fill=none), false — как у логотипов (fill по умолчанию).
    static func elements(_ src: String, defaultStroke: Bool) -> [SVGElement] {
        let key = (defaultStroke ? "s|" : "f|") + src
        if let c = cache[key] { return c }
        var out: [SVGElement] = []
        let tagRx = try! NSRegularExpression(pattern: "<(path|rect|circle)\\b([^>]*)/?>")
        let attrRx = try! NSRegularExpression(pattern: "([a-zA-Z-]+)=\"([^\"]*)\"")
        let ns = src as NSString
        for m in tagRx.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1))
            let attrStr = ns.substring(with: m.range(at: 2)) as NSString
            var a: [String: String] = [:]
            for am in attrRx.matches(in: attrStr as String, range: NSRange(location: 0, length: attrStr.length)) {
                a[attrStr.substring(with: am.range(at: 1))] = attrStr.substring(with: am.range(at: 2))
            }
            func num(_ k: String) -> CGFloat { CGFloat(Double(a[k] ?? "") ?? 0) }
            var p = Path()
            switch tag {
            case "path": p = parsePath(a["d"] ?? "")
            case "rect":
                let r = CGRect(x: num("x"), y: num("y"), width: num("width"), height: num("height"))
                let rx = num("rx")
                p = rx > 0 ? Path(roundedRect: r, cornerRadius: rx) : Path(r)
            default:
                let r = num("r")
                p = Path(ellipseIn: CGRect(x: num("cx") - r, y: num("cy") - r, width: 2 * r, height: 2 * r))
            }
            func paint(_ v: String?, _ def: Paint) -> Paint {
                guard let v else { return def }
                if v == "none" { return .none }
                if v == "currentColor" { return .current }
                if v.hasPrefix("#") {
                    var s = String(v.dropFirst())
                    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
                    return .hex(UInt32(s, radix: 16) ?? 0)
                }
                return def
            }
            let fill = paint(a["fill"], defaultStroke ? .none : .hex(0))
            let stroke = paint(a["stroke"], defaultStroke ? .current : .none)
            let sw = a["stroke-width"].flatMap { Double($0) }.map { CGFloat($0) }
            out.append(SVGElement(path: p, fill: fill, stroke: stroke, strokeWidth: sw))
        }
        cache[key] = out
        return out
    }

    // MARK: разбор атрибута d

    static func parsePath(_ d: String) -> Path {
        var p = Path()
        let chars = Array(d.unicodeScalars)
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint? = nil
        var lastCmd: Character = " "

        func skip() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }
        func isNumStart() -> Bool {
            skip()
            guard i < chars.count else { return false }
            let c = chars[i]
            return (c >= "0" && c <= "9") || c == "-" || c == "+" || c == "."
        }
        func number() -> CGFloat {
            skip()
            var s = ""
            var seenDot = false, seenE = false
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.unicodeScalars.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c >= "0" && c <= "9" { s.unicodeScalars.append(c); i += 1 }
                else if c == "." && !seenDot && !seenE { seenDot = true; s.unicodeScalars.append(c); i += 1 }
                else if (c == "e" || c == "E") && !seenE {
                    seenE = true; s.unicodeScalars.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.unicodeScalars.append(chars[i]); i += 1 }
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }
        func flag() -> Bool {
            skip()
            guard i < chars.count else { return false }
            let c = chars[i]; i += 1
            return c == "1"
        }

        while true {
            skip()
            if i >= chars.count { break }
            let c = chars[i]
            var gotLetter = false
            if CharacterSet.letters.contains(c) {
                cmd = Character(c); i += 1; gotLetter = true
            } else if !isNumStart() { i += 1; continue }
            if !gotLetter && (cmd == "Z" || cmd == "z") { i += 1; continue }
            let rel = cmd.isLowercase
            let up = Character(cmd.uppercased())
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            switch up {
            case "M":
                let to = pt(number(), number())
                p.move(to: to); cur = to; start = to
                cmd = rel ? "l" : "L"
                lastCtrl = nil
            case "L":
                let to = pt(number(), number()); p.addLine(to: to); cur = to; lastCtrl = nil
            case "H":
                let x = number(); let to = CGPoint(x: rel ? cur.x + x : x, y: cur.y); p.addLine(to: to); cur = to; lastCtrl = nil
            case "V":
                let y = number(); let to = CGPoint(x: cur.x, y: rel ? cur.y + y : y); p.addLine(to: to); cur = to; lastCtrl = nil
            case "C":
                let c1 = pt(number(), number()), c2 = pt(number(), number()), to = pt(number(), number())
                p.addCurve(to: to, control1: c1, control2: c2); cur = to; lastCtrl = c2
            case "S":
                let c1: CGPoint
                if let lc = lastCtrl, "CcSs".contains(lastCmd) { c1 = CGPoint(x: 2 * cur.x - lc.x, y: 2 * cur.y - lc.y) } else { c1 = cur }
                let c2 = pt(number(), number()), to = pt(number(), number())
                p.addCurve(to: to, control1: c1, control2: c2); cur = to; lastCtrl = c2
            case "Q":
                let c1 = pt(number(), number()), to = pt(number(), number())
                p.addQuadCurve(to: to, control: c1); cur = to; lastCtrl = c1
            case "T":
                let c1: CGPoint
                if let lc = lastCtrl, "QqTt".contains(lastCmd) { c1 = CGPoint(x: 2 * cur.x - lc.x, y: 2 * cur.y - lc.y) } else { c1 = cur }
                let to = pt(number(), number())
                p.addQuadCurve(to: to, control: c1); cur = to; lastCtrl = c1
            case "A":
                let rx = number(), ry = number(), rot = number()
                let large = flag(), sweep = flag()
                let to = pt(number(), number())
                arc(&p, from: cur, rx: rx, ry: ry, phi: rot, large: large, sweep: sweep, to: to)
                cur = to; lastCtrl = nil
            case "Z":
                p.closeSubpath(); cur = start; lastCtrl = nil
            default:
                break
            }
            lastCmd = cmd
        }
        return p
    }

    /// Дуга SVG → кубические кривые (W3C, приложение F.6).
    static func arc(_ p: inout Path, from p0: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, phi deg: CGFloat, large: Bool, sweep: Bool, to p1: CGPoint) {
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 || p0 == p1 { p.addLine(to: p1); return }
        let phi = deg * .pi / 180
        let cs = cos(phi), sn = sin(phi)
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cs * dx2 + sn * dy2
        let y1p = -sn * dx2 + cs * dy2
        let lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lam > 1 { let s = sqrt(lam); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let sign: CGFloat = large == sweep ? -1 : 1
        let coef = den == 0 ? 0 : sign * sqrt(max(0, num / den))
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)
        let cx = cs * cxp - sn * cyp + (p0.x + p1.x) / 2
        let cy = sn * cxp + cs * cyp + (p0.y + p1.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let t1 = ang(1, 0, ux, uy)
        var dt = ang(ux, uy, vx, vy)
        if !sweep && dt > 0 { dt -= 2 * .pi }
        if sweep && dt < 0 { dt += 2 * .pi }
        let segs = max(1, Int(ceil(abs(dt) / (.pi / 2) - 0.001)))
        let delta = dt / CGFloat(segs)
        let t = 4 / 3 * tan(delta / 4)
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cs * x - ry * sn * y, y: cy + rx * sn * x + ry * cs * y)
        }
        var a = t1
        for _ in 0..<segs {
            let b = a + delta
            let ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b)
            let c1 = map(ca - t * sa, sa + t * ca)
            let c2 = map(cb + t * sb, sb - t * cb)
            let e = map(cb, sb)
            p.addCurve(to: e, control1: c1, control2: c2)
            a = b
        }
    }
}

struct ScaledPath: Shape {
    let p: Path
    func path(in r: CGRect) -> Path {
        p.applying(CGAffineTransform(translationX: r.minX, y: r.minY).scaledBy(x: r.width / 24, y: r.height / 24))
    }
}

/// Иконка интерфейса из IC (обводка 1,9 при 22 pt, как в макете).
struct Icon: View {
    let name: String
    var size: CGFloat = 22
    var weight: CGFloat? = nil

    var body: some View {
        let els = SVG.elements(IC.src(name), defaultStroke: true)
        let sw = weight ?? (size <= 13 ? 2.2 : (size <= 18 ? 2 : 1.9))
        ZStack {
            ForEach(els.indices, id: \.self) { i in
                let e = els[i]
                if e.fill != .none { ScaledPath(p: e.path).fill(.foreground) }
                if e.stroke != .none {
                    ScaledPath(p: e.path).stroke(.foreground, style: StrokeStyle(lineWidth: (e.strokeWidth ?? sw) * size / 24, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum IC {
    static func src(_ n: String) -> String { all[n] ?? all["alert"]! }
    static let all: [String: String] = [
        "grid": "<rect x=\"3\" y=\"3\" width=\"7.5\" height=\"7.5\" rx=\"2.2\"/><rect x=\"13.5\" y=\"3\" width=\"7.5\" height=\"7.5\" rx=\"2.2\"/><rect x=\"3\" y=\"13.5\" width=\"7.5\" height=\"7.5\" rx=\"2.2\"/><rect x=\"13.5\" y=\"13.5\" width=\"7.5\" height=\"7.5\" rx=\"2.2\"/>",
        "chat": "<path d=\"M21 11.5a8.5 8.5 0 0 1-12.6 7.4L3 20.5l1.6-5A8.5 8.5 0 1 1 21 11.5z\"/>",
        "users": "<path d=\"M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2\"/><circle cx=\"9\" cy=\"7\" r=\"4\"/><path d=\"M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8\"/>",
        "card": "<rect x=\"2\" y=\"5\" width=\"20\" height=\"14\" rx=\"3\"/><path d=\"M2 10h20M6 15h4\"/>",
        "cal": "<rect x=\"3\" y=\"4\" width=\"18\" height=\"18\" rx=\"3\"/><path d=\"M16 2v4M8 2v4M3 10h18\"/>",
        "send": "<path d=\"M22 2 11 13M22 2l-7 20-4-9-9-4z\"/>",
        "shield": "<path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z\"/>",
        "ell": "<circle cx=\"12\" cy=\"12\" r=\"9.5\"/><circle cx=\"7.8\" cy=\"12\" r=\".9\" fill=\"currentColor\"/><circle cx=\"12\" cy=\"12\" r=\".9\" fill=\"currentColor\"/><circle cx=\"16.2\" cy=\"12\" r=\".9\" fill=\"currentColor\"/>",
        "more": "<circle cx=\"5\" cy=\"12\" r=\"1.7\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"12\" cy=\"12\" r=\"1.7\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"19\" cy=\"12\" r=\"1.7\" fill=\"currentColor\" stroke=\"none\"/>",
        "search": "<circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"m20.5 20.5-4.2-4.2\"/>",
        "bell": "<path d=\"M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9\"/><path d=\"M10.3 21a1.94 1.94 0 0 0 3.4 0\"/>",
        "plus": "<path d=\"M12 5v14M5 12h14\"/>",
        "chevL": "<path d=\"m15 18-6-6 6-6\"/>",
        "chevR": "<path d=\"m9 18 6-6-6-6\"/>",
        "chevD": "<path d=\"m6 9 6 6 6-6\"/>",
        "chevU": "<path d=\"m18 15-6-6-6 6\"/>",
        "mic": "<rect x=\"9\" y=\"2\" width=\"6\" height=\"12\" rx=\"3\"/><path d=\"M19 10v1a7 7 0 0 1-14 0v-1M12 18v4\"/>",
        "clip": "<path d=\"m21.4 11-9.2 9.2a6 6 0 0 1-8.5-8.5l8.6-8.6A4 4 0 1 1 18 8.8l-8.6 8.6a2 2 0 0 1-2.8-2.8l8.5-8.5\"/>",
        "clock": "<circle cx=\"12\" cy=\"12\" r=\"9.5\"/><path d=\"M12 6.5V12l3.5 2\"/>",
        "bolt": "<path d=\"M13 2 3 14h9l-1 8 10-12h-9z\"/>",
        "check": "<path d=\"M20 6 9 17l-5-5\"/>",
        "checks": "<path d=\"M17 7 6.5 17.5 2 13M22 7.5 13 16.5l-1-1\"/>",
        "x": "<path d=\"M18 6 6 18M6 6l12 12\"/>",
        "wifiOff": "<path d=\"m2 2 20 20M8.5 16.5a5 5 0 0 1 7 0M2 8.8a15 15 0 0 1 4.2-2.6M10.7 5c4-.4 8.1.9 11.3 3.8M16.9 11.3a10 10 0 0 1 2.2 1.6M5 13a10 10 0 0 1 5.2-2.8M12 20h.01\"/>",
        "alert": "<circle cx=\"12\" cy=\"12\" r=\"9.5\"/><path d=\"M12 7.5v5M12 16.2h.01\"/>",
        "refresh": "<path d=\"M3 12a9 9 0 0 1 15.4-6.4L21 8M21 3v5h-5M21 12a9 9 0 0 1-15.4 6.4L3 16M3 21v-5h5\"/>",
        "userPlus": "<path d=\"M15 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2\"/><circle cx=\"8.5\" cy=\"7\" r=\"4\"/><path d=\"M19 8v6M22 11h-6\"/>",
        "user": "<circle cx=\"12\" cy=\"8\" r=\"4\"/><path d=\"M20 21a8 8 0 0 0-16 0\"/>",
        "hour": "<path d=\"M5 22h14M5 2h14M17 22v-4.2a2 2 0 0 0-.6-1.4L12 12l-4.4 4.4a2 2 0 0 0-.6 1.4V22M7 2v4.2a2 2 0 0 0 .6 1.4L12 12l4.4-4.4a2 2 0 0 0 .6-1.4V2\"/>",
        "link": "<path d=\"M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.8 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7\"/>",
        "edit": "<path d=\"M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z\"/>",
        "play": "<path d=\"M8 5.5v13l11-6.5z\" fill=\"currentColor\"/>",
        "pause": "<rect x=\"6.5\" y=\"5\" width=\"4\" height=\"14\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/><rect x=\"13.5\" y=\"5\" width=\"4\" height=\"14\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>",
        "book": "<path d=\"M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20\"/><circle cx=\"12\" cy=\"9\" r=\"2.5\"/><path d=\"M8.5 14.5a3.5 3.5 0 0 1 7 0\"/>",
        "trend": "<path d=\"m22 7-8.5 8.5-5-5L2 17\"/><path d=\"M16 7h6v6\"/>",
        "inbox": "<path d=\"M22 12h-6l-2 3h-4l-2-3H2\"/><path d=\"M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z\"/>",
        "wallet": "<path d=\"M19 7V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4\"/><path d=\"M21 11h-5a2 2 0 0 0 0 4h5z\"/>",
        "msgSq": "<path d=\"M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z\"/>",
        "pin": "<path d=\"M12 17v5M9 10.8V4h6v6.8l3 3.2H6z\"/>",
        "ext": "<path d=\"M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\"/>",
        "mail": "<rect x=\"2\" y=\"4\" width=\"20\" height=\"16\" rx=\"3\"/><path d=\"m22 7-10 6L2 7\"/>",
        "moon": "<path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z\"/>",
        "phone": "<rect x=\"6\" y=\"2\" width=\"12\" height=\"20\" rx=\"3\"/><path d=\"M11 18h2\"/>",
        "laptop": "<rect x=\"4\" y=\"4\" width=\"16\" height=\"11\" rx=\"2\"/><path d=\"M2 19h20\"/>",
        "star": "<path d=\"m12 2 3 6.5 7 .8-5.2 4.8 1.4 7L12 17.5 5.8 21l1.4-7L2 9.3l7-.8z\"/>",
        "bellOff": "<path d=\"M8.7 3A6 6 0 0 1 18 8c0 2 .2 3.7.6 5M17 17H3s3-2 3-9c0-.6.1-1.2.3-1.7M10.3 21a1.94 1.94 0 0 0 3.4 0M2 2l20 20\"/>",
        "archive": "<rect x=\"2\" y=\"3\" width=\"20\" height=\"5\" rx=\"1.5\"/><path d=\"M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4\"/>",
        "trash": "<path d=\"M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2\"/>",
        "reply": "<path d=\"M9 17 4 12l5-5\"/><path d=\"M20 18v-2a4 4 0 0 0-4-4H4\"/>",
        "copy": "<rect x=\"9\" y=\"9\" width=\"13\" height=\"13\" rx=\"2\"/><path d=\"M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1\"/>",
        "fwd": "<path d=\"m15 17 5-5-5-5\"/><path d=\"M4 18v-2a4 4 0 0 1 4-4h12\"/>",
        "selc": "<circle cx=\"12\" cy=\"12\" r=\"9.5\"/><path d=\"m8 12 3 3 5-6\"/>",
        "save": "<path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3\"/>",
        "lock": "<rect x=\"4\" y=\"11\" width=\"16\" height=\"11\" rx=\"2.5\"/><path d=\"M8 11V7a4 4 0 0 1 8 0v4\"/>",
        "lockO": "<rect x=\"4\" y=\"11\" width=\"16\" height=\"11\" rx=\"2.5\"/><path d=\"M8 11V7a4 4 0 0 1 7.8-1.3\"/>",
        "flip": "<path d=\"M20 5h-3.2L15 3H9L7.2 5H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z\"/><path d=\"M9 12.5a3 3 0 0 0 5.6 1.5M15 11.5a3 3 0 0 0-5.6-1.5M14.6 16v-2h-2M9.4 8v2h2\"/>",
        "vcirc": "<circle cx=\"12\" cy=\"12\" r=\"9.5\"/><rect x=\"6.5\" y=\"9.5\" width=\"7.5\" height=\"5\" rx=\"1.3\"/><path d=\"m14 11.3 3.5-1.8v5l-3.5-1.8\"/>",
        "image": "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"3\"/><circle cx=\"9\" cy=\"9\" r=\"2\"/><path d=\"m21 15-5-5L5 21\"/>",
        "file": "<path d=\"M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z\"/><path d=\"M14 2v6h6\"/>",
        "sliders": "<path d=\"M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1\"/><circle cx=\"15\" cy=\"6\" r=\"2\"/><circle cx=\"9\" cy=\"12\" r=\"2\"/><circle cx=\"17\" cy=\"18\" r=\"2\"/>",
        "grip": "<circle cx=\"9\" cy=\"6\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"15\" cy=\"6\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"9\" cy=\"12\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"15\" cy=\"12\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"9\" cy=\"18\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"15\" cy=\"18\" r=\"1.3\" fill=\"currentColor\" stroke=\"none\"/>",
        "faceid": "<path d=\"M3 8V6a3 3 0 0 1 3-3h2M16 3h2a3 3 0 0 1 3 3v2M21 16v2a3 3 0 0 1-3 3h-2M8 21H6a3 3 0 0 1-3-3v-2M9 9v1.5M15 9v1.5M12 9v4h-1M9 16a4.5 4.5 0 0 0 6 0\"/>",
    ]
}

// MARK: - сети

struct NetStyle {
    let name: String
    let bg: AnyShapeStyle
    let glyph: String
}

enum Net {
    static func key(_ network: String?) -> String {
        switch network {
        case "telegram": return "tg"
        case "instagram": return "ig"
        case "whatsapp": return "wa"
        case "tiktok": return "tt"
        case "threads": return "th"
        case "vk": return "vk"
        case "avito": return "av"
        case "max": return "max"
        case "profi": return "pf"
        default: return "tg"
        }
    }

    static func name(_ network: String?) -> String { style(network).name }

    /// Сети, где номер телефона — единственное имя клиента (берём имя из телефонной книги).
    static func phoneOnly(_ network: String?) -> Bool { network == "whatsapp" || network == "max" }

    static func style(_ network: String?) -> NetStyle {
        switch key(network) {
        case "ig": return NetStyle(name: "Instagram", bg: AnyShapeStyle(RadialGradient(colors: [Color(hex: 0xFDF497), Color(hex: 0xFD5949), Color(hex: 0xD6249F), Color(hex: 0x285AEB)], center: UnitPoint(x: 0.3, y: 1.07), startRadius: 0, endRadius: 26)),
                                     glyph: "<rect x=\"4\" y=\"4\" width=\"16\" height=\"16\" rx=\"5\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.4\"/><circle cx=\"12\" cy=\"12\" r=\"3.8\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.4\"/>")
        case "wa": return NetStyle(name: "WhatsApp", bg: AnyShapeStyle(Color(hex: 0x25D366)),
                                   glyph: "<path fill=\"#fff\" d=\"M12 2.5a9.5 9.5 0 0 0-8.2 14.3L2.5 21.5l4.8-1.3A9.5 9.5 0 1 0 12 2.5zm4.7 13.1c-.2.6-1.2 1.1-1.7 1.1-.4.1-1 .1-1.6-.1a14 14 0 0 1-5.6-4.9c-.4-.6-.8-1.5-.8-2.4 0-.9.5-1.4.7-1.6.2-.2.4-.3.6-.3h.4c.1 0 .3 0 .5.4l.7 1.7c.1.1.1.3 0 .4l-.3.5-.3.4c-.1.1-.2.3-.1.5.1.2.6 1 1.3 1.6.9.8 1.6 1 1.9 1.1.2.1.4.1.5-.1l.7-.9c.2-.2.3-.2.5-.1l1.6.8c.2.1.4.2.4.3.1.1.1.6-.1 1.2z\"/>")
        case "tt": return NetStyle(name: "TikTok", bg: AnyShapeStyle(Color(hex: 0x111111)),
                                   glyph: "<path fill=\"#fff\" d=\"M16.6 2h-3.3v13.4a2.9 2.9 0 1 1-2.9-2.9c.3 0 .6 0 .9.1V9.2a6.3 6.3 0 1 0 5.3 6.2V8.7a7.6 7.6 0 0 0 4.4 1.4V6.8a4.4 4.4 0 0 1-4.4-4.4z\"/>")
        case "th": return NetStyle(name: "Threads", bg: AnyShapeStyle(Color(hex: 0x111111)),
                                   glyph: "<path fill=\"none\" stroke=\"#fff\" stroke-width=\"2.3\" d=\"M17 8.5C16 5.5 14 4 11.5 4 7.5 4 5 7 5 12s2.5 8 6.5 8c3 0 5.5-1.7 5.5-4.6 0-4.2-6.5-4.6-6.5-1.2 0 1.5 1.3 2.2 2.6 2.1 2-.1 3-1.8 3-4.6\"/>")
        case "vk": return NetStyle(name: "VK", bg: AnyShapeStyle(Color(hex: 0x0077FF)),
                                   glyph: "<path fill=\"#fff\" d=\"M12.9 17.5C6.9 17.5 3.4 13.4 3.3 6.5h3c.1 5 2.4 7.2 4.2 7.6V6.5h2.9v4.3c1.8-.2 3.6-2.2 4.3-4.3h2.8a8.3 8.3 0 0 1-3.8 5.4 8.6 8.6 0 0 1 4.5 5.6h-3.1a5.4 5.4 0 0 0-4.7-3.9v3.9z\"/>")
        case "av": return NetStyle(name: "Авито", bg: AnyShapeStyle(Color.white),
                                   glyph: "<circle cx=\"8\" cy=\"8\" r=\"4\" fill=\"#00AAFF\"/><circle cx=\"16.5\" cy=\"8.5\" r=\"2.6\" fill=\"#FF4053\"/><circle cx=\"8.5\" cy=\"16.5\" r=\"2.6\" fill=\"#965EEB\"/><circle cx=\"16\" cy=\"16\" r=\"3.4\" fill=\"#97CF26\"/>")
        case "max": return NetStyle(name: "MAX", bg: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3C8CFF), Color(hex: 0x7B3CF5)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                                    glyph: "<path fill=\"none\" stroke=\"#fff\" stroke-width=\"2.6\" d=\"M5 17V7l7 7 7-7v10\"/>")
        case "pf": return NetStyle(name: "Профи", bg: AnyShapeStyle(Color(hex: 0x2E7D5B)),
                                   glyph: "<rect x=\"2\" y=\"4\" width=\"20\" height=\"16\" rx=\"3\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2.2\"/><path fill=\"none\" stroke=\"#fff\" stroke-width=\"2.2\" d=\"m22 7-10 6L2 7\"/>")
        default: return NetStyle(name: "Telegram", bg: AnyShapeStyle(Color(hex: 0x29A9EB)),
                                 glyph: "<path fill=\"#fff\" d=\"M20.7 4.3 3 11.2c-1 .4-1 1.1 0 1.4l4.4 1.4 1.7 5.3c.2.6.5.7 1 .3l2.5-2.1 4.7 3.5c.7.4 1.2.2 1.4-.7l3-14c.3-1.2-.4-1.7-1-1.3zM9.2 14.1l8.5-6.1-6.6 7-.4 3z\"/>")
        }
    }
}

/// Логотип сети в кружке (.nb макета).
struct NetBadge: View {
    let network: String?
    var size: CGFloat = 19
    var ring: Bool = true

    var body: some View {
        let st = Net.style(network)
        let els = SVG.elements(st.glyph, defaultStroke: false)
        ZStack {
            Circle().fill(st.bg)
            ZStack {
                ForEach(els.indices, id: \.self) { i in
                    let e = els[i]
                    if case .hex(let h) = e.fill { ScaledPath(p: e.path).fill(Color(hex: h)) }
                    if case .hex(let h) = e.stroke {
                        ScaledPath(p: e.path).stroke(Color(hex: h), style: StrokeStyle(lineWidth: (e.strokeWidth ?? 2) * size * 0.58 / 24, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
        .overlay { if ring { Circle().stroke(Th.cream, lineWidth: 2).padding(-1) } }
        .accessibilityLabel(st.name)
    }
}
