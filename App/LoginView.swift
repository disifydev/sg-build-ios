import SwiftUI

/// Вход: почта → код из письма (/api/auth/code + /api/auth/verify) или почта + пароль (/api/auth/login).
struct LoginView: View {
    @Environment(Store.self) private var store
    @State private var email = UserDefaults.standard.string(forKey: "lastEmail") ?? ""
    @State private var password = ""
    @State private var code = ""
    @State private var step = 0 // 0 — почта, 1 — код
    @State private var passMode = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    enum Field { case email, pass, code }

    var body: some View {
        ZStack {
            Aurora()
            if step == 0 {
                emailStep.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                codeStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: passMode)
        .onAppear {
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"), i + 1 < ProcessInfo.processInfo.arguments.count,
               ProcessInfo.processInfo.arguments[i + 1] == "code" { email = "demo@sguardo.ru"; step = 1 }
            #endif
        }
    }

    private var emailStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            Image("BrandIcon")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21.6, style: .continuous))
                .shadow(color: Color(hex: 0x0F3D42).opacity(0.3), radius: 15, y: 16)
            Text("Sguardo")
                .font(Typo.display(30, .bold))
                .tracking(-0.6)
                .foregroundStyle(Th.fg)
                .padding(.top, 22)
            Text("все клиенты в одном окне")
                .font(Typo.body(15))
                .foregroundStyle(Th.muted)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
                field(icon: "mail", placeholder: "Почта", text: $email, secure: false)
                    .focused($focus, equals: .email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .submitLabel(passMode ? .next : .go)
                    .onSubmit { if passMode { focus = .pass } else { submit() } }
                if passMode {
                    field(icon: "lock", placeholder: "Пароль", text: $password, secure: true)
                        .focused($focus, equals: .pass)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let error {
                    Text(error).font(Typo.body(14)).foregroundStyle(Th.danger).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        .transition(.opacity)
                }
                Btn(title: passMode ? "Войти" : "Получить код", wide: true, busy: busy, action: submit)
                    .accessibilityIdentifier("login-submit")
                Btn(title: passMode ? "Войти по коду из письма" : "Войти по паролю", kind: .text) {
                    passMode.toggle(); error = nil
                }
            }
            .padding(16)
            .glassRect(32)
            Text("Кабинет создаётся на sguardo.ru.\nВход той же почтой, что в веб-кабинете.")
                .font(Typo.body(13))
                .foregroundStyle(Th.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircle(icon: "chevL", label: "Назад") { step = 0; code = ""; error = nil }
                .padding(.top, 8)
            Text("Код из письма")
                .font(Typo.display(28, .bold))
                .tracking(-0.6)
                .foregroundStyle(Th.fg)
                .padding(.top, 28)
            (Text("Отправили 6 цифр на ") + Text(email).foregroundColor(Th.fg).font(Typo.body(16, .medium)) + Text(". Письмо может идти до минуты."))
                .font(Typo.body(16))
                .foregroundStyle(Th.muted)
                .lineSpacing(4)
                .padding(.top, 12)
            // Обычное видимое поле: автоподстановка кода из Почты/Сообщений (над клавиатурой) надёжно вставляет только в видимое поле
            TextField("", text: $code, prompt: Text("000000").foregroundColor(Th.faint))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .font(Typo.display(30))
                .kerning(14)
                .multilineTextAlignment(.center)
                .foregroundStyle(Th.fg)
                .tint(Th.teal)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Th.glass2))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(focus == .code ? Th.teal : Th.glassEdge, lineWidth: focus == .code ? 2 : 0.5))
                .padding(.top, 30)
                .accessibilityIdentifier("code-field")
                .onChange(of: code) { _, v in
                    let digits = Self.extractCode(v)
                    if digits != v { code = digits }
                    if digits.count == 6 { verify() }
                }
            if let error {
                Text(error).font(Typo.body(14)).foregroundStyle(Th.danger).padding(.top, 14)
            }
            // Системная кнопка вставки: без окна «Разрешить вставку», работает всегда
            PasteButton(payloadType: String.self) { items in
                guard let s = items.first else { return }
                Task { @MainActor in code = Self.extractCode(s) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(Th.teal)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            Btn(title: "Отправить код ещё раз", kind: .text, wide: true) { requestCode(resend: true) }
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .code } }
    }

    private func codeCell(_ i: Int) -> some View {
        let chars = Array(code)
        let active = i == min(code.count, 5) && focus == .code
        return Text(i < chars.count ? String(chars[i]) : "")
            .font(Typo.display(24))
            .foregroundStyle(Th.fg)
            .frame(width: 48, height: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Th.glass2))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? Th.teal : Th.glassEdge, lineWidth: active ? 2 : 0.5))
            .scaleEffect(i < chars.count ? 1 : 0.97)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: chars.count)
    }

    @ViewBuilder
    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Icon(name: icon, size: 18).foregroundStyle(Th.muted)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Th.faint))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(Th.faint))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(Typo.body(17))
            .foregroundStyle(Th.fg)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Capsule().fill(Th.fill6))
    }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func submit() {
        guard !busy else { return }
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { withAnimation { error = "Введите почту" }; return }
        UserDefaults.standard.set(cleanEmail, forKey: "lastEmail")
        if passMode {
            guard !password.isEmpty else { withAnimation { error = "Введите пароль" }; return }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    _ = try await API.send("POST", "/api/auth/login/", json: ["email": cleanEmail, "password": password])
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await store.didLogin()
                } catch {
                    withAnimation { self.error = friendly(error) }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        } else {
            requestCode(resend: false)
        }
    }

    private func requestCode(resend: Bool) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                _ = try await API.send("POST", "/api/auth/code/", json: ["email": cleanEmail])
                if resend { store.show("Новый код отправлен") }
                withAnimation { step = 1 }
            } catch {
                withAnimation { self.error = friendly(error) }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// Код из вставленного текста: сначала ищем шесть цифр подряд (письмо целиком, «123 456»), иначе первые шесть цифр.
    static func extractCode(_ s: String) -> String {
        if let r = s.range(of: #"(?<!\d)\d{6}(?!\d)"#, options: .regularExpression) { return String(s[r]) }
        let compact = s.replacingOccurrences(of: #"(\d)[\s\-](?=\d)"#, with: "$1", options: .regularExpression)
        if let r = compact.range(of: #"(?<!\d)\d{6}(?!\d)"#, options: .regularExpression) { return String(compact[r]) }
        return String(s.filter(\.isNumber).prefix(6))
    }

    private func verify() {
        guard !busy, code.count == 6 else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                _ = try await API.send("POST", "/api/auth/verify/", json: ["email": cleanEmail, "code": code, "mode": "login"])
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                focus = nil
                await store.didLogin()
            } catch {
                withAnimation { self.error = friendly(error) }
                code = ""
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
