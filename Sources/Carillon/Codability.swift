import Foundation

/// Persistence conformances, kept apart from the types they belong to.
///
/// `TagValue` and `PushEnvironment` describe what the server is told; that they
/// also have to survive a cold start is a storage concern, and mixing the two
/// makes the shape of the protocol harder to read than it needs to be.
///
/// `DeviceState` conforms where it is declared, because Swift only synthesises
/// `Codable` for a type in the file that defines it.

extension PushEnvironment: Codable {}

extension TagValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    // Bool before Int, deliberately: a JSON `true` decodes as an integer on some
    // platforms, and a tag that went in as a boolean must not come back as `1`
    // — the customer filters an audience on it.
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case let .string(value): try container.encode(value)
    case let .int(value): try container.encode(value)
    case let .double(value): try container.encode(value)
    case let .bool(value): try container.encode(value)
    }
  }
}
