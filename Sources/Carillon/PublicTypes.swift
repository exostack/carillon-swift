import Foundation

/// Opened notification with its delivery id, original APNs payload, and tap time.
public struct OpenedNotification {
  public let deliveryId: String
  public let userInfo: [AnyHashable: Any]
  public let openedAt: Date
}

/// Diagnostic snapshot. Includes the full mobile key and device token.
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
  /// allowed, denied, provisional, or undetermined. Nil before iOS settings are read.
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
  /// Formats diagnostics as aligned text; missing values appear as a dash.
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
