import Observation
import UIKit
import UserNotifications

/// iOS notifications about watched nodes: the ones the map itself raises while
/// it is open, and the ones the background check raises.
@MainActor
@Observable
final class Notifier: NSObject {
    static let shared = Notifier()

    /// A node the viewer asked for from outside the map (a tapped notification
    /// or widget); the map shows it and clears this.
    var requestedNode: String?

    private nonisolated static let nodeKey = "node"

    /// Before the app has finished launching, so a tap that launched it is not missed.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// The permission as the web's Notification API names it.
    func permission() async -> String {
        Self.webName(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// Asks the viewer, the first time; afterwards answers what they chose.
    func requestPermission() async -> String {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    func isAllowed() async -> Bool {
        await permission() == "granted"
    }

    /// - Parameter tag: notifications with the same tag replace each other, as on the web.
    func post(title: String, body: String, tag: String) async {
        guard await isAllowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(title.prefix(120))
        content.body = String(body.prefix(600))
        content.sound = .default
        if let node = Self.node(fromTag: tag) { content.userInfo = [Self.nodeKey: node] }
        let identifier = tag.isEmpty ? UUID().uuidString : String(tag.prefix(64))
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// The tag of a notification about a node, the same one the map uses.
    static func tag(forNode id: String) -> String { "meshmap-\(id)" }

    static func node(fromTag tag: String) -> String? {
        guard tag.hasPrefix("meshmap-") else { return nil }
        let id = String(tag.dropFirst("meshmap-".count))
        return Shared.isNodeID(id) ? id : nil
    }

    static func webName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: "granted"
        case .denied: "denied"
        case .notDetermined: "default"
        @unknown default: "default"
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// With the app open, a notification is shown all the same: it is what the viewer asked the map for.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let node = response.notification.request.content.userInfo[Self.nodeKey] as? String
        await MainActor.run {
            if let node, Shared.isNodeID(node) { Notifier.shared.requestedNode = node }
        }
    }
}
