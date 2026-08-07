#if canImport(UIKit)
  import Foundation
  import UIKit
  import UserNotifications

  /// The two things that need a running iOS app.
  ///
  /// Kept apart from the rest of the facade so that everything else — the state
  /// model, the queue, the retry policy, the profile parse — builds and is tested
  /// without a simulator. That separation is not a testing trick: it is what makes
  /// the protocol logic identical in every environment it runs in.
  extension Carillon {
    /// Asks for permission, then asks APNs for a token.
    ///
    /// Call it whenever the app is ready to ask. The token does not arrive here —
    /// it arrives on the delegate callback the app forwards to
    /// `didRegister(token:)`, which is where registration actually happens.
    @discardableResult
    public static func register(
      options: UNAuthorizationOptions = [.alert, .badge, .sound]
    ) async -> RegistrationOutcome {
      refreshAttributes()

      let center = UNUserNotificationCenter.current()
      let granted = (try? await center.requestAuthorization(options: options)) ?? false

      guard granted else { return .denied }

      // Registration is attempted on simulators too: since Xcode 14, a
      // simulator on an Apple Silicon Mac receives a real sandbox token from
      // APNs, and the callbacks decide the truth — the token arrives on
      // didRegister(token:), or the failure arrives on didFailToRegister(_:),
      // which is also how an unsupported simulator announces itself. Deciding
      // pre-emptively here was a fact from an older world, and it made the SDK
      // the one thing refusing a flow the platform now supports.
      //
      // Registration for remote notifications is a UIApplication call and
      // belongs on the main actor. The token comes back on the delegate.
      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }

      return .registered
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
