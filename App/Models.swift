import Foundation

// Модели — зеркало src/lib/types.ts бэкенда Sguardo. Поля, без которых экран живёт, — необязательные:
// бэкенд меняется, и приложение не должно падать на новом/пропавшем поле.

struct Folder: Codable, Identifiable, Hashable {
    let id: String
    let key: String?
    var name: String
    var color: String?
}

struct Attachment: Codable, Hashable {
    let kind: String
    let name: String?
    let url: String
    let mediaId: String?
    let mime: String?
    let round: Bool?
}

struct Translation: Codable, Hashable {
    let lang: String?
    let text: String
    let from: String?
}

struct ReplyRef: Codable, Hashable {
    let id: String
    let text: String
    let dir: String?
}

/// Расшифровка голосового/кружка (Groq Whisper на сервере).
struct Transcript: Codable, Hashable {
    let text: String
    let lang: String?
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let dir: String
    let text: String?
    let at: String
    let author: String?
    let attachments: [Attachment]?
    let translation: Translation?
    var replyTo: ReplyRef? = nil
    var externalId: String? = nil
    var authorId: String? = nil
    var transcript: Transcript? = nil
    /// реакции: не больше одной нашей и одной от собеседника (Telegram, WhatsApp)
    var reactions: [Reaction]? = nil

    var isOut: Bool { dir == "out" }
    /// первая ссылка в тексте — для превью
    var firstLink: URL? {
        guard !body.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return det.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))?.url
    }
    var date: Date { parseISO(at) ?? .distantPast }
    var body: String { text ?? "" }

    var preview: String {
        if !body.isEmpty { return body }
        if attachments?.first?.round == true { return "Кружок" }
        switch attachments?.first?.kind {
        case "audio": return "Голосовое сообщение"
        case "image": return "Фото"
        case "video": return "Видео"
        case .some: return "Вложение"
        default: return ""
        }
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let network: String
    var messages: [Message]
    let older: Int?
    var unread: Int
    let channelId: String?
    /// метки диалога: pinned (время закрепа), archived, muted, blocked, pins (закреплённые сообщения), kind=group
    var meta: [String: String]? = nil

    var last: Message? { messages.last }
    var isPinned: Bool { !(meta?["pinned"] ?? "").isEmpty }
    var pinnedAt: String { meta?["pinned"] ?? "" }
    var isArchived: Bool { flag("archived") }
    var isMuted: Bool { flag("muted") }
    var isGroup: Bool { meta?["kind"] == "group" }
    var pins: [String] { (meta?["pins"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty } }
    private func flag(_ k: String) -> Bool {
        guard let v = meta?[k], !v.isEmpty else { return false }
        return v != "0" && v != "false"
    }
}

struct Reaction: Codable, Hashable {
    let emoji: String
    let mine: Bool
}

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let handle: String?
    let hue: Double?
    let source: String?
    let networks: [String]?
    let folderId: String?
    let assignee: String?
    let note: String?
    let phone: String?
    let email: String?
    let tags: [String]?
    let lang: String?
    let avatar: String?
    let firstContactAt: String?

    var first: Date { parseISO(firstContactAt) ?? .distantPast }
    var displayHue: Double { hue ?? Double(stableHash(name)) }
    /// классы репетитора: метки «класс:9»
    var classes: [String] { (tags ?? []).filter { $0.hasPrefix("класс:") }.map { String($0.dropFirst(6)) } }
    /// группы: метки «группа:9 класс»
    var groups: [String] { (tags ?? []).filter { $0.hasPrefix("группа:") }.map { String($0.dropFirst(7)) } }
    /// обычные метки без служебных «класс:» и «группа:»
    var plainTags: [String] { (tags ?? []).filter { !$0.hasPrefix("класс:") && !$0.hasPrefix("группа:") } }
}

/// «9» → «9 класс» (как classTitle на сайте).
func classTitle(_ name: String) -> String {
    if name.count <= 2, Int(name) != nil { return name + " класс" }
    return name
}

struct Deal: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let productId: String?
    let amount: Double
    let status: String
    let date: String
    let dueAt: String?
    var day: Date { parseISO(date) ?? .distantPast }
}

struct Reminder: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let at: String
    let text: String
    let done: Bool
    var date: Date { parseISO(at) ?? .distantPast }
}

struct AppEvent: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let contactId: String
    let at: String
    let meta: String?
    var date: Date { parseISO(at) ?? .distantPast }
}

struct Template: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let mode: String?
    let name: String
    let status: String
    let error: String?
}

struct WorkspaceInfo: Codable, Hashable {
    let currency: String?
    let translate: Bool?
}

struct AppState: Codable {
    var workspace: WorkspaceInfo?
    var channels: [Channel]
    var folders: [Folder]
    var contacts: [Contact]
    var conversations: [Conversation]
    var deals: [Deal]
    var reminders: [Reminder]
    var events: [AppEvent]
    var templates: [Template]
    var products: [Product] = []
    var team: [TeamMember] = []

    static let empty = AppState(workspace: nil, channels: [], folders: [], contacts: [], conversations: [], deals: [], reminders: [], events: [], templates: [])

    init(workspace: WorkspaceInfo?, channels: [Channel], folders: [Folder], contacts: [Contact], conversations: [Conversation],
         deals: [Deal], reminders: [Reminder], events: [AppEvent], templates: [Template], products: [Product] = [], team: [TeamMember] = []) {
        self.workspace = workspace; self.channels = channels; self.folders = folders; self.contacts = contacts
        self.conversations = conversations; self.deals = deals; self.reminders = reminders; self.events = events; self.templates = templates
        self.products = products; self.team = team
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try? c.decodeIfPresent(WorkspaceInfo.self, forKey: .workspace)
        channels = (try? c.decodeIfPresent([Channel].self, forKey: .channels)) ?? []
        folders = (try? c.decodeIfPresent([Folder].self, forKey: .folders)) ?? []
        contacts = (try? c.decodeIfPresent([Contact].self, forKey: .contacts)) ?? []
        conversations = (try? c.decodeIfPresent([Conversation].self, forKey: .conversations)) ?? []
        deals = (try? c.decodeIfPresent([Deal].self, forKey: .deals)) ?? []
        reminders = (try? c.decodeIfPresent([Reminder].self, forKey: .reminders)) ?? []
        events = (try? c.decodeIfPresent([AppEvent].self, forKey: .events)) ?? []
        templates = (try? c.decodeIfPresent([Template].self, forKey: .templates)) ?? []
        products = (try? c.decodeIfPresent([Product].self, forKey: .products)) ?? []
        team = (try? c.decodeIfPresent([TeamMember].self, forKey: .team)) ?? []
    }
}

struct Features: Codable, Hashable {
    let outreach: Bool?
    var partners: Bool? = nil
}

struct Product: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
}

struct Permissions: Codable, Hashable {
    let onlyAssigned: Bool?
    let canPay: Bool?
    let canExport: Bool?
    let seeMoney: Bool?
}

struct TeamMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let email: String?
    let permissions: Permissions?

    /// Роль для показа: владелец или одна из трёх ролей по правам.
    var roleTitle: String {
        if role == "owner" { return "Владелец" }
        guard let p = permissions else { return "Менеджер" }
        if p.onlyAssigned == true && p.canPay != true { return "Только просмотр" }
        if p.canExport == true && p.seeMoney != false { return "Администратор" }
        return "Менеджер"
    }
}

struct PartialState: Codable {
    let conversations: [Conversation]?
    let gone: [String]?
}

struct ScheduledMessage: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let text: String?
    let sendAt: String
    let status: String
    let error: String?
    var date: Date { parseISO(sendAt) ?? .distantFuture }
}

struct ScheduledList: Codable { let items: [ScheduledMessage] }

struct Lesson: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let contactId: String
    let startsAt: String
    let endsAt: String
    let status: String
    let seriesId: String?
    var start: Date { parseISO(startsAt) ?? .distantPast }
    var end: Date { parseISO(endsAt) ?? .distantPast }
    var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

struct LessonsResponse: Codable { let lessons: [Lesson] }

struct PaymentFinding: Codable, Identifiable, Hashable {
    let messageId: String
    let conversationId: String?
    let contactId: String?
    let amount: Double?
    let currency: String?
    let payer: String?
    let purpose: String?
    let source: String?
    let duplicateOf: String?
    var id: String { messageId }
}

struct FindingsResponse: Codable { let items: [PaymentFinding] }

struct LinkSuggestion: Codable, Hashable {
    let aId: String
    let bId: String
    let aName: String?
    let bName: String?
    let reason: String?
}

struct LinkSuggestions: Codable { let items: [LinkSuggestion] }

struct SearchItem: Codable, Identifiable, Hashable {
    let messageId: String
    let conversationId: String
    let name: String?
    let network: String?
    let at: String?
    let snippet: String?
    var id: String { messageId }
}

struct SearchResponse: Codable { let items: [SearchItem] }

struct Presence: Codable, Hashable {
    let online: Bool?
    let lastSeen: String?
}

struct PresenceResponse: Codable { let presence: [String: Presence] }

struct DraftItem: Codable { let text: String }
struct DraftsResponse: Codable { let drafts: [String: DraftItem] }

struct LinkPreview: Codable, Hashable {
    let url: String
    let title: String?
    let description: String?
    let image: String?
    let site: String?
}

struct LinkPreviewResponse: Codable { let preview: LinkPreview? }

/// Поле профиля от ИИ: значение и уверенность («проверьте», если догадка неуверенная).
struct AIField: Codable, Hashable {
    let value: String?
    let confidence: Double?
    let manual: Bool?
}

struct AIProfile: Codable, Hashable {
    let role: AIField?
    let grade: AIField?
    let lessonType: AIField?
    let groupName: AIField?
    let summary: String?
}

struct AIProfiles: Codable { let profiles: [String: AIProfile] }

/// «2026-11-27T18:30» — местное время для /api/schedule.
func localStamp(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
}

func dayStamp(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
}

/// ISO со смещением пояса телефона (sendAt отложенных сообщений).
func isoLocal(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = .current
    return f.string(from: d)
}

struct User: Codable, Hashable {
    let id: String
    let workspaceId: String?
    let email: String
    let name: String
    let role: String
    let locale: String?
    let tz: String?
    let features: Features?
    var isOwner: Bool { role == "owner" }
}

struct StateResponse: Codable {
    let state: AppState
    let user: User?
}

struct ActionResponse: Codable {
    let state: AppState
}

struct MeResponse: Codable {
    let user: User
}

struct HistoryResponse: Codable {
    let messages: [Message]
}

struct AccountInfo: Codable {
    let name: String?
    let email: String?
    let role: String?
    let plan: String?
    let status: String?
    let workspaceName: String?
    let paidUntil: String?
    let trialEndsAt: String?
}

struct UploadResponse: Codable {
    let attachment: Attachment
}

// Рассылка (только кабинет владельца сервиса с флагом features.outreach)
struct OutreachTarget: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String?
    let niche: String?
    let phone: String?
    let site: String?
    let problem: String?
    let rating: Double?
    let reviews: Double?
    let waStatus: String?
    let message: String?
    let status: String
    let sentAt: String?
    let repliedAt: String?
    let contactId: String?
    let error: String?
}

struct OutreachQuota: Codable, Hashable {
    let ok: Bool?
    let reason: String?
    let sentToday: Int?
    let limit: Int?
}

struct OutreachAuto: Codable, Hashable {
    let on: Bool?
    let stopped: String?
    let next: String?
    let left: Int?
}

struct OutreachList: Codable {
    let targets: [OutreachTarget]
    let quota: OutreachQuota?
    let channel: String?
    let auto: OutreachAuto?
    let error: String?
}

// MARK: - даты

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let isoLock = NSLock()
nonisolated(unsafe) private var isoCache: [String: Date] = [:]

/// Разбор ISO-даты с запоминанием: сортировки списков и ленты не разбирают одну строку тысячи раз.
func parseISO(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    isoLock.lock()
    if let d = isoCache[s] { isoLock.unlock(); return d }
    isoLock.unlock()
    guard let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) else { return nil }
    isoLock.lock()
    if isoCache.count > 40000 { isoCache.removeAll(keepingCapacity: true) }
    isoCache[s] = d
    isoLock.unlock()
    return d
}
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

func isoString(_ d: Date) -> String { isoFrac.string(from: d) }
