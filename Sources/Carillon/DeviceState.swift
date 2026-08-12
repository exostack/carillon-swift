import Foundation

/// A tag value, as the API defines it: a flat scalar and nothing else.
///
/// The literal conformances are what keep the customer's call site readable —
/// `setTags(["plan": "pro", "seats": 5, "beta": true])` compiles as written. A
/// dictionary of `Any` would read the same and fail at runtime on the first
/// nested value; the API refuses those, and refusing them at the call site is
/// the difference between a compiler message and a 422 in production.
public enum TagValue: Hashable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)

  var json: Any {
    switch self {
    case let .string(value): return value
    case let .int(value): return value
    case let .double(value): return value
    case let .bool(value): return value
    }
  }
}

extension TagValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}

extension TagValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self = .int(value) }
}

extension TagValue: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) { self = .double(value) }
}

extension TagValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Everything the server is told about this device.
///
/// One value, held whole, sent whole. The protocol makes the SDK the canonical
/// holder of this state and the registration call a replacement rather than a
/// patch — which is what makes re-registration free, and what makes an app that
/// has been offline for a week correct again with one call rather than several.
struct DeviceState: Equatable, Codable {
  /// Absent until APNs hands one over. Nothing is sent before it exists: a
  /// registration without a token names no device.
  var token: String?
  var environment: PushEnvironment = .production
  var externalId: String?
  var tags: [String: TagValue] = [:]
  var timezoneId: String?
  var locale: String?
  var appVersion: String?
  /// `CFBundleVersion` — the build behind the marketing version, which several
  /// builds share.
  var appBuild: String?
  var bundleId: String?
  /// `UIDevice.current.systemVersion`, verbatim. Never normalised here.
  var osVersion: String?
  /// Absent until the app has been able to ask iOS, which is asynchronous.
  var pushPermission: PushPermission?
  var sdkVersion: String?
  var optedIn: Bool = true

  static let platform = "ios"

  /// The body of `POST /v1/devices`.
  ///
  /// Every field is present on every call, including the null ones, and that is
  /// deliberate on both sides: the server reads an absent field as "unchanged"
  /// and an explicit null as "erase". Since this SDK holds the whole truth about
  /// the device, sending the whole truth is the only description that stays
  /// correct — `clearIdentity()` has to reach the server as a null, and it can
  /// only do that if nulls are sent.
  func registrationBody() -> [String: Any] {
    [
      "token": token ?? "",
      "platform": DeviceState.platform,
      "environment": environment.rawValue,
      "external_id": externalId ?? NSNull(),
      "tags": tags.mapValues(\.json),
      "timezone_id": timezoneId ?? NSNull(),
      "locale": locale ?? NSNull(),
      "app_version": appVersion ?? NSNull(),
      "app_build": appBuild ?? NSNull(),
      "bundle_id": bundleId ?? NSNull(),
      "os_version": osVersion ?? NSNull(),
      "push_permission": pushPermission?.rawValue ?? NSNull(),
      "sdk_version": sdkVersion ?? NSNull(),
      "opted_in": optedIn,
    ]
  }

  /// What "the server already knows this" means.
  ///
  /// Compared as the serialised body rather than field by field: the question is
  /// whether another call would tell the server anything new, and the body is
  /// exactly that question. A field added to the table later is covered without
  /// anyone remembering to extend a comparison — which is why turning
  /// notifications off in Settings, or updating iOS, is by itself a reason to
  /// re-register: the body changes, so the fingerprint does.
  func fingerprint() -> String {
    guard let data = JSON.encode(registrationBody()) else { return UUID().uuidString }

    return String(decoding: data, as: UTF8.self)
  }
}

/// One encoder, with sorted keys, used everywhere a body is built.
///
/// Sorted because the fingerprint above compares serialised bodies, and a
/// dictionary that serialises in a different order on the next launch would make
/// every cold start look like a change and re-register the whole park.
enum JSON {
  static func encode(_ object: Any) -> Data? {
    try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}
