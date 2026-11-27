import Foundation

// Модели — зеркало src/lib/types.ts бэкенда Sguardo. Поля, без которых экран живёт, — необязательные:
// бэкенд меняется, и приложение не должно падать на новом или пропавшем поле.

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
    let waveform: [Double]?
    let duration: Double?

    init(kind: String, name: String?, url: String, mediaId: String?, mime: String?, round: Bool? = nil, waveform: [Double]? = nil, duration: Double? = nil) {
        self.kind = kind; self.name = name; self.url = url; self.mediaId = mediaId; self.mime = mime
        self.round = round; self.waveform = waveform; self.duration = duration
    }
}

struct Translation: Codable, Hashable {
    let lang: String?
    let text: String
    let from: String?
}

struct ReplyRef: Codable, Hashable {
    let id: String
    let text: String
    let dir: String
}

struct Reaction: Codable, Hashable {
    let emoji: String
    let mine: Bool
}

struct Transcript: Codable, Hashable {
    let text: String
    let lang: String?
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let dir: String
    var text: String?
    let at: String
    let author: String?
    var attachments: [Attachment]?
    let translation: Translation?
    var replyTo: ReplyRef?
    var reactions: [Reaction]?
    let transcript: Transcript?
    /// только в приложении: ещё не подтверждено сервером
    var pending: Bool?
    var edited: Bool?

    init(id: String, dir: String, text: String?, at: String, author: String? = nil, attachments: [Attachment]? = nil,
         translation: Translation? = nil, replyTo: ReplyRef? = nil, reactions: [Reaction]? = nil, transcript: Transcript? = nil) {
        self.id = id; self.dir = dir; self.text = text; self.at = at; self.author = author; self.attachments = attachments
        self.translation = translation; self.replyTo = replyTo; self.reactions = reactions; self.transcript = transcript
    }

    var isOut: Bool { dir == "out" }
    var date: Date { parseISO(at) ?? .distantPast }
    var body: String { text ?? "" }
    var att: Attachment? { attachments?.first }

    var kind: String {
        guard let a = att else { return "text" }
        if a.kind == "video" && a.round == true { return "round" }
        return a.kind
    }

    var preview: String {
        let a = att
        switch a?.kind {
        case "audio": return body.isEmpty ? "Голосовое сообщение" : body
        case "image": return body.isEmpty ? "Фото" : "Фото, " + body
        case "video": return a?.round == true ? "Видеосообщение" : (body.isEmpty ? "Видео" : "Видео, " + body)
        case .some: return body.isEmpty ? (a?.name ?? "Файл") : body
        default: return body
        }
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let network: String
    var messages: [Message]
    var older: Int?
    var unread: Int
    let channelId: String?
    var meta: [String: String]?

    var last: Message? { messages.last }
    var pinnedAt: Date? { parseISO(meta?["pinned"]) ?? (meta?["pinned"] == "1" ? .distantPast : nil) }
    var isPinned: Bool { (meta?["pinned"] ?? "").isEmpty == false }
    var isArchived: Bool { flag("archived") }
    var isMuted: Bool { flag("muted") }
    var isBlocked: Bool { flag("blocked") }
    var isGroup: Bool { meta?["kind"] == "group" }
    var pins: [String] { (meta?["pins"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty } }

    private func flag(_ k: String) -> Bool {
        guard let v = meta?[k], !v.isEmpty else { return false }
        return v != "0" && v != "false"
    }
}

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let handle: String?
    let hue: Double?
    let source: String?
    let networks: [String]?
    var folderId: String?
    var assignee: String?
    let assigneeId: String?
    var note: String?
    let phone: String?
    let email: String?
    var tags: [String]?
    let lang: String?
    let avatar: String?
    let firstContactAt: String?

    init(id: String, name: String, handle: String?, hue: Double? = nil, source: String?, networks: [String]?, folderId: String?,
         assignee: String? = nil, assigneeId: String? = nil, note: String? = nil, phone: String? = nil, email: String? = nil,
         tags: [String]? = nil, lang: String? = nil, avatar: String? = nil, firstContactAt: String?) {
        self.id = id; self.name = name; self.handle = handle; self.hue = hue; self.source = source; self.networks = networks
        self.folderId = folderId; self.assignee = assignee; self.assigneeId = assigneeId; self.note = note; self.phone = phone
        self.email = email; self.tags = tags; self.lang = lang; self.avatar = avatar; self.firstContactAt = firstContactAt
    }

    var first: Date { parseISO(firstContactAt) ?? .distantPast }
    /// классы репетитора: метки «класс:9»
    var classes: [String] { (tags ?? []).filter { $0.hasPrefix("класс:") }.map { String($0.dropFirst(6)) } }
    /// обычные метки без служебных «класс:» и «группа:»
    var plainTags: [String] { (tags ?? []).filter { !$0.hasPrefix("класс:") && !$0.hasPrefix("группа:") } }
}

func classTitle(_ name: String) -> String {
    if name.count <= 2, Int(name) != nil { return name + " класс" }
    return name
}

struct Product: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
}

struct Deal: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let productId: String?
    let amount: Double
    var status: String
    let date: String
    let dueAt: String?
    var day: Date { parseISO(date) ?? .distantPast }
    var due: Date? { parseISO(dueAt) }
    var isLate: Bool { status == "promised" && (due.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false) }
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

struct Permissions: Codable, Hashable {
    let channels: ChannelsScope?
    let onlyAssigned: Bool?
    let canPay: Bool?
    let canExport: Bool?
    let seeMoney: Bool?
}

/// channels: "all" или список id
enum ChannelsScope: Codable, Hashable {
    case all, list([String])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), s == "all" { self = .all; return }
        self = .list((try? c.decode([String].self)) ?? [])
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .all: try c.encode("all")
        case .list(let l): try c.encode(l)
        }
    }
}

struct TeamMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let email: String?
    let permissions: Permissions?

    /// Роль для показа: владелец или одна из трёх ролей приложения по правам.
    var roleTitle: String {
        if role == "owner" { return "Владелец" }
        guard let p = permissions else { return "Менеджер" }
        if p.onlyAssigned == true && p.canPay != true { return "Только просмотр" }
        if p.canExport == true && p.seeMoney != false { return "Администратор" }
        return "Менеджер"
    }
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
    var products: [Product]
    var deals: [Deal]
    var reminders: [Reminder]
    var events: [AppEvent]
    var templates: [Template]
    var team: [TeamMember]

    static let empty = AppState(workspace: nil, channels: [], folders: [], contacts: [], conversations: [], products: [], deals: [],
                                reminders: [], events: [], templates: [], team: [])

    init(workspace: WorkspaceInfo?, channels: [Channel], folders: [Folder], contacts: [Contact], conversations: [Conversation],
         products: [Product], deals: [Deal], reminders: [Reminder], events: [AppEvent], templates: [Template], team: [TeamMember]) {
        self.workspace = workspace; self.channels = channels; self.folders = folders; self.contacts = contacts
        self.conversations = conversations; self.products = products; self.deals = deals; self.reminders = reminders
        self.events = events; self.templates = templates; self.team = team
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try? c.decodeIfPresent(WorkspaceInfo.self, forKey: .workspace)
        channels = (try? c.decodeIfPresent([Channel].self, forKey: .channels)) ?? []
        folders = (try? c.decodeIfPresent([Folder].self, forKey: .folders)) ?? []
        contacts = (try? c.decodeIfPresent([Contact].self, forKey: .contacts)) ?? []
        conversations = (try? c.decodeIfPresent([Conversation].self, forKey: .conversations)) ?? []
        products = (try? c.decodeIfPresent([Product].self, forKey: .products)) ?? []
        deals = (try? c.decodeIfPresent([Deal].self, forKey: .deals)) ?? []
        reminders = (try? c.decodeIfPresent([Reminder].self, forKey: .reminders)) ?? []
        events = (try? c.decodeIfPresent([AppEvent].self, forKey: .events)) ?? []
        templates = (try? c.decodeIfPresent([Template].self, forKey: .templates)) ?? []
        team = (try? c.decodeIfPresent([TeamMember].self, forKey: .team)) ?? []
    }
}

struct User: Codable, Hashable {
    let id: String
    let workspaceId: String?
    let email: String
    let name: String
    let role: String
    let locale: String?
    let tz: String?
    var isOwner: Bool { role == "owner" }
}

struct StateResponse: Codable {
    let state: AppState
    let user: User?
}

struct PartialState: Codable {
    let partial: Bool?
    let conversations: [Conversation]?
    let gone: [String]?
}

struct ActionResponse: Codable {
    let state: AppState
}

struct MeResponse: Codable {
    let user: User
}

struct HistoryResponse: Codable {
    let messages: [Message]
    let hasMore: Bool?
}

struct AccountInfo: Codable {
    let name: String?
    let email: String?
    let role: String?
    let workspaceName: String?
}

struct UploadResponse: Codable {
    let attachment: Attachment
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

struct ScheduledList: Codable {
    let items: [ScheduledMessage]
}

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

struct LessonsResponse: Codable {
    let lessons: [Lesson]
}

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

struct FindingsResponse: Codable {
    let items: [PaymentFinding]
}

struct LinkSuggestion: Codable, Hashable {
    let aId: String
    let bId: String
    let aName: String?
    let bName: String?
    let reason: String?
}

struct LinkSuggestions: Codable {
    let items: [LinkSuggestion]
}

struct SearchItem: Codable, Identifiable, Hashable {
    let messageId: String
    let conversationId: String
    let contactId: String?
    let name: String?
    let network: String?
    let dir: String?
    let at: String?
    let snippet: String?
    var id: String { messageId }
}

struct SearchResponse: Codable {
    let items: [SearchItem]
}

struct Presence: Codable, Hashable {
    let online: Bool?
    let lastSeen: String?
}

struct PresenceResponse: Codable {
    let presence: [String: Presence]
}

struct DraftItem: Codable {
    let text: String
}

struct DraftsResponse: Codable {
    let drafts: [String: DraftItem]
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

func parseISO(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

func isoString(_ d: Date) -> String { isoFrac.string(from: d) }

/// ISO со смещением пояса телефона (для sendAt отложенных сообщений).
func isoLocal(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = .current
    return f.string(from: d)
}

/// «2026-11-27T18:30» — местное время для /api/schedule.
func localStamp(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
}

func dayStamp(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
}
