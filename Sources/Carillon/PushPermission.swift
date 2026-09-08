#if canImport(UserNotifications)
  import UserNotifications
#endif

/// OS notification display permission, independent of token registration.
public enum PushPermission: String, Codable {
  /// Notification authorization granted, including temporary App Clip authorization.
  case allowed
  case denied
  /// Provisional authorization for quiet notification delivery.
  case provisional
  /// Notification permission has not been requested.
  case undetermined
}

#if canImport(UserNotifications)
  extension PushPermission {
    /// Maps known refusal and provisional states explicitly. Other states map to allowed;
    /// .ephemeral cannot be referenced in the macOS build used by host tests.
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
