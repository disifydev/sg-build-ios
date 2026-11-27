import SwiftUI

struct FolderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        SheetBox(title: "Переложить в папку") {
            if store.canRemoveFromFolder(contactId), let base = store.baseFolder {
                SheetOption(icon: "folder.badge.minus", iconColor: Pal.rose, title: "Убрать из «\(store.folder(c?.folderId)?.name ?? "папки")»", subtitle: "вернётся в «\(base.name)»", action: {
                    dismiss()
                    Task { await store.removeFromFolder(contactId) }
                })
            }
            ForEach(store.folders) { f in
                SheetOption(icon: "circle.fill", iconColor: Color(css: f.color), title: f.name, on: c?.folderId == f.id, action: {
                    dismiss()
                    guard c?.folderId != f.id else { return }
                    Task { await store.perform([["type": "move", "contactId": contactId, "folderId": f.id]], contactId: contactId, ok: "Папка «\(f.name)»") }
                }) {
                    if c?.folderId == f.id { Image(systemName: "checkmark").foregroundStyle(Pal.acc) }
                }
            }
        }
    }
}

/// Переложить сразу несколько выбранных чатов (их клиентов) в папку или убрать из папок.
struct BatchFolderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let convIds: Set<String>

    var body: some View {
        let ids: [String] = store.contactIds(of: convIds)
        SheetBox(title: "Переложить в папку", subtitle: "Выбрано: " + ruCount(ids.count, "клиент", "клиента", "клиентов")) {
            if let base = store.baseFolder, ids.contains(where: { store.canRemoveFromFolder($0) }) {
                SheetOption(icon: "folder.badge.minus", iconColor: Pal.rose, title: "Убрать из папок", subtitle: "вернутся в «\(base.name)»", action: {
                    dismiss()
                    store.stopSelecting()
                    Task { await store.removeManyFromFolders(ids) }
                })
            }
            ForEach(store.folders) { f in
                let here: Int = ids.filter { store.contact($0)?.folderId == f.id }.count
                SheetOption(icon: "circle.fill", iconColor: Color(css: f.color), title: f.name, subtitle: here > 0 ? "уже тут: \(here)" : nil, action: {
                    dismiss()
                    store.stopSelecting()
                    Task { await store.moveMany(ids, to: f.id) }
                })
            }
        }
    }
}

struct ReminderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String
    @State private var text = "Написать клиенту"
    @State private var custom = Date().addingTimeInterval(3 * 3600)
    @State private var showCustom = false

    var body: some View {
        let c = store.contact(contactId)
        let existing = store.reminder(for: contactId)
        SheetBox(title: "Напомнить о клиенте", subtitle: c?.name) {
            HStack {
                TextField("", text: $text, prompt: Text("Текст напоминания").foregroundColor(Pal.fg3))
                    .font(Typo.body(15)).foregroundStyle(Pal.fg)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 4).padding(.bottom, 6)
            ForEach(RemPreset.allCases, id: \.self) { p in
                SheetOption(icon: "clock", title: p.title, subtitle: Fmt.whenFull(p.date), action: { save(p.date) })
            }
            SheetOption(icon: "calendar", title: "Выбрать дату и время", action: { withAnimation { showCustom.toggle() } })
            if showCustom {
                DatePicker("", selection: $custom, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Pal.acc)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                Button { save(custom) } label: {
                    Text("Напомнить " + Fmt.whenFull(custom)).font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
                }
                .buttonStyle(PressStyle())
            }
            if let existing {
                Text("Сейчас стоит: \(Fmt.whenFull(existing.date)) — «\(existing.text)»")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3).padding(.horizontal, 12).padding(.top, 8)
                SheetOption(icon: "checkmark.circle", iconColor: Pal.mint, title: "Выполнено", subtitle: "напоминание закроется", action: {
                    dismiss()
                    Task { await store.perform([["type": "doneReminder", "id": existing.id]], contactId: contactId, ok: "Напоминание выполнено") }
                })
                SheetOption(icon: "trash", iconColor: Pal.danger, title: "Удалить напоминание", color: Pal.danger, action: {
                    dismiss()
                    Task { await store.perform([["type": "removeReminder", "id": existing.id]], contactId: contactId, ok: "Напоминание удалено") }
                })
            }
        }
    }

    private func save(_ at: Date) {
        dismiss()
        let t = text.trimmingCharacters(in: .whitespaces)
        var bodies: [[String: Any]] = []
        if let old = store.reminder(for: contactId) { bodies.append(["type": "removeReminder", "id": old.id]) }
        bodies.append(["type": "remind", "contactId": contactId, "at": isoString(at), "text": t.isEmpty ? "Написать клиенту" : t])
        Task { await store.perform(bodies, contactId: contactId, ok: "Напомню " + Fmt.whenFull(at)) }
    }
}

struct TemplatesSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    private let fallback = [
        "Здравствуйте! Спасибо, что написали. Подскажите, что вас интересует?",
        "Отправляю реквизиты для оплаты. После оплаты пришлите, пожалуйста, скрин.",
        "Напоминаю о нашем разговоре — актуально?",
        "Спасибо за оплату! Всё получили.",
    ]

    var body: some View {
        let list = store.state.templates.isEmpty ? fallback.map { ("", $0) } : store.state.templates.map { ($0.title, $0.text) }
        SheetBox(title: "Шаблоны ответов", subtitle: store.state.templates.isEmpty ? "Свои шаблоны заводятся в веб-версии" : nil) {
            ForEach(list.indices, id: \.self) { i in
                Button {
                    dismiss(); onPick(list[i].1)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if !list[i].0.isEmpty { Text(list[i].0).font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc) }
                        Text(list[i].1).font(Typo.body(15)).foregroundStyle(Pal.fg).multilineTextAlignment(.leading).lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

struct AttachSheet: View {
    var canNote = false
    let onPhoto: () -> Void
    let onFile: () -> Void
    let onTemplate: () -> Void
    let onVoice: () -> Void
    let onNote: () -> Void

    var body: some View {
        SheetBox(title: "Прикрепить") {
            SheetOption(icon: "photo", title: "Фото или видео", action: onPhoto)
            SheetOption(icon: "folder", title: "Файл", action: onFile)
            SheetOption(icon: "mic", title: "Голосовое", subtitle: "удерживай микрофон справа от поля", action: onVoice)
            if canNote {
                SheetOption(icon: "video.circle", title: "Кружок", subtitle: "видео в круге до минуты, только Telegram", action: onNote)
            }
            SheetOption(icon: "tag", title: "Шаблон", action: onTemplate)
        }
    }
}

/// «Написать»: только каналы, которые реально есть у клиента.
struct WriteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        let convs = store.conversations(of: contactId)
        let phone = phoneOf(c, convs)
        SheetBox(title: "Написать", subtitle: "Каналы, которые есть у клиента") {
            ForEach(convs) { conv in
                let n = NetInfo.of(conv.network)
                SheetOption(icon: "circle.fill", iconColor: n.color, title: "\(n.name) — в Sguardo", subtitle: c?.handle ?? c?.name, action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.open(.chat(conv.id)) }
                }) { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3) }
            }
            if let phone, convs.contains(where: { $0.network == "whatsapp" }) || c?.phone != nil {
                SheetOption(icon: "arrow.up.right.square", title: "Открыть в WhatsApp", subtitle: phone, action: {
                    if let u = URL(string: "https://wa.me/" + phone.filter(\.isNumber)) { openURL(u) }
                })
            }
            if let h = telegramHandle(c, convs), let u = URL(string: "https://t.me/" + h) {
                SheetOption(icon: "arrow.up.right.square", title: "Открыть в Telegram", subtitle: "@" + h, action: { openURL(u) })
            }
            if let email = c?.email, !email.isEmpty {
                SheetOption(icon: "envelope", title: "Почта", subtitle: email, action: {
                    if let u = URL(string: "mailto:" + email) { openURL(u) }
                }) {
                    Button { UIPasteboard.general.string = email; store.show("Скопировано") } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 15)).foregroundStyle(Pal.fg2).frame(width: 36, height: 36)
                    }
                }
            }
            if (c?.email ?? "").isEmpty {
                Text("Почты и других сетей у клиента нет — добавятся, когда он напишет оттуда")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3).padding(.horizontal, 10).padding(.top, 6)
            }
        }
    }
}

struct CallSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        let convs = store.conversations(of: contactId)
        SheetBox(title: "Позвонить") {
            if let phone = phoneOf(c, convs) {
                Text(phone)
                    .font(Typo.display(24))
                    .foregroundStyle(Pal.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                SheetOption(icon: "phone", title: "Обычный звонок", action: {
                    if let u = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) { openURL(u) }
                })
                SheetOption(icon: "message", title: "Звонок в WhatsApp", subtitle: "откроет чат, там кнопка звонка", action: {
                    if let u = URL(string: "https://wa.me/" + phone.filter(\.isNumber)) { openURL(u) }
                })
                SheetOption(icon: "doc.on.doc", title: "Скопировать номер", action: {
                    UIPasteboard.general.string = phone
                    store.show("Скопировано")
                })
            } else {
                Text("У клиента нет номера телефона — он пишет из \(NetInfo.of(convs.first?.network).name). Можно попросить номер в чате.")
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                if let conv = store.mainConversation(of: contactId) {
                    SheetOption(icon: "bubble.left", title: "Попросить номер в чате", subtitle: "текст встанет в поле ввода, отправишь сама", action: {
                        store.drafts[conv.id] = "Подскажите, пожалуйста, номер телефона — так будет удобнее созвониться."
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.open(.chat(conv.id)) }
                    })
                }
            }
        }
    }
}

struct LabelSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String?
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetBox(title: "Новая метка") {
            HStack(spacing: 8) {
                TextField("", text: $name, prompt: Text("Например: опт").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).foregroundStyle(Pal.fg)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.horizontal, 14).frame(height: 46)
                    .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button(action: add) {
                    Text("Добавить").font(Typo.body(15, .semibold)).padding(.horizontal, 16).frame(height: 46).primaryFill(15)
                }
                .buttonStyle(PressStyle())
            }
            .padding(4)
        }
        .onAppear { focused = true }
    }

    private func add() {
        let v = String(name.trimmingCharacters(in: .whitespaces).prefix(30))
        guard !v.isEmpty else { return }
        store.addLabel(v)
        dismiss()
        if let contactId, let c = store.contact(contactId) {
            var tags = c.tags ?? []
            if !tags.contains(v) { tags.append(v) }
            Task { await store.perform([["type": "updateContact", "contactId": contactId, "tags": tags]], contactId: contactId, ok: "Метка «\(v)» добавлена") }
        } else {
            store.show("Метка «\(v)» добавлена")
        }
    }
}

struct DeleteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sure = false
    @State private var busy = false

    var body: some View {
        SheetBox(title: nil) {
            VStack(spacing: 8) {
                Text("Удалить аккаунт?").font(Typo.display(18)).foregroundStyle(Pal.fg)
                Text(store.user?.isOwner == false
                     ? "Удалим вашу учётную запись сотрудника. Кабинет останется у владельца."
                     : "Удалим кабинет целиком: переписки, клиентов, оплаты и сотрудников. Вернуть будет нельзя.")
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            Button { sure = true } label: {
                ZStack {
                    if busy { ProgressView().tint(Pal.page) } else { Text("Удалить аккаунт").font(Typo.body(16, .semibold)) }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.danger))
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            Button { dismiss() } label: {
                Text("Отмена").font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg).frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(PressStyle())
        }
        .alert("Точно удалить навсегда?", isPresented: $sure) {
            Button("Удалить", role: .destructive) {
                busy = true
                Task {
                    await store.deleteAccount()
                    busy = false
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Это действие нельзя отменить.") }
    }
}

// MARK: - контакты клиента

func phoneOf(_ c: Contact?, _ convs: [Conversation]) -> String? {
    if let p = c?.phone, !p.isEmpty { return p }
    if convs.contains(where: { $0.network == "whatsapp" }), let h = c?.handle, h.filter(\.isNumber).count >= 7 { return h }
    return nil
}

func telegramHandle(_ c: Contact?, _ convs: [Conversation]) -> String? {
    guard convs.contains(where: { $0.network == "telegram" }), var h = c?.handle, !h.isEmpty else { return nil }
    if h.hasPrefix("@") { h.removeFirst() }
    if h.allSatisfy({ $0.isNumber || $0 == "+" }) { return nil }
    if h.contains(" ") { return nil }
    return h
}
