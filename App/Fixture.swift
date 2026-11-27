#if DEBUG
import Foundation

/// Только для снимков симулятора в CI (`-fixture`): выдуманный кабинет без сети. В сборку для TestFlight не попадает.
enum Fixture {
    @MainActor
    static func apply(_ s: Store) {
        let now = Date()
        func ago(_ min: Double) -> String { isoString(now.addingTimeInterval(-min * 60)) }
        let folders: [Folder] = [
            Folder(id: "f_new", key: "new", name: "Новые", color: "#A9D8FF"),
            Folder(id: "f_talking", key: "talking", name: "В диалоге", color: "#DCC6FF"),
            Folder(id: "f_thinking", key: "thinking", name: "Думает", color: "#FFD59E"),
            Folder(id: "f_later", key: "later", name: "Оплатит позже", color: "#FFB8B0"),
            Folder(id: "f_paid", key: "paid", name: "Оплатил", color: "#A8EDCB"),
            Folder(id: "f_repeat", key: "repeat", name: "Повторный клиент", color: "#9EE6E0"),
            Folder(id: "f_rejected", key: "rejected", name: "Отказ", color: "#B9B2B5"),
        ]
        struct P { let name: String; let handle: String; let net: String; let folder: String; let tags: [String]; let phone: String?; let msgs: [(String, String, Double)]; let unread: Int }
        let people: [P] = [
            P(name: "Анна Белова", handle: "annabel", net: "telegram", folder: "f_new", tags: ["VIP"], phone: nil,
              msgs: [("in", "Здравствуйте! Сколько стоит курс?", 50)], unread: 1),
            P(name: "+7 988 473-73-30", handle: "+79884737330", net: "whatsapp", folder: "f_talking", tags: [], phone: "+79884737330",
              msgs: [("in", "Добрый день, можно записаться на четверг?", 300), ("out", "Здравствуйте! Да, в 15:00 свободно", 290), ("in", "Отлично, оплачу завтра", 280)], unread: 0),
            P(name: "On Gayrimenkul", handle: "+905301112233", net: "whatsapp", folder: "f_talking", tags: ["Турция"], phone: "+905301112233",
              msgs: [("out", "Merhaba, On Gayrimenkul! 👋 Google'da firmanızı gördük", 1500)], unread: 0),
            P(name: "Мария Орлова", handle: "m_orlova", net: "telegram", folder: "f_thinking", tags: ["Сайт"], phone: nil,
              msgs: [("out", "Отправила программу и цены", 3000), ("in", "Спасибо, я подумаю до пятницы", 2900)], unread: 0),
            P(name: "Lena Ekicioğlu", handle: "+905551234567", net: "whatsapp", folder: "f_talking", tags: ["Турция"], phone: "+905551234567",
              msgs: [("out", "Merhaba! Sitenizi inceledik", 4000), ("in", "Lena İnşaat ile iletişime geçtiğiniz için teşekkür ederiz", 3990)], unread: 1),
            P(name: "Павел Смирнов", handle: "psmirnov", net: "telegram", folder: "f_paid", tags: ["VIP"], phone: "+79161234567",
              msgs: [("in", "Оплатил, проверьте", 6000), ("out", "Спасибо за оплату! Всё получили.", 5990)], unread: 0),
            P(name: "Emir Yapı", handle: "+905339998877", net: "whatsapp", folder: "f_talking", tags: [], phone: "+905339998877",
              msgs: [("out", "Merhaba, Emir Yapı! 👋", 9000)], unread: 0),
            P(name: "Ольга Тихонова", handle: "olgat", net: "telegram", folder: "f_later", tags: [], phone: nil,
              msgs: [("in", "Скиньте реквизиты, переведу в понедельник", 12000), ("out", "Отправляю реквизиты для оплаты", 11990)], unread: 0),
        ]
        var contacts: [Contact] = [], convs: [Conversation] = [], events: [AppEvent] = []
        for (i, p) in people.enumerated() {
            let cid = "c\(i)", vid = "v\(i)"
            let firstMin = (p.msgs.first?.2 ?? 100) + 60 * 24 * Double(i)
            contacts.append(Contact(id: cid, name: p.name, handle: p.handle, hue: Double((i * 47) % 360), source: p.net, networks: [p.net],
                                    folderId: p.folder, assignee: "", note: i == 3 ? "Хочет групповые занятия" : "", phone: p.phone, email: i == 5 ? "pavel@example.com" : nil,
                                    tags: p.tags, lang: (i == 0 || i == 4) ? "tr" : "ru", avatar: nil, firstContactAt: ago(firstMin)))
            var msgs: [Message] = p.msgs.enumerated().map { j, m in
                Message(id: "m\(i)_\(j)", dir: m.0, text: m.1, at: ago(m.2), author: nil, attachments: nil, translation: nil)
            }
            if i == 0 { msgs = mediaChat(ago) }
            convs.append(Conversation(id: vid, contactId: cid, network: p.net, messages: msgs, older: 0, unread: p.unread, channelId: "ch_\(p.net)"))
            events.append(AppEvent(id: "e\(i)", type: "lead_created", contactId: cid, at: ago(firstMin), meta: nil))
            for (j, m) in p.msgs.enumerated() {
                events.append(AppEvent(id: "e\(i)_\(j)", type: m.0 == "in" ? "message_in" : "message_out", contactId: cid, at: ago(m.2), meta: nil))
            }
        }
        let tomorrow10 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now.addingTimeInterval(86400)) ?? now
        s.state = AppState(
            workspace: WorkspaceInfo(currency: "RUB", translate: true),
            channels: [
                Channel(id: "ch_whatsapp", type: "whatsapp", mode: "qr", name: "WhatsApp +905077748057", status: "connected", error: nil),
                Channel(id: "ch_threads", type: "threads", mode: nil, name: "@disifydev", status: "connected", error: nil),
                Channel(id: "ch_telegram", type: "telegram", mode: "mtproto", name: "@disifydev", status: "connected", error: nil),
            ],
            folders: folders, contacts: contacts, conversations: convs,
            deals: [Deal(id: "d1", contactId: "c5", productId: nil, amount: 5000, status: "paid", date: ago(5990), dueAt: nil)],
            reminders: [
                Reminder(id: "r1", contactId: "c1", at: isoString(tomorrow10), text: "Проверить оплату", done: false),
                Reminder(id: "r2", contactId: "c7", at: ago(120), text: "Напомнить про реквизиты", done: false),
            ],
            events: events,
            templates: [
                Template(id: "t1", title: "Привет", text: "Здравствуйте! Спасибо, что написали. Подскажите, что вас интересует?"),
                Template(id: "t2", title: "Реквизиты", text: "Отправляю реквизиты для оплаты. После оплаты пришлите, пожалуйста, скрин."),
            ])
        s.user = User(id: "u1", workspaceId: "ws1", email: "demo@sguardo.ru", name: "Владелец", role: "owner", locale: "ru", tz: "Europe/Moscow", features: Features(outreach: false, partners: true))
        s.account = AccountInfo(name: "Владелец", email: "demo@sguardo.ru", role: "owner", plan: "business", status: "active", workspaceName: "Мой кабинет", paidUntil: nil, trialEndsAt: nil)
        // новые функции: закрепы, архив, классы, реакции, расписание, сотрудники, найденные оплаты
        for i in s.state.conversations.indices {
            let id = s.state.conversations[i].id
            if id == "v0" { s.state.conversations[i].meta = ["pinned": ago(1), "pins": "m0_4"] }
            if id == "v3" { s.state.conversations[i].meta = ["pinned": ago(2)] }
            if id == "v2" || id == "v6" { s.state.conversations[i].meta = ["archived": "1"] }
            if id == "v4" { s.state.conversations[i].meta = ["muted": "1"] }
        }
        for i in s.state.contacts.indices {
            let c = s.state.contacts[i]
            let extra: [String] = ["c0": ["класс:9", "группа:Мини-группа ЕГЭ"], "c1": ["класс:7"], "c3": ["класс:9"], "c5": ["класс:11", "группа:Мини-группа ЕГЭ"], "c7": ["класс:5"]][c.id] ?? []
            s.state.contacts[i] = Contact(id: c.id, name: c.name, handle: c.handle, hue: c.hue, source: c.source, networks: c.networks, folderId: c.folderId,
                                          assignee: c.assignee, note: c.note, phone: c.phone, email: c.email, tags: (c.tags ?? []) + extra, lang: c.lang,
                                          avatar: c.avatar, firstContactAt: c.firstContactAt)
        }
        if let i = s.state.conversations.firstIndex(where: { $0.id == "v0" }) {
            for j in s.state.conversations[i].messages.indices {
                let mid = s.state.conversations[i].messages[j].id
                if mid == "m0_1" { s.state.conversations[i].messages[j].reactions = [Reaction(emoji: "❤️", mine: false)] }
                if mid == "m0_3" { s.state.conversations[i].messages[j].reactions = [Reaction(emoji: "👍", mine: true)] }
            }
        }
        s.state.team = [
            TeamMember(id: "u1", name: "Владелец", role: "owner", email: "demo@sguardo.ru", permissions: nil),
            TeamMember(id: "u2", name: "Анна Морозова", role: "agent", email: "anna@example.com", permissions: Permissions(onlyAssigned: false, canPay: true, canExport: false, seeMoney: true)),
        ]
        s.presence = ["v0": Presence(online: true, lastSeen: nil)]
        s.scheduled = ["v0": [ScheduledMessage(id: "sch1", conversationId: "v0", text: "Напоминаю про занятие завтра в 10:00", sendAt: isoString(tomorrow10.addingTimeInterval(-3600)), status: "pending", error: nil)]]
        s.findings = [PaymentFinding(messageId: "pf1", conversationId: "v1", contactId: "c1", amount: 3500, currency: "RUB", payer: "Мария К.", purpose: "консультация", source: "receipt", duplicateOf: nil)]
        s.suggestions = [LinkSuggestion(aId: "c5", bId: "c7", aName: "Павел Смирнов", bName: "Ольга Тихонова", reason: "Совпадает номер телефона")]
        s.aiProfiles = ["c5": AIProfile(role: AIField(value: "parent", confidence: 0.9, manual: nil), grade: AIField(value: "11", confidence: 0.5, manual: nil),
                                        lessonType: AIField(value: "group", confidence: 0.8, manual: nil), groupName: nil,
                                        summary: "Мама ученика 11 класса, готовятся к ЕГЭ по математике, удобно по вечерам.")]
        s.bookAccess = true
        s.bookNames = [PhoneBook.key("+79884737330"): "Ирина Белова"]
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func lessonAt(_ day: Int, _ h: Int, _ m: Int, _ mins: Int, _ cid: String, _ conv: String, _ subj: String, _ id: String, series: String? = nil) -> Lesson {
            let st = cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: today) ?? today) ?? now
            s.lessonSubject[id] = subj
            return Lesson(id: id, conversationId: conv, contactId: cid, startsAt: isoString(st), endsAt: isoString(st.addingTimeInterval(Double(mins) * 60)), status: "planned", seriesId: series)
        }
        s.lessons = [
            lessonAt(0, 10, 0, 60, "c0", "v0", "Математика", "l1", series: "s1"),
            lessonAt(0, 12, 30, 90, "c3", "v3", "Физика", "l2"),
            lessonAt(0, 16, 0, 30, "c7", "v7", "Пробное занятие", "l3"),
            lessonAt(0, 18, 30, 60, "c5", "v5", "Математика", "l4", series: "s2"),
            lessonAt(1, 11, 0, 60, "c1", "v1", "Консультация", "l5"),
            lessonAt(-1, 17, 0, 60, "c0", "v0", "Математика", "l6", series: "s1"),
        ]
        s.lessonsWeek = Store.monday(of: now)
        s.phase = ProcessInfo.processInfo.arguments.contains("-login") ? .login : .ready
        if ProcessInfo.processInfo.arguments.contains("-toast") {
            s.toast = Toast(text: "Метка «VIP» снята", ok: true, undo: {})
        }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-wall"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let w = Wall(rawValue: ProcessInfo.processInfo.arguments[i + 1]) { s.wall = w }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-theme"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let t = ThemeMode(rawValue: ProcessInfo.processInfo.arguments[i + 1]) { s.theme = t }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"), i + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "today": s.tab = .today
            case "summary": s.tab = .summary
            case "profile": s.tab = .profile
            case "chat": s.chatsPath = [.chat("v1")]
            case "chat-tr", "chat-tr-sheet": s.chatsPath = [.chat("v4")]
            case "chats-folder": s.chatFolder = "f_talking"
            case "chats-select":
                s.chatSelecting = true
                s.chatSelected = ["v1", "v4", "v6"]
            case "chats-folder-sheet":
                s.chatSelecting = true
                s.chatSelected = ["v1", "v4"]
                s.chatBatchFolderSheet = true
            case "chat-tg", "chat-reply", "chat-voice", "chat-preview", "viewer", "note", "note-rec", "note-lock", "chat-voice-rec": s.chatsPath = [.chat("v0")]
            case "client": s.chatsPath = [.client("c5")]
            case "folders": s.tab = .profile; s.profilePath = [.folders]
            case "partners": s.tab = .profile; s.profilePath = [.partners]
            case "archive": s.chatsPath = [.archive]
            case "schedule": s.tab = .profile; s.profilePath = [.schedule]
            case "lists": s.tab = .profile; s.profilePath = [.lists]
            case "staff": s.tab = .profile; s.profilePath = [.staff]
            case "light": s.theme = .light
            case "chats-light": s.theme = .light
            case "chat-light": s.theme = .light; s.chatsPath = [.chat("v0")]
            case "code": s.phase = .login
            default: break
            }
        }
    }

    /// Переписка с фото, голосовым, ответом и кружком — для снимков чата и просмотрщика.
    static func mediaChat(_ ago: (Double) -> String) -> [Message] {
        let photo = Attachment(kind: "image", name: "Фото", url: "fixture:photo-1", mediaId: nil, mime: "image/jpeg", round: nil)
        let photo2 = Attachment(kind: "image", name: "Фото", url: "fixture:photo-2", mediaId: nil, mime: "image/jpeg", round: nil)
        let voice = Attachment(kind: "audio", name: "Голосовое", url: "fixture:voice", mediaId: nil, mime: "audio/ogg", round: nil)
        let note = Attachment(kind: "video", name: "Кружок", url: "fixture:note", mediaId: nil, mime: "video/mp4", round: true)
        var out: [Message] = []
        out.append(Message(id: "m0_0", dir: "in", text: "Здравствуйте! Сколько стоит курс?", at: ago(95), author: nil, attachments: nil, translation: nil))
        var a = Message(id: "m0_1", dir: "out", text: "Вот программа и расписание", at: ago(90), author: "Вы", attachments: [photo], translation: nil)
        a.externalId = "100:11"
        out.append(a)
        out.append(Message(id: "m0_2", dir: "in", text: "", at: ago(70), author: nil, attachments: [voice], translation: nil))
        out.append(Message(id: "m0_3", dir: "in", text: "А вот так у меня сейчас", at: ago(60), author: nil, attachments: [photo2], translation: nil))
        var r = Message(id: "m0_4", dir: "out", text: "Отлично, с таким уровнем подойдёт продвинутая группа", at: ago(55), author: "Вы", attachments: nil, translation: nil)
        r.replyTo = ReplyRef(id: "m0_3", text: "А вот так у меня сейчас", dir: "in")
        r.externalId = "100:14"
        out.append(r)
        var n = Message(id: "m0_5", dir: "out", text: "", at: ago(52), author: "Вы", attachments: [note], translation: nil)
        n.externalId = "100:15"
        out.append(n)
        // кружок клиента (слева), расшифровка уже пришла с сервера
        let note2 = Attachment(kind: "video", name: "Кружок", url: "fixture:note2", mediaId: nil, mime: "video/mp4", round: true)
        var n2 = Message(id: "m0_5b", dir: "in", text: "", at: ago(51), author: nil, attachments: [note2], translation: nil)
        n2.transcript = Transcript(text: "Вот так я сейчас играю — посмотрите, пожалуйста, руку.", lang: "ru")
        out.append(n2)
        out.append(Message(id: "m0_6", dir: "in", text: "Сколько стоит курс целиком?", at: ago(50), author: nil, attachments: nil, translation: nil))
        // голосовое, расшифровка которого уже пришла с сервера: по «→A» показывается без запроса
        let voice2 = Attachment(kind: "audio", name: "Голосовое", url: "fixture:voice2", mediaId: nil, mime: "audio/ogg", round: nil)
        var v2 = Message(id: "m0_7", dir: "in", text: "", at: ago(48), author: nil, attachments: [voice2], translation: nil)
        v2.transcript = Transcript(text: "И ещё вопрос: в группе сколько человек? Хочу, чтобы было не больше восьми.", lang: "ru")
        out.append(v2)
        return out
    }
}
#endif
