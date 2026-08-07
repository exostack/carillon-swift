import Foundation

/// What `register()` resolved to.
///
/// Three cases and no error: none of them is a failure the caller can retry, and
/// all three are things an app legitimately wants to branch on. A thrown error
/// would make the simulator — the most common one during development — look like
/// a bug in the integration.
public enum RegistrationOutcome: String, Equatable {
  /// Permission granted and a token requested from APNs. The token itself
  /// arrives later, on the delegate callback the app forwards.
  case registered
  /// The person said no. Not an error, and not a state to keep asking about.
  case denied
  /// No APNs token exists on a simulator, so nothing is claimed. Said out loud
  /// rather than reported as success, which would have the developer waiting for
  /// a notification that can never arrive.
  case simulator
}

/// An open, handed to the app.
///
/// The full payload is included because the customer's own keys travel in it and
/// the destination of a tap is theirs to decide. Carillon carries the data and
/// takes no position on what it means.
public struct OpenedNotification {
  public let deliveryId: String
  public let userInfo: [AnyHashable: Any]
  public let openedAt: Date
}

/// One call, one value, made to be pasted into a support ticket.
///
/// The key appears whole. A mobile key ships inside every copy of the app, so
/// anyone holding the binary already has it, and truncating it here would only
/// cost the support engineer the one identifier that tells them which app they
/// are looking at.
public struct DebugInfo: Codable, Equatable {
  public let sdkVersion: String
  public let key: String
  public let endpoint: String
  public let token: String?
  public let deviceId: String?
  public let environment: String
  public let lastRegistrationAt: Date?
  public let lastRegistrationResult: String?
  public let queuedEvents: Int

  enum CodingKeys: String, CodingKey {
    case sdkVersion = "sdk_version"
    case key
    case endpoint
    case token
    case deviceId = "device_id"
    case environment
    case lastRegistrationAt = "last_registration_at"
    case lastRegistrationResult = "last_registration_result"
    case queuedEvents = "queued_events"
  }
}

extension DebugInfo: CustomStringConvertible {
  /// Rendered rather than dumped: this is read by a person, in a ticket, and
  /// `Optional("…")` in every other line is noise they have to see past.
  public var description: String {
    let lines: [(String, String)] = [
      ("sdk_version", sdkVersion),
      ("key", key.isEmpty ? "—" : key),
      ("endpoint", endpoint),
      ("token", token ?? "—"),
      ("device_id", deviceId ?? "—"),
      ("environment", environment),
      ("last_registration_at", lastRegistrationAt.map(ISO8601.string(from:)) ?? "—"),
      ("last_registration_result", lastRegistrationResult ?? "—"),
      ("queued_events", String(queuedEvents)),
    ]

    let width = lines.map(\.0.count).max() ?? 0

    return lines
      .map { "\($0.padding(toLength: width, withPad: " ", startingAt: 0))  \($1)" }
      .joined(separator: "\n")
  }
}
