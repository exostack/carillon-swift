import Foundation

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
  public let bundleId: String?
  public let appBuild: String?
  public let osVersion: String?
  /// `allowed`, `denied`, `provisional` or `undetermined`, and nil until the app
  /// has been able to ask iOS. A string rather than a type, for the reason
  /// `environment` is one: this is read in a ticket, not switched on.
  public let pushPermission: String?
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
    case bundleId = "bundle_id"
    case appBuild = "app_build"
    case osVersion = "os_version"
    case pushPermission = "push_permission"
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
      ("bundle_id", bundleId ?? "—"),
      ("app_build", appBuild ?? "—"),
      ("os_version", osVersion ?? "—"),
      ("push_permission", pushPermission ?? "—"),
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
