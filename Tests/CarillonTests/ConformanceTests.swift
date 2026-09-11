import XCTest

@testable import Carillon

/// Vectors every Carillon SDK has to satisfy, in any language.
///
/// The bodies in `Tests/ConformanceFixtures` are not a second description of the
/// protocol — they are the output of the same functions the tests above assert,
/// written down. That is what makes them worth replaying: the Kotlin SDK reading
/// `registration.json` is comparing itself against what iOS actually sends,
/// rather than against a document either of them could have drifted from.
///
/// They are deliberately free of anything language-specific: a case is a state
/// expressed in the API's own field names, and the request it must produce. To
/// regenerate after a deliberate change:
///
///     CARILLON_WRITE_FIXTURES=1 swift test
///
/// and read the diff. A change nobody meant to make shows up as a failing test.
final class ConformanceTests: XCTestCase {
  private var directory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("ConformanceFixtures")
  }

  private var rewriting: Bool {
    ProcessInfo.processInfo.environment["CARILLON_WRITE_FIXTURES"] == "1"
  }

  // MARK: - Registration

  func testRegistrationVectors() throws {
    let document = registrationDocument()

    try check(document, named: "registration.json") { rawCase in
      let given = rawCase["given"] as? [String: Any] ?? [:]

      return state(from: given).registrationBody()
    }
  }

  /// The states worth pinning: the ones where a field means something other than
  /// its own value.
  private func registrationDocument() -> [String: Any] {
    let token = String(repeating: "ab", count: 32)

    let cases: [[String: Any]] = [
      [
        "name": "every field the table carries",
        "given": [
          "token": token,
          "environment": "sandbox",
          "external_id": "user-42",
          "tags": ["plan": "pro", "seats": 5, "beta": true, "ratio": 1.5],
          "timezone_id": "Europe/Paris",
          "locale": "fr-FR",
          "app_version": "1.4.2",
          "app_build": "4271",
          "bundle_id": "com.example.app",
          "os_version": "18.5",
          "push_permission": "allowed",
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
      [
        "name": "a device that has only just registered",
        "note":
          "Nothing but a token. Every other field is sent as null rather than omitted, because the server reads an absent field as unchanged.",
        "given": [
          "token": token,
          "environment": "production",
          "external_id": NSNull(),
          "tags": [:],
          "timezone_id": NSNull(),
          "locale": NSNull(),
          "app_version": NSNull(),
          "app_build": NSNull(),
          "bundle_id": NSNull(),
          "os_version": NSNull(),
          "push_permission": NSNull(),
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
      [
        "name": "an identity that has been cleared",
        "note":
          "external_id must travel as an explicit null. Omitting it would leave the previous identifier in place for ever, with nothing failing to say so.",
        "given": [
          "token": token,
          "environment": "sandbox",
          "external_id": NSNull(),
          "tags": ["plan": "pro"],
          "timezone_id": "Europe/Paris",
          "locale": "fr-FR",
          "app_version": "1.4.2",
          "app_build": "4271",
          "bundle_id": "com.example.app",
          "os_version": "18.5",
          "push_permission": "allowed",
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
      [
        "name": "a device that has opted out",
        "note": "The row stays and stays reachable: opting out is a state, not a deletion.",
        "given": [
          "token": token,
          "environment": "production",
          "external_id": "user-42",
          "tags": [:],
          "timezone_id": "America/New_York",
          "locale": "en-US",
          "app_version": "2.0.0",
          "app_build": "980",
          "bundle_id": "com.example.app",
          "os_version": "18.5",
          "push_permission": "allowed",
          "sdk_version": "0.2.0",
          "opted_in": false,
        ],
      ],
      [
        "name": "a handset whose notifications were turned off in Settings",
        "note":
          "opted_in and push_permission are two different refusals: the first is the customer's own switch inside their app, the second is what the operating system will do whatever that switch says. A device can be opted in and denied, which is why both travel.",
        "given": [
          "token": token,
          "environment": "production",
          "external_id": "user-42",
          "tags": [:],
          "timezone_id": "Europe/Paris",
          "locale": "fr-FR",
          "app_version": "2.0.0",
          "app_build": "980",
          "bundle_id": "com.example.app",
          "os_version": "26.0",
          "push_permission": "denied",
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
      [
        "name": "a permission that has never been asked for",
        "note":
          "undetermined is not denied. An app that has not shown the prompt yet has a device that can still become reachable, and the distinction is what an onboarding funnel is measured on. Quiet delivery is its own state again: provisional reaches the handset and lands where almost nobody looks.",
        "given": [
          "token": token,
          "environment": "sandbox",
          "external_id": NSNull(),
          "tags": [:],
          "timezone_id": "Europe/Paris",
          "locale": "fr-FR",
          "app_version": "1.0.0",
          "app_build": "1",
          "bundle_id": "com.example.app.clip",
          "os_version": "18.5",
          "push_permission": "undetermined",
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
      [
        "name": "the four tag value types",
        "note":
          "Scalars only, and each keeps its type on the wire: a boolean that arrives as 1 is an audience filter that silently stops matching.",
        "given": [
          "token": token,
          "environment": "sandbox",
          "external_id": NSNull(),
          "tags": ["text": "pro", "whole": 5, "fractional": 1.5, "flag": false],
          "timezone_id": "Europe/Paris",
          "locale": "fr",
          "app_version": "1.0.0",
          "app_build": "1",
          "bundle_id": "com.example.app",
          "os_version": "18.5",
          "push_permission": "provisional",
          "sdk_version": "0.2.0",
          "opted_in": true,
        ],
      ],
    ]

    return [
      "schema_version": 1,
      "endpoint": ["method": "POST", "path": "/v1/devices"],
      "description":
        "Given the SDK's device state, the exact body POST /v1/devices must receive. The SDK holds the whole state and sends it whole; the server replaces what it holds.",
      "cases": cases,
    ]
  }

  /// The replay harness, and the only Swift in the whole exercise: a state
  /// expressed in the API's field names, rebuilt into the SDK's own type.
  private func state(from given: [String: Any]) -> DeviceState {
    var state = DeviceState()
    state.token = given["token"] as? String
    state.environment = PushEnvironment(rawValue: given["environment"] as? String ?? "") ?? .production
    state.externalId = given["external_id"] as? String
    state.timezoneId = given["timezone_id"] as? String
    state.locale = given["locale"] as? String
    state.appVersion = given["app_version"] as? String
    state.appBuild = given["app_build"] as? String
    state.bundleId = given["bundle_id"] as? String
    state.osVersion = given["os_version"] as? String
    state.pushPermission =
      (given["push_permission"] as? String).flatMap(PushPermission.init(rawValue:))
    state.sdkVersion = given["sdk_version"] as? String
    state.optedIn = given["opted_in"] as? Bool ?? true

    var tags: [String: TagValue] = [:]
    for (name, value) in given["tags"] as? [String: Any] ?? [:] {
      // `NSNumber` answers to every numeric question, so the discriminator has to
      // be the type it was actually created with — otherwise every boolean tag
      // comes back an integer.
      if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
          tags[name] = .bool(number.boolValue)
        } else if CFNumberIsFloatType(number) {
          tags[name] = .double(number.doubleValue)
        } else {
          tags[name] = .int(number.intValue)
        }
      } else if let text = value as? String {
        tags[name] = .string(text)
      }
    }
    state.tags = tags

    return state
  }

  // MARK: - Events

  func testEventVectors() throws {
    let document = eventDocument()

    try check(document, named: "events.json") { rawCase in
      let given = rawCase["given"] as? [String: Any] ?? [:]
      let queue = (given["queue"] as? [[String: Any]] ?? []).map(event(from:))
      let batch = Array(queue.prefix(Engine.maxEventsPerBatch))

      return ["events": batch.map { $0.json() }]
    }
  }

  private func eventDocument() -> [String: Any] {
    func open(_ index: Int, at seconds: TimeInterval) -> [String: Any] {
      [
        "type": "opened",
        "delivery_id": String(format: "01937b1e-0000-7000-8000-%012d", index),
        "at": ISO8601.string(from: Date(timeIntervalSince1970: seconds)),
      ]
    }

    let cases: [[String: Any]] = [
      [
        "name": "one open",
        "given": ["queue": [open(1, at: 1_770_000_000)]],
        "remaining_after_success": 0,
      ],
      [
        "name": "several opens, in the order they happened",
        "note":
          "Order is preserved. The server keeps the first report of a delivery and ignores later ones, so the order is what decides which instant is kept.",
        "given": [
          "queue": [
            open(1, at: 1_770_000_000),
            open(2, at: 1_770_000_060),
            open(3, at: 1_770_003_600),
          ]
        ],
        "remaining_after_success": 0,
      ],
      [
        "name": "a queue longer than one batch",
        "note":
          "A hundred at a time, which is the API's cap. The rest stay queued and go out in the next request — an app that has been offline is the ordinary case, not an anomaly.",
        "given": [
          "queue": (1...101).map { open($0, at: 1_770_000_000 + TimeInterval($0)) }
        ],
        "remaining_after_success": 1,
      ],
    ]

    return [
      "schema_version": 1,
      "endpoint": ["method": "POST", "path": "/v1/events"],
      "batch_limit": Engine.maxEventsPerBatch,
      "description":
        "Given a queue of events the SDK is holding, the exact body POST /v1/events must receive. Delivery is at-least-once: an entry stays queued until the server answers 2xx, and a replay is safe because the server is idempotent per delivery and event type.",
      "cases": cases,
    ]
  }

  private func event(from raw: [String: Any]) -> QueuedEvent {
    QueuedEvent(
      type: raw["type"] as? String ?? QueuedEvent.opened,
      deliveryId: raw["delivery_id"] as? String ?? "",
      at: date(from: raw["at"] as? String ?? "")
    )
  }

  private func date(from text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

    return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
  }

  // MARK: - Writing and checking

  /// Fills in each case's expected request from the real code, then either writes
  /// the file or asserts the committed one matches it byte for byte.
  private func check(
    _ document: [String: Any],
    named name: String,
    body: ([String: Any]) -> [String: Any]
  ) throws {
    let endpoint = document["endpoint"] as? [String: Any] ?? [:]

    var filled = document
    filled["cases"] = (document["cases"] as? [[String: Any]] ?? []).map { rawCase -> [String: Any] in
      var completed = rawCase
      var expect: [String: Any] = [
        "method": endpoint["method"] ?? "POST",
        "path": endpoint["path"] ?? "",
        "body": body(rawCase),
      ]
      if let remaining = rawCase["remaining_after_success"] {
        expect["remaining_after_success"] = remaining
      }
      completed["remaining_after_success"] = nil
      completed["expect"] = expect

      return completed.compactMapValues { $0 }
    }

    let rendered = try JSONSerialization.data(
      withJSONObject: filled, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    let file = directory.appendingPathComponent(name)

    guard !rewriting else {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
      try (rendered + Data("\n".utf8)).write(to: file)

      return
    }

    let committed = try Data(contentsOf: file)

    XCTAssertEqual(
      String(decoding: committed, as: UTF8.self),
      String(decoding: rendered + Data("\n".utf8), as: UTF8.self),
      """
      \(name) no longer describes what this SDK sends. If the change was \
      deliberate, regenerate with CARILLON_WRITE_FIXTURES=1 swift test and \
      carry the same change to the other SDKs.
      """
    )
  }
}
