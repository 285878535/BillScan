import SwiftUI
import Combine
import UserNotifications

@MainActor
final class HealthNotificationRoute: ObservableObject {
    static let shared = HealthNotificationRoute()
    @Published var documentID: UUID?
}

final class HealthNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["documentID"] as? String
        Task { @MainActor in
            if let raw, let id = UUID(uuidString: raw) { HealthNotificationRoute.shared.documentID = id }
            completionHandler()
        }
    }
}
