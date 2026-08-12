#if canImport(UIKit)
  import Foundation
  import UIKit
  import UserNotifications

  /// The parts that need a running iOS app.
  ///
  /// Kept apart from the rest of the facade so that everything else — the state
  /// model, the queue, the retry policy, the profile parse — builds and is tested
  /// without a simulator. That separation is not a testing trick: it is what makes
  /// the protocol logic identical in every environment it runs in.
  extension Carillon {
    /// Shows the system prompt, and answers with what the person decided.
    ///
    /// One question, one answer. It does not register the device — `configure`
    /// already did, silently, and this handset has been in the customer's base
    /// since its first launch. What changes here is whether anything will be
    /// displayed, and the new permission reaches the server by itself: it is
    /// part of the state, so it is part of the fingerprint, so the next pass of
    /// the registration loop sends it.
    ///
    /// Callable from anywhere — `UNUserNotificationCenter` needs no activity, no
    /// window and no main actor. Android is not so lucky, and its equivalent
    /// takes an `Activity`.
    ///
    /// Asking twice shows nothing the second time: iOS answers a repeat request
    /// from the record instead of prompting, which is why this can be called
    /// wherever it reads best without guarding it.
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

    /// Asks APNs for a token, without asking the person for anything.
    ///
    /// **A push token is transport addressing, not consent.** iOS hands one to
    /// `registerForRemoteNotifications()` whether or not notifications have ever
    /// been authorised — the authorisation gates *display*. So the device row
    /// exists from the first launch, carrying whatever permission is really in
    /// force, and a customer's base is every install rather than the subset that
    /// happened to say yes on the day someone remembered to ask.
    ///
    /// The token does not arrive here. It arrives on the delegate callback the
    /// app forwards to `didRegister(token:)`, and the registration loop absorbs
    /// the delay exactly as it absorbs a device that starts up offline.
    ///
    /// Attempted on simulators too: since Xcode 14, a simulator on an Apple
    /// Silicon Mac receives a real sandbox token, and the callbacks decide the
    /// truth — the token on `didRegister(token:)`, the refusal on
    /// `didFailToRegister(_:)`, which is also how an unsupported host announces
    /// itself.
    static func requestPushToken() async {
      // A UIApplication call, and therefore the main actor's.
      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }

    /// The OS version and what iOS will do with a notification for this app.
    ///
    /// Both are read here rather than beside the other attributes because
    /// neither answers on the spot: `UIDevice` is bound to the main actor, and
    /// notification settings arrive asynchronously. Refreshed on every
    /// registration path, which is what makes a permission revoked in Settings
    /// — an act the app cannot observe while it is not running — reach the
    /// server at the next launch.
    @discardableResult
    static func refreshEnvironmentFacts() async -> PushPermission {
      let version = await MainActor.run { UIDevice.current.systemVersion }
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      let permission = PushPermission(settings.authorizationStatus)

      engine.refreshOperatingSystem(osVersion: version, pushPermission: permission)

      return permission
    }

    /// Forwarded from
    /// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    ///
    /// Recorded for `debugInfo()` and the debug log — a developer whose token
    /// never arrives needs the platform's own words for why, not a silence.
    /// On simulators this is where an Intel Mac's "unsupported" lands.
    public static func didFailToRegister(_ error: Error) {
      engine.didFailToRegister(describing: String(describing: error))
    }

    /// Forwarded from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    ///
    /// Reads `carillon.delivery_id` out of the payload and queues an open.
    /// Possession of that id is the proof of receipt: it is unguessable and it
    /// travelled inside this one notification, which is what makes an open rate
    /// something that cannot be manufactured.
    ///
    /// Forward every response. A notification that is not ours carries no such
    /// key and is ignored, so the app does not have to work out which is which.
    public static func didOpen(_ response: UNNotificationResponse) {
      engine.didOpen(userInfo: response.notification.request.content.userInfo)
    }
  }
#endif
