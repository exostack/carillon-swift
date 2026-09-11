import Foundation

/// What survives the app being killed.
///
/// Split by what each fact describes. `UserDefaults` holds what describes an
/// install — state, token, fingerprint, queued events — and travels with a
/// backup. The Keychain, `ThisDeviceOnly`, holds what identifies the installation
/// to the server — the secret and the device id — and never leaves the handset:
/// a backup restored onto another device must not inherit an identity and take
/// over its row.
protocol Store: AnyObject {
  var state: DeviceState? { get set }
  /// The proof of identity sent with every registration. Device-bound.
  var installationSecret: String? { get set }
  /// The id the server returned. Device-bound, and what `deviceId` answers.
  var deviceId: String? { get set }
  /// The fingerprint of the state the server has confirmed. What makes a second
  /// launch with nothing changed cost no call at all.
  var registeredFingerprint: String? { get set }
  var events: [QueuedEvent] { get set }
}

/// One open, waiting to be reported.
struct QueuedEvent: Codable, Equatable {
  /// `opened` is the only type this version produces. It is stored rather than
  /// implied so that the queue a later version inherits from an earlier install
  /// still says what each entry was.
  let type: String
  let deliveryId: String
  let at: Date

  static let opened = "opened"

  func json() -> [String: Any] {
    ["type": type, "delivery_id": deliveryId, "at": ISO8601.string(from: at)]
  }
}

/// The instant format the API reads and writes, fixed to UTC with milliseconds.
///
/// Pinned rather than left to a default: the API validates ISO 8601 and a device
/// in Paris must not report an open in local time with an offset the server then
/// has to guess the intent of.
enum ISO8601 {
  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

    return formatter
  }()

  static func string(from date: Date) -> String {
    formatter.string(from: date)
  }
}

final class UserDefaultsStore: Store {
  private let defaults: UserDefaults
  private let keychain: Keychain
  private let prefix: String

  init(defaults: UserDefaults = .standard, keychain: Keychain, prefix: String = "dev.carillon.") {
    self.defaults = defaults
    self.keychain = keychain
    self.prefix = prefix

    moveToKeychain("installationSecret")
    moveToKeychain("deviceId")
  }

  var state: DeviceState? {
    get { read("state") }
    set { write(newValue, "state") }
  }

  var installationSecret: String? {
    get { keychain.read(prefix + "installationSecret") }
    set { keychain.write(newValue, account: prefix + "installationSecret") }
  }

  var deviceId: String? {
    get { keychain.read(prefix + "deviceId") }
    set { keychain.write(newValue, account: prefix + "deviceId") }
  }

  var registeredFingerprint: String? {
    get { defaults.string(forKey: prefix + "fingerprint") }
    set { defaults.set(newValue, forKey: prefix + "fingerprint") }
  }

  var events: [QueuedEvent] {
    get { read("events") ?? [] }
    set { write(newValue, "events") }
  }

  /// An install upgraded from a version that kept these in `UserDefaults` keeps
  /// its identity. The Keychain wins where both hold a value, and the defaults
  /// entry is dropped only once the Keychain is known to hold one.
  private func moveToKeychain(_ name: String) {
    guard let legacy = defaults.string(forKey: prefix + name) else { return }

    if keychain.read(prefix + name) == nil { keychain.write(legacy, account: prefix + name) }
    if keychain.read(prefix + name) != nil { defaults.removeObject(forKey: prefix + name) }
  }

  private func read<T: Decodable>(_ key: String) -> T? {
    guard let data = defaults.data(forKey: prefix + key) else { return nil }

    // A value this version cannot decode is one an older or newer install
    // wrote. Dropped rather than repaired: the state rebuilds itself on the next
    // registration, and a queue that cannot be read is a queue that can never be
    // sent either.
    return try? JSONDecoder().decode(T.self, from: data)
  }

  private func write<T: Encodable>(_ value: T?, _ key: String) {
    guard let value, let data = try? JSONEncoder().encode(value) else {
      defaults.removeObject(forKey: prefix + key)

      return
    }

    defaults.set(data, forKey: prefix + key)
  }
}

/// The store a test uses, and the one the SDK falls back to before `configure`.
final class MemoryStore: Store {
  var state: DeviceState?
  var installationSecret: String?
  var deviceId: String?
  var registeredFingerprint: String?
  var events: [QueuedEvent] = []
}
