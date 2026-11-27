import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Материалы переписки в карточке клиента, как в Telegram: Медиа · Файлы · Ссылки · Голосовые.
/// Медиа — фото и видео без кружков; Файлы — только документы; Голосовые — голосовые и кружки.
struct ClientMaterials: View {
    @Environment(Store.self) private var store
    let contactId: String
    @State private var tab = "media"
    @State private var viewer: ViewerState?
    @State private var previewURL: URL?
    @State private var loadingFile: String?

    private struct Entry: Identifiable {
        let id: String
        let message: Message
        let index: Int
        let att: Attachment
        var date: Date { message.date }
    }

    private struct LinkEntry: Identifiable {
        let id: String
        let url: URL
        let message: Message
    }

    private var messages: [Message] {
        store.conversations(of: contactId).flatMap { store.messages($0.id) }.sorted { $0.date > $1.date }
    }

    private func entries(_ keep: (Attachment) -> Bool) -> [Entry] {
        var out: [Entry] = []
        for m in messages {
            for (i, a) in (m.attachments ?? []).enumerated() where keep(a) {
                out.append(Entry(id: m.id + "#\(i)", message: m, index: i, att: a))
            }
        }
        return out
    }

    private var media: [Entry] { entries { ($0.kind == "image" || $0.kind == "video") && $0.round != true } }
    private var files: [Entry] { entries { $0.kind != "image" && $0.kind != "video" && $0.kind != "audio" } }
    private var voices: [Entry] { entries { $0.kind == "audio" || $0.round == true } }
    private var links: [LinkEntry] {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var out: [LinkEntry] = []
        var seen = Set<String>()
        for m in messages where !m.body.isEmpty {
            let ns = m.body as NSString
            for r in det.matches(in: m.body, range: NSRange(location: 0, length: ns.length)) {
                guard let u = r.url, u.scheme == "http" || u.scheme == "https", seen.insert(u.absoluteString).inserted else { continue }
                out.append(LinkEntry(id: m.id + "|" + u.absoluteString, url: u, message: m))
            }
        }
        return out
    }

    var body: some View {
        let m = media, f = files, l = links, v = voices
        VStack(alignment: .leading, spacing: 0) {
            Cap("Материалы")
            GlassSegment(items: [("media", "Медиа"), ("files", "Файлы"), ("links", "Ссылки"), ("voice", "Голосовые")], selection: $tab)
            Group {
                switch tab {
                case "files": filesList(f)
                case "links": linksList(l)
                case "voice": voicesList(v)
                default: mediaGrid(m)
                }
            }
            .padding(.top, 10)
        }
        .fullScreenCover(item: $viewer) { v in
            MediaViewer(items: v.items, start: v.start) { viewer = nil }.environment(store)
        }
        .quickLookPreview($previewURL)
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-mtab"), i + 1 < args.count { tab = args[i + 1] }
            #endif
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Typo.body(14)).foregroundStyle(Pal.fg2)
            .frame(maxWidth: .infinity, minHeight: 64)
            .glassRect(24)
    }

    private func item(_ e: Entry) -> MediaItem {
        MediaItem(id: e.id, raw: e.att.url, kind: e.att.kind, name: e.att.name ?? "", round: e.att.round == true, mime: e.att.mime)
    }

    private func open(_ list: [Entry], _ e: Entry) {
        let items = list.filter { $0.att.kind == "image" || $0.att.kind == "video" }.map(item)
        guard let start = items.firstIndex(where: { $0.id == e.id }) else { return }
        viewer = ViewerState(items: items, start: start)
    }

    // MARK: Медиа

    @ViewBuilder private func mediaGrid(_ list: [Entry]) -> some View {
        if list.isEmpty { empty("Фото и видео из переписки появятся здесь") } else {
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(list.prefix(60)) { e in
                    Button { open(list, e) } label: {
                        ZStack {
                            if e.att.kind == "image" {
                                RemoteImage(raw: e.att.url)
                            } else {
                                LinearGradient(colors: [Pal.sky.opacity(0.4), Pal.lav.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(Pal.fg)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(e.att.kind == "image" ? "Фото" : "Видео")
                }
            }
        }
    }

    // MARK: Файлы

    @ViewBuilder private func filesList(_ list: [Entry]) -> some View {
        if list.isEmpty { empty("Документов пока нет") } else {
            VStack(spacing: 0) {
                ForEach(Array(list.prefix(100).enumerated()), id: \.element.id) { i, e in
                    Button { Task { await openFile(e) } } label: {
                        GroupRow(first: i == 0) {
                            RowIcon(system: "doc.fill", color: Pal.sky)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.att.name ?? "Файл").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg).lineLimit(1)
                                Text(Fmt.whenFull(e.date)).font(Typo.body(12)).foregroundStyle(Pal.fg2)
                            }
                            Spacer(minLength: 0)
                            if loadingFile == e.id { ProgressView() }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .glassRect(24)
        }
    }

    private func openFile(_ e: Entry) async {
        guard let url = API.media(e.att.url) else { return }
        loadingFile = e.id
        defer { loadingFile = nil }
        do {
            let data = try await API.download(url)
            var name = (e.att.name ?? "file").replacingOccurrences(of: "/", with: "_")
            if (name as NSString).pathExtension.isEmpty, let mime = e.att.mime, let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
                name += "." + ext
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + name)
            try data.write(to: dest)
            previewURL = dest
        } catch {
            store.show("Не удалось открыть файл", ok: false)
        }
    }

    // MARK: Ссылки

    @ViewBuilder private func linksList(_ list: [LinkEntry]) -> some View {
        if list.isEmpty { empty("Ссылок в переписке пока нет") } else {
            VStack(spacing: 0) {
                ForEach(Array(list.prefix(100).enumerated()), id: \.element.id) { i, e in
                    Button { UIApplication.shared.open(e.url) } label: {
                        GroupRow(first: i == 0) {
                            RowIcon(system: "link", color: Pal.mint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.url.host ?? e.url.absoluteString).font(Typo.body(15, .medium)).foregroundStyle(Pal.fg).lineLimit(1)
                                Text(e.url.absoluteString).font(Typo.body(12)).foregroundStyle(Pal.fg2).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .glassRect(24)
        }
    }

    // MARK: Голосовые и кружки

    @ViewBuilder private func voicesList(_ list: [Entry]) -> some View {
        if list.isEmpty { empty("Голосовых и кружков пока нет") } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(list.prefix(60)) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text((e.message.isOut ? "Вы · " : "Клиент · ") + Fmt.whenFull(e.date))
                            .font(Typo.body(12)).foregroundStyle(Pal.fg2)
                        if e.att.round == true {
                            Button { open(list, e) } label: {
                                HStack(spacing: 10) {
                                    RowIcon(system: "video.circle.fill", color: Pal.lav)
                                    Text("Кружок").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg)
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(Pal.fg2)
                                }
                                .padding(.horizontal, 14).frame(height: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .glassRect(20)
                        } else {
                            AudioBubble(url: API.media(e.att.url), raw: e.att.url, out: e.message.isOut, message: e.message, showTime: false, mime: e.att.mime)
                        }
                    }
                }
            }
        }
    }
}
