#if canImport(UserNotifications)
  import Foundation
  import UserNotifications

  /// Notification-center facts and forwards that need no UIKit, so the host
  /// suite can exercise them and a bridge can call them with a payload it
  /// already holds.
  extension Carillon {
    /// Replaced by tests; the app reads the real notification settings.
    static var authorizationStatus: () async -> UNAuthorizationStatus = {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Replaced by tests; the app clears the real Notification Center.
    static var removeAllDeliveredNotifications: () -> Void = {
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Reads the current notification permission without prompting and syncs it to the server.
    public static func getPermission() async -> PushPermission {
      await refreshEnvironmentFacts()
    }

    /// True while the system prompt has never been shown, which is the only time
    /// `requestPermission()` displays anything.
    public static func canRequestPermission() async -> Bool {
      await getPermission() == .undetermined
    }

    /// Reads OS version and notification settings asynchronously.
    /// Refreshing at launch picks up permission changes made in Settings.
    @discardableResult
    static func refreshEnvironmentFacts() async -> PushPermission {
      let version = await currentOSVersion()
      let permission = PushPermission(await authorizationStatus())

      engine.refreshOperatingSystem(osVersion: version, pushPermission: permission)

      return permission
    }

    /// Runs the `onReceived` decision for a foreground notification payload and
    /// returns the presentation options to hand back to the system. For hosts
    /// whose notification-center delegate belongs to another library.
    public static func willPresent(userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
      let alert = (userInfo["aps"] as? [String: Any])?["alert"]
      let fields = alert as? [String: Any]

      return willPresent(
        userInfo: userInfo,
        title: fields?["title"] as? String,
        body: fields?["body"] as? String ?? alert as? String
      )
    }

    static func willPresent(
      userInfo: [AnyHashable: Any], title: String?, body: String?
    ) -> UNNotificationPresentationOptions {
      let received = ReceivedNotification(userInfo: userInfo, title: title, body: body)
      let decision = onReceived?(received) ?? .show

      return decision == .show ? [.banner, .list, .sound, .badge] : []
    }

    /// Removes notifications currently displayed by this app.
    public static func clearNotifications() {
      removeAllDeliveredNotifications()
    }
  }
#endif
