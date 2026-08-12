#if canImport(UserNotifications)
  import UserNotifications
#endif

/// What iOS will do with a notification for this app.
///
/// One vocabulary for both platforms, defined by the protocol rather than by
/// Apple: Android has no `provisional` and iOS has no way of reporting a single
/// channel switched off, so neither platform's own enumeration would describe
/// the other.
///
/// It is the *display* permission and nothing more. Whether a device can be
/// addressed at all is a question about its token, which it has from its first
/// launch whatever this says — see `requestPushToken()`.
public enum PushPermission: String, Codable {
  /// A notification will be shown. Ephemeral — an App Clip's temporary grant —
  /// belongs here: it is time-limited, not diminished.
  case allowed
  case denied
  /// Apple's quiet delivery: granted without a prompt, and arriving in the
  /// notification centre rather than on the lock screen. Neither allowed nor
  /// denied — the notification reaches the handset and almost nobody sees it.
  case provisional
  /// Nobody has been asked yet. A different fact from having said no, and the
  /// one an onboarding funnel is measured on.
  case undetermined
}

#if canImport(UserNotifications)
  extension PushPermission {
    /// Apple's five states, in our four words.
    ///
    /// `.ephemeral` cannot be named here: Apple marks it unavailable outside
    /// iOS, and this file is compiled by the host toolchain so that the mapping
    /// is exercised without a simulator. It arrives through `default` instead,
    /// which is also where a sixth state Apple has not introduced yet would
    /// land — and `allowed` is the right answer for both, since every status
    /// Apple has ever added that is not a refusal has been a form of yes.
    init(_ status: UNAuthorizationStatus) {
      switch status {
      case .denied: self = .denied
      case .provisional: self = .provisional
      case .notDetermined: self = .undetermined
      default: self = .allowed
      }
    }
  }
#endif
