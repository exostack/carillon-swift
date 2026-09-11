#if canImport(UIKit)
  import Foundation
  import UIKit
  import UserNotifications

  /// UIKit entry points, excluded from host-only builds.
  extension Carillon {
    /// Requests notification permission and returns the current authorization status.
    /// Syncs the result to the server. iOS does not repeat an already answered prompt.
    /// Defaults to alert, badge, and sound authorization.
    @discardableResult
    public static func requestPermission(
      options: UNAuthorizationOptions = [.alert, .badge, .sound]
    ) async -> PushPermission {
      refreshAttributes()

      // The granted flag is deliberately discarded. It says whether the options
      // asked for were granted; the settings say what the system will actually
      // do, which is the thing the server records and the thing a provisional
      // authorisation answers differently.
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: options)

      return await refreshEnvironmentFacts()
    }

    /// Requests an APNs token without requesting notification display permission.
    /// The app must forward success and failure delegate callbacks.
    static func requestPushToken() async {
      // A UIApplication call, and therefore the main actor's.
      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }

    /// Opens the app's notification settings, where a person who answered the
    /// prompt with no can change their mind. Nothing else can show the prompt again.
    public static func openNotificationSettings() {
      Task { @MainActor in
        let path: String
        if #available(iOS 16, *) {
          path = UIApplication.openNotificationSettingsURLString
        } else {
          path = UIApplication.openSettingsURLString
        }

        guard let url = URL(string: path) else { return }

        UIApplication.shared.open(url)
      }
    }

    /// Forward UNUserNotificationCenterDelegate.willPresent without swizzling.
    public static func willPresent(
      _ notification: UNNotification,
      completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      let content = notification.request.content
      completionHandler(willPresent(userInfo: content.userInfo, title: content.title, body: content.body))
    }

    /// Forward application(_:didFailToRegisterForRemoteNotificationsWithError:).
    /// Records the error in debugInfo() and the debug log.
    public static func didFailToRegister(_ error: Error) {
      engine.didFailToRegister(describing: String(describing: error))
    }

    /// Forward userNotificationCenter(_:didReceive:withCompletionHandler:).
    /// Queues an open for the payload delivery id. Ignores notifications without one.
    public static func didOpen(_ response: UNNotificationResponse) {
      engine.didOpen(userInfo: response.notification.request.content.userInfo)
    }
  }
#endif
