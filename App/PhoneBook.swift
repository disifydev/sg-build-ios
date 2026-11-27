import Foundation
import Contacts
import UIKit
import UserNotifications

/// Телефонная книга: имена для номеров WhatsApp и MAX и «Добавить в контакты».
enum PhoneBook {
    static var authorized: Bool {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        if s == .authorized { return true }
        if #available(iOS 18.0, *), s == .limited { return true }
        return false
    }

    static func request(_ done: @escaping @MainActor (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    /// Ключ номера: последние 10 цифр (8 916… и +7 916… совпадают).
    static func key(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        return String(digits.suffix(10))
    }

    static func looksLikePhone(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 7 else { return false }
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-")
        return t.unicodeScalars.allSatisfy { allowed.contains($0) } && t.filter(\.isNumber).count >= 7
    }

    /// Все номера книги → имя (читается в фоне).
    static func loadNames() -> [String: String] {
        guard authorized else { return [:] }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var out: [String: String] = [:]
        let req = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: req) { c, _ in
            var name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if name.isEmpty { name = c.organizationName }
            guard !name.isEmpty else { return }
            for p in c.phoneNumbers {
                let k = key(p.value.stringValue)
                if k.count >= 7 { out[k] = name }
            }
        }
        return out
    }

    /// Новый контакт: имя, номер или ссылка на профиль в соцсети.
    static func save(name: String, phone: String?, network: String?, handle: String?) -> Bool {
        let c = CNMutableContact()
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        c.givenName = parts.first ?? name
        if parts.count > 1 { c.familyName = parts[1] }
        if let phone, !phone.isEmpty {
            c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        if let handle, !handle.isEmpty, !looksLikePhone(handle), let url = profileURL(network: network, handle: handle) {
            c.urlAddresses = [CNLabeledValue(label: Net.name(network), value: url as NSString)]
        }
        c.note = "Клиент Sguardo"
        let req = CNSaveRequest()
        req.add(c, toContainerWithIdentifier: nil)
        do { try CNContactStore().execute(req); return true } catch { return false }
    }

    static func profileURL(network: String?, handle: String) -> String? {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        switch network {
        case "telegram": return "https://t.me/" + h
        case "instagram": return "https://instagram.com/" + h
        case "tiktok": return "https://tiktok.com/@" + h
        case "threads": return "https://threads.net/@" + h
        case "vk": return "https://vk.com/" + h
        default: return nil
        }
    }
}

/// Push (APNs): токен устройства → POST /api/push/device, нажатие на уведомление → чат по полю url.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var store: Store?
    var pendingURL: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Push.delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in self.store?.registerDevice(hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let url = response.notification.request.content.userInfo["url"] as? String
        Task { @MainActor in
            if let url {
                if let store = self.store, store.phase == .ready { store.openURL(url) } else { self.pendingURL = url }
            }
            completionHandler()
        }
    }
}

enum Push {
    static weak var delegate: AppDelegate?

    /// Запросить токен, если уведомления разрешены.
    static func register() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}
