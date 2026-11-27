#if DEBUG
import Foundation
import SwiftUI

/// Только для снимков симулятора в CI (`-fixture`): демо-кабинет репетитора из макета, без сети. В сборку для TestFlight не попадает.
/// Аргументы: `-screen <экран>`, `-theme light|dark`, `-state loading|empty|error|offline`.
enum Fixture {
    @MainActor
    static func apply(_ s: Store) {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ k: String) -> String? {
            guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let t = arg("-theme"), let m = ThemeMode(rawValue: t) { s.theme = m }
        if let st = arg("-state"), let d = DemoState(rawValue: st) { s.demo = d }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        func day(_ off: Int) -> Date { cal.date(byAdding: .day, value: off, to: today) ?? today }
        func at(_ off: Int, _ hm: String) -> String {
            let p = hm.split(separator: ":").compactMap { Int($0) }
            return isoString(cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: day(off)) ?? today)
        }

        let folders = [
            Folder(id: "f0", key: "new", name: "Новые", color: "#9CC3D3"),
            Folder(id: "f1", key: "talking", name: "В диалоге", color: "#B9A9DE"),
            Folder(id: "f2", key: "thinking", name: "Думает", color: "#E2C06A"),
            Folder(id: "f3", key: "later", name: "Оплатит позже", color: "#E9A37E"),
            Folder(id: "f4", key: "paid", name: "Оплатил", color: "#86C7A6"),
        ]

        struct M { let o: Bool; let t: String; let at: String; var kind: String? = nil; var len: Double = 0; var rx: String? = nil; var name: String? = nil }
        struct C {
            let id: String; let n: String; let h: String?; let phone: String?; let net: String; let off: Int; let unread: Int; let folder: Int
            var pin = false; var mute = false; var arch = false; let klass: String?; let tags: [String]; let msgs: [M]
        }
        let chats: [C] = [
            C(id: "anna", n: "Анна Соколова", h: "@anna.sokolova", phone: nil, net: "telegram", off: 0, unread: 1, folder: 1, pin: true, klass: "11", tags: [], msgs: [
                M(o: false, t: "Здравствуйте! Увидела у вас в профиле разбор, хочу так же для своего аккаунта", at: "15:52"),
                M(o: true, t: "Добрый день! Да, конечно. Разбор профиля стоит 5 000 ₽, делаю за два дня", at: "15:58", rx: "❤️"),
                M(o: false, t: "", at: "16:01", kind: "audio", len: 14),
                M(o: false, t: "Вот тетрадь с последней темой", at: "16:03", kind: "image", name: "note"),
                M(o: true, t: "Возьмите её на занятие. Посмотрим, на каком шаге стало непонятно", at: "16:07"),
                M(o: true, t: "", at: "16:09", kind: "round", len: 11, name: "cam"),
                M(o: false, t: "Отлично, а когда можно начать?", at: "16:13")]),
            C(id: "maria", n: "Мария Козлова", h: "@mkozlova", phone: nil, net: "telegram", off: 0, unread: 3, folder: 1, klass: "5", tags: [], msgs: [
                M(o: true, t: "Мария, добрый день! Курс «Старт» стартует 1 декабря, осталось три места", at: "15:20"),
                M(o: false, t: "Здравствуйте! Звучит интересно", at: "15:38"), M(o: false, t: "Сколько стоит?", at: "15:40"), M(o: false, t: "А рассрочка есть?", at: "15:41")]),
            C(id: "maxim", n: "Максим Орлов", h: "max.orlov", phone: nil, net: "instagram", off: 0, unread: 2, folder: 0, klass: "9", tags: [], msgs: [
                M(o: false, t: "Добрый день, подскажите, у вас есть групповые занятия?", at: "13:50"), M(o: false, t: "Для 9 класса", at: "13:51")]),
            C(id: "ivan", n: "Иван Громов", h: "@grom", phone: nil, net: "telegram", off: 0, unread: 0, folder: 1, klass: "7", tags: [], msgs: [
                M(o: false, t: "", at: "12:09", kind: "file", name: "Домашка_геометрия.pdf"), M(o: false, t: "Скинул домашку, посмотрите?", at: "12:10"),
                M(o: true, t: "Получила, посмотрю сегодня вечером", at: "12:27")]),
            C(id: "irina", n: "+7 916 204-18-33", h: nil, phone: "+7 916 204-18-33", net: "whatsapp", off: 0, unread: 3, folder: 0, klass: "9", tags: [], msgs: [
                M(o: false, t: "Привет!", at: "12:19"), M(o: false, t: "", at: "12:20", kind: "audio", len: 9), M(o: false, t: "Хочу заказать разбор профиля", at: "12:21")]),
            C(id: "dmitry", n: "Дмитрий Кузнецов", h: "dkuz", phone: nil, net: "tiktok", off: 0, unread: 1, folder: 0, klass: "11", tags: [], msgs: [
                M(o: false, t: "Здравствуйте, это актуально? Хотел бы попробовать", at: "10:51")]),
            C(id: "artem", n: "Артём Волков", h: "artem.v", phone: nil, net: "threads", off: 0, unread: 3, folder: 0, klass: "5", tags: [], msgs: [
                M(o: false, t: "Классный пост!", at: "07:50"), M(o: false, t: "А можно записаться на пробное?", at: "07:51")]),
            C(id: "natalia", n: "Наталья Фёдорова", h: "id48211", phone: nil, net: "vk", off: -1, unread: 2, folder: 1, klass: "9", tags: [], msgs: [
                M(o: true, t: "Когда вам удобно на следующей неделе?", at: "18:02"), M(o: false, t: "Лучше в четверг вечером", at: "19:40")]),
            C(id: "olga", n: "+7 903 771-52-09", h: nil, phone: "+7 903 771-52-09", net: "max", off: -1, unread: 0, folder: 2, klass: "7", tags: [], msgs: [
                M(o: false, t: "Тетрадь ещё продаётся?", at: "14:12"), M(o: true, t: "Да, ещё продаётся", at: "14:30")]),
            C(id: "egor", n: "Егор Жуков", h: "Егор", phone: nil, net: "avito", off: -4, unread: 0, folder: 4, mute: true, klass: nil, tags: [], msgs: [
                M(o: true, t: "Ссылка на оплату: разбор профиля, 5 000 ₽", at: "11:02"), M(o: false, t: "Спасибо, оплатил", at: "11:40")]),
            C(id: "nikolay", n: "Николай Попов", h: "@npopov", phone: nil, net: "telegram", off: -5, unread: 0, folder: 3, klass: nil, tags: [], msgs: [
                M(o: true, t: "Николай, напоминаю про оплату консультации", at: "10:00"), M(o: false, t: "Да, помню, на неделе переведу", at: "10:41")]),
            C(id: "ksenia", n: "Ксения Лаврова", h: "@ksu_l", phone: nil, net: "telegram", off: -15, unread: 0, folder: 4, arch: true, klass: "11", tags: [], msgs: [
                M(o: false, t: "Спасибо за занятия, курс закончила!", at: "18:20"), M(o: true, t: "Рада была помочь, приходите ещё", at: "18:31")]),
            C(id: "shop", n: "Типография «Лист»", h: "avito", phone: nil, net: "avito", off: -24, unread: 0, folder: 0, mute: true, arch: true, klass: nil, tags: [], msgs: [
                M(o: false, t: "Тетради готовы, можно забирать", at: "11:00")]),
        ]

        var contacts: [Contact] = []
        var convs: [Conversation] = []
        var events: [AppEvent] = []
        var mid = 0
        for (ci, c) in chats.enumerated() {
            var msgs: [Message] = []
            for m in c.msgs {
                mid += 1
                var att: Attachment? = nil
                switch m.kind {
                case "audio": att = Attachment(kind: "audio", name: "voice.ogg", url: "fixture:voice", mediaId: "m\(mid)", mime: "audio/ogg", duration: m.len)
                case "image": att = Attachment(kind: "image", name: "photo.jpg", url: "fixture:" + (m.name ?? "note"), mediaId: "m\(mid)", mime: "image/jpeg")
                case "round": att = Attachment(kind: "video", name: "circle.mp4", url: "fixture:" + (m.name ?? "cam"), mediaId: "m\(mid)", mime: "video/mp4", round: true, duration: m.len)
                case "file": att = Attachment(kind: "file", name: m.name, url: "fixture:file", mediaId: "m\(mid)", mime: "application/pdf")
                default: break
                }
                msgs.append(Message(id: "msg\(mid)", dir: m.o ? "out" : "in", text: m.t, at: at(c.off, m.at), attachments: att.map { [$0] },
                                    reactions: m.rx.map { [Reaction(emoji: $0, mine: false)] }))
            }
            var meta: [String: String] = [:]
            if c.pin { meta["pinned"] = isoString(now) }
            if c.mute { meta["muted"] = "1" }
            if c.arch { meta["archived"] = "1" }
            if c.id == "anna" { meta["pins"] = msgs[4].id }
            var tags = c.tags
            if let k = c.klass { tags.append("класс:" + k) }
            contacts.append(Contact(id: c.id, name: c.n, handle: c.h, source: c.net, networks: [c.net], folderId: folders[c.folder].id,
                                    assignee: "Виктория", note: c.id == "maria" ? "Хочет рассрочку на курс «Старт»" : "", phone: c.phone, tags: tags,
                                    firstContactAt: at(c.off - (ci % 3), "09:00")))
            convs.append(Conversation(id: c.id, contactId: c.id, network: c.net, messages: msgs, older: 0, unread: c.unread, channelId: "ch_" + c.net, meta: meta))
            events.append(AppEvent(id: "lead_" + c.id, type: "lead_created", contactId: c.id, at: at(c.off - (ci % 3), "09:00"), meta: nil))
        }

        // клиенты без переписки в демо (папки и классы, как в макете)
        let extra: [(String, String, Int, Int, String?, [String])] = [
            ("Елена Морозова", "instagram", 0, -1, "7", []), ("Софья Кузнецова", "telegram", 0, -9, "5", ["Математика"]), ("Никита Попов", "whatsapp", 0, -9, "9", ["Физика"]),
            ("Сергей Лебедев", "instagram", 1, -3, "11", []), ("Павел Новиков", "tiktok", 1, -4, "7", []),
            ("Алина Захарова", "instagram", 2, -4, "9", []), ("Юлия Мельникова", "threads", 2, -4, "5", []), ("Кирилл Тихонов", "telegram", 2, -5, "11", []),
            ("Дарья Крылова", "telegram", 2, -6, "7", []), ("Андрей Семёнов", "telegram", 3, -7, "9", []), ("Полина Ковалёва", "tiktok", 3, -8, "5", []),
            ("Мария Павлова", "telegram", 3, -9, "11", ["Математика"]), ("Иван Иванов", "telegram", 4, -8, "9", ["Математика"]),
            ("Полина Фёдорова", "telegram", 4, -9, "7", ["Математика"]), ("Степан Петров", "whatsapp", 4, -9, "11", ["Физика"]),
            ("Екатерина Руденко", "instagram", 4, -1, nil, []), ("Светлана Дроздова", "telegram", 4, -2, nil, []), ("Виктория Ершова", "vk", 3, -3, nil, []),
            ("Анна С.", "whatsapp", 0, -2, nil, []),
        ]
        for (i, e) in extra.enumerated() {
            let id = "x\(i)"
            var tags = e.5
            if let k = e.4 { tags.append("класс:" + k) }
            contacts.append(Contact(id: id, name: e.0, handle: nil, source: e.1, networks: [e.1], folderId: folders[e.2].id, assignee: "Виктория",
                                    tags: tags, firstContactAt: at(e.3, "11:00")))
            if i < 8 { events.append(AppEvent(id: "lead_" + id, type: "lead_created", contactId: id, at: at(e.3, "11:00"), meta: nil)) }
        }
        func cid(_ name: String) -> String { contacts.first { $0.name == name }?.id ?? "anna" }

        // входящие по дням (последние 14 дней)
        let bars = [0, 2, 2, 2, 2, 2, 2, 4, 2, 6, 2, 5, 9, 4]
        for (i, n) in bars.enumerated() where n > 0 {
            for k in 0..<n { events.append(AppEvent(id: "in\(i)_\(k)", type: "message_in", contactId: "anna", at: at(i - 13, String(format: "%02d:%02d", 9 + k, 10)), meta: nil)) }
        }

        let products = [
            Product(id: "p0", name: "Консультация 60 мин", price: 3500), Product(id: "p1", name: "Разбор профиля", price: 5000),
            Product(id: "p2", name: "Курс «Старт»", price: 12900), Product(id: "p3", name: "Менторство 30 дней", price: 24000),
            Product(id: "p4", name: "Математика · 60 мин", price: 1800), Product(id: "p5", name: "Физика · 60 мин", price: 2000),
        ]
        let pays: [(String, String, Int, Double, String, Int?)] = [
            ("Егор Жуков", "p1", -1, 5000, "paid", nil), ("Екатерина Руденко", "p0", -1, 1500, "paid", nil), ("Светлана Дроздова", "p0", -2, 3500, "paid", nil),
            ("Андрей Семёнов", "p0", -3, 3500, "promised", -1), ("Виктория Ершова", "p2", -3, 12900, "promised", 1), ("Николай Попов", "p0", -3, 3500, "promised", -2),
            ("Полина Ковалёва", "p1", -3, 5000, "promised", -1), ("Алина Захарова", "p3", -4, 24000, "promised", 4), ("Мария Павлова", "p3", -6, 24000, "paid", nil),
            ("Анна Соколова", "p2", -7, 12900, "paid", nil), ("Иван Иванов", "p4", -8, 1800, "paid", nil), ("Степан Петров", "p5", -9, 2000, "promised", -4),
        ]
        let deals = pays.enumerated().map { i, p in
            Deal(id: "d\(i)", contactId: cid(p.0), productId: p.1, amount: p.3, status: p.4, date: at(p.2, "12:00"), dueAt: p.5.map { at($0, "12:00") })
        }
        let reminders = [
            Reminder(id: "r0", contactId: "anna", at: at(-7, "10:00"), text: "Уточнить оплату до занятия", done: false),
            Reminder(id: "r1", contactId: "maria", at: at(-2, "10:00"), text: "Прислать рассрочку", done: false),
            Reminder(id: "r2", contactId: "nikolay", at: at(-2, "12:00"), text: "Напомнить об оплате", done: false),
            Reminder(id: "r3", contactId: "artem", at: at(0, "16:00"), text: "Записать на пробное", done: false),
            Reminder(id: "r4", contactId: "natalia", at: at(0, "17:21"), text: "Предложить четверг 18:30", done: false),
        ]
        let templates = ["Пришлю ссылку на оплату", "Свободные окна: чт 18:30, сб 12:00", "Спасибо, записала вас", "Рассрочка есть: три платежа без переплаты"]
            .enumerated().map { Template(id: "t\($0.offset)", title: $0.element, text: $0.element) }
        let team = [
            TeamMember(id: "u1", name: "Виктория", role: "owner", email: "demo@sguardo.ru", permissions: nil),
            TeamMember(id: "u2", name: "Анна Морозова", role: "agent", email: "anna@sguardo.ru",
                       permissions: Permissions(channels: .all, onlyAssigned: false, canPay: true, canExport: false, seeMoney: true)),
        ]

        s.state = AppState(workspace: WorkspaceInfo(currency: "RUB", translate: false), channels: [], folders: folders, contacts: contacts,
                           conversations: convs, products: products, deals: deals, reminders: reminders, events: events, templates: templates, team: team)
        s.user = User(id: "u1", workspaceId: "ws1", email: "demo@sguardo.ru", name: "Виктория", role: "owner", locale: "ru", tz: "Europe/Moscow")
        s.account = AccountInfo(name: "Виктория", email: "demo@sguardo.ru", role: "owner", workspaceName: "Демо-кабинет")
        s.loaded = true
        s.bookAccess = true
        s.contactsOn = true
        s.bookNames = [PhoneBook.key("+7 916 204-18-33"): "Ирина Белова", PhoneBook.key("+7 903 771-52-09"): "Ольга Никитина"]
        s.presence = ["maria": Presence(online: true, lastSeen: nil), "anna": Presence(online: false, lastSeen: at(0, "16:14"))]
        s.scheduled = ["anna": [ScheduledMessage(id: "s1", conversationId: "anna", text: "Напоминаю про занятие завтра в 10:00", sendAt: at(1, "09:00"), status: "pending", error: nil)]]
        s.findings = [PaymentFinding(messageId: "f1", conversationId: "maria", contactId: "maria", amount: 3500, currency: "RUB", payer: "Мария К.",
                                     purpose: "консультация", source: "receipt", duplicateOf: nil)]
        s.suggestions = [LinkSuggestion(aId: "anna", bId: cid("Анна С."), aName: "Анна Соколова", bName: "Анна С.", reason: "Совпадают имя и фамилия")]
        s.notifSeen = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
        s.pushOn = true

        // занятия этой недели: «сегодня» как пятница макета
        let L: [(Int, String, Int, String, String)] = [
            (0, "10:00", 60, "Математика", "Анна Соколова"), (0, "12:30", 90, "Физика", "Иван Громов"), (0, "16:00", 30, "Пробное занятие", "Артём Волков"),
            (0, "18:30", 60, "Математика", "Наталья Фёдорова"), (-4, "11:00", 60, "Физика", "Мария Козлова"), (-3, "17:00", 60, "Математика", "Иван Громов"),
            (-3, "19:00", 60, "Консультация", "Николай Попов"), (-2, "15:00", 60, "Консультация", "Максим Орлов"), (-1, "10:00", 60, "Математика", "Мария Козлова"),
            (-1, "18:00", 60, "Физика", "Дмитрий Кузнецов"), (1, "12:00", 90, "Математика", "Ольга Никитина"),
        ]
        var lessons: [Lesson] = []
        for (i, l) in L.enumerated() {
            let c = cid(l.4)
            let start = parseISO(at(l.0, l.1)) ?? now
            lessons.append(Lesson(id: "l\(i)", conversationId: c, contactId: c, startsAt: isoString(start), endsAt: isoString(start.addingTimeInterval(Double(l.2) * 60)),
                                  status: "planned", seriesId: i == 0 ? "ser1" : nil))
            s.lessonSubject["l\(i)"] = l.3
        }
        s.lessons = lessons
        s.lessonsWeek = Store.monday(of: now)

        s.phase = .ready
        s.tab = .home
        let screen = arg("-screen") ?? "home"
        switch screen {
        case "splash": s.phase = .launching
        case "onboard", "onboard-contacts": s.phase = .onboarding
        case "login", "code": s.phase = .login
        case "home": s.tab = .home
        case "messages": s.tab = .messages
        case "archive": s.tab = .messages; s.showArchiveRow = true; s.messagesPath = [.archive]
        case "messages-archive": s.tab = .messages; s.showArchiveRow = true
        case "clients": s.tab = .clients
        case "payments": s.tab = .payments
        case "more": s.tab = .more
        case "chat", "chatctx", "chatreply", "chattpl", "chatvoice", "chatcircle", "chatselect":
            s.tab = .messages
            s.messagesPath = [.chat(screen == "chatreply" || screen == "chattpl" ? "maria" : "anna")]
            s.demoChatOverlay = ["chatctx": "context", "chatreply": "reply", "chattpl": "templates", "chatvoice": "voice", "chatcircle": "circle", "chatselect": "select"][screen]
        case "profile": s.tab = .messages; s.messagesPath = [.chat("anna"), .profile("anna")]
        case "profile-files": s.tab = .messages; s.messagesPath = [.profile("ivan")]
        case "edit": s.tab = .messages; s.messagesPath = [.profile("irina"), .editContact("irina")]
        case "notifications": s.tab = .home; s.homePath = [.notifications]
        case "schedule": s.tab = .more; s.morePath = [.schedule]
        case "folders": s.tab = .more; s.morePath = [.folders]
        case "lists": s.tab = .more; s.morePath = [.lists]
        case "staff": s.tab = .more; s.morePath = [.account, .staff]
        case "account": s.tab = .more; s.morePath = [.account]
        case "security": s.tab = .more; s.morePath = [.security]
        default: break
        }
        let sheets: [String: SheetKind] = [
            "newpay": .newPay(contactId: nil), "newclient": .newClient, "addlesson": .addLesson(editId: nil), "lesson": .lesson("l0"),
            "invite": .invite, "folder": .folder("f1"), "sched": .schedSend(conv: "anna", text: "Напоминаю про занятие завтра"),
            "attach": .attach(conv: "anna"), "fwd": .forward(conv: "anna", mids: ["msg5"]), "staffrole": .staff("u2"),
        ]
        if let k = sheets[screen] {
            switch screen {
            case "addlesson", "lesson": s.tab = .more; s.morePath = [.schedule]
            case "sched", "attach", "fwd": s.tab = .messages; s.messagesPath = [.chat("anna")]
            case "invite", "staffrole": s.tab = .more; s.morePath = [.account, .staff]
            case "folder": s.tab = .more; s.morePath = [.folders]
            case "newclient": s.tab = .clients
            default: s.tab = .payments
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { s.sheet = k }
        }
    }
}
#endif
