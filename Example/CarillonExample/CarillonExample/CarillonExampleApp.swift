import Carillon
import SwiftUI
import UIKit
import UserNotifications

/// The test bench's entry point, and the whole of the integration.
///
/// Two forwarded callbacks and one `configure`. That is the entire contract: the
/// SDK swizzles nothing, so everything it receives is visible here, in the app's
/// own code, where a developer can read it and a debugger can stop on it.
@main
struct CarillonExampleApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Set before anything else so that a launch from a tap has somewhere to
    // deliver its open to.
    UNUserNotificationCenter.current().delegate = self
    Bench.shared.configureSdk()

    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // The `Data` goes over as it arrived. Hex-encoding is the SDK's job, which is
    // what makes sending `deviceToken.description` — the classic mistake —
    // something this line cannot express.
    Carillon.didRegister(token: deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    Carillon.didFailToRegister(error)
    Bench.shared.log("APNs refused to issue a token: \(error.localizedDescription)")
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let content = response.notification.request.content
    Bench.shared.log("opened: \(content.title) — forwarding to Carillon.didOpen")
    Carillon.didOpen(response)
    completionHandler()
  }

  /// Forwards foreground presentation to the SDK.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let content = notification.request.content
    // The reserved key: a Carillon-sent notification carries its delivery id
    // under `carillon` in the payload. Its presence names the sender; its value
    // is what an opened event proves possession of.
    let stamp = (content.userInfo["carillon"] as? [String: Any])?["delivery_id"] as? String
    Bench.shared.log(
      "willPresent (foreground): \(content.title)"
        + (stamp.map { " — carillon delivery \($0)" } ?? " — no carillon stamp, not ours")
    )
    Carillon.willPresent(notification, completionHandler: completionHandler)
  }
}
