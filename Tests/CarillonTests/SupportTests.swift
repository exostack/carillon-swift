import XCTest

@testable import Carillon

final class HexTests: XCTestCase {
  func testEncodesLowercaseWithEveryByteInTwoCharacters() {
    XCTAssertEqual(Hex.encode(Data([0x00, 0x0f, 0xa1, 0xff])), "000fa1ff")
    XCTAssertEqual(Hex.encode(Data()), "")
  }

  func testEncodesATokenTheLengthApnsHandsOver() {
    let token = Data((0..<32).map { UInt8($0) })

    XCTAssertEqual(Hex.encode(token).count, 64)
    XCTAssertEqual(Hex.encode(token).prefix(6), "000102")
  }

  func testNeverProducesUppercase() {
    // The server folds case on iOS tokens. Two spellings of one token would
    // otherwise become two devices: counted twice, sent to twice, and only half
    // of it struck off when Apple forgets the token.
    let encoded = Hex.encode(Data([0xab, 0xcd, 0xef]))

    XCTAssertEqual(encoded, encoded.lowercased())
  }
}

final class BackoffTests: XCTestCase {
  func testDoublesFromOneSecond() {
    XCTAssertEqual((1...6).map(Backoff.delay(afterFailures:)), [1, 2, 4, 8, 16, 32])
  }

  func testWaitsForNothingBeforeTheFirstAttempt() {
    XCTAssertEqual(Backoff.delay(afterFailures: 0), 0)
  }

  func testStopsAtFiveMinutes() {
    // The ceiling matters more than the curve: a device that has been offline all
    // day has to register within a minute of coming back, and an SDK that has
    // backed off to an hour is indistinguishable from one that is broken.
    XCTAssertEqual(Backoff.delay(afterFailures: 20), 300)
    XCTAssertEqual(Backoff.delay(afterFailures: 1_000), 300)
  }
}

final class DebugInfoTests: XCTestCase {
  func testAnswersEveryQuestionSupportAsksFirst() async {
    let store = MemoryStore()
    let clock = FakeClock()
    let transport = FakeTransport([
      .response(status: 200, body: Data(#"{"id":"01937b1e-0000-7000-8000-000000000001"}"#.utf8))
    ])

    let engine = makeEngine(
      transport: transport, clock: clock, store: store, key: "carillon_mk_test_abc")

    engine.refreshDeviceAttributes(
      timezoneId: "Europe/Paris", locale: "fr-FR", appVersion: "1.4.2", appBuild: "4271",
      bundleId: "com.example.app")
    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .denied)
    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    engine.didOpen(userInfo: ["carillon": ["delivery_id": "01937b1e-0000-7000-8000-0000000000ff"]])

    let info = engine.debugInfo()

    XCTAssertEqual(info.sdkVersion, Carillon.sdkVersion)
    // Whole, not truncated: a mobile key ships inside every copy of the app, so
    // anyone with the binary already has it, and hiding it here would only cost
    // the support engineer the one identifier that says which app this is.
    XCTAssertEqual(info.key, "carillon_mk_test_abc")
    XCTAssertEqual(info.endpoint, "https://api-staging.carillon.dev")
    XCTAssertEqual(info.token, String(repeating: "ab", count: 32))
    XCTAssertEqual(info.deviceId, "01937b1e-0000-7000-8000-000000000001")
    XCTAssertEqual(info.environment, "sandbox")
    XCTAssertEqual(info.bundleId, "com.example.app")
    XCTAssertEqual(info.appBuild, "4271")
    XCTAssertEqual(info.osVersion, "18.5")
    // The first thing to look at when an integration works and nothing arrives.
    XCTAssertEqual(info.pushPermission, "denied")
    XCTAssertEqual(info.lastRegistrationAt, clock.now)
    XCTAssertEqual(info.lastRegistrationResult, "registered")
    XCTAssertEqual(info.queuedEvents, 1)

    await engine.settle()
  }

  func testAnswersBeforeAnythingHasHappened() {
    // Support asks for this when nothing works. It must never be the call that
    // also fails.
    let info = makeEngine(key: "").debugInfo()

    XCTAssertEqual(info.key, "")
    XCTAssertNil(info.token)
    XCTAssertNil(info.deviceId)
    XCTAssertNil(info.lastRegistrationAt)
    XCTAssertEqual(info.queuedEvents, 0)
  }

  func testRendersAsSomethingWorthPastingIntoATicket() {
    let info = makeEngine(key: "carillon_mk_test_abc").debugInfo()
    let rendered = info.description

    XCTAssertTrue(rendered.contains("sdk_version"))
    XCTAssertTrue(rendered.contains("carillon_mk_test_abc"))
    // Absent values read as absent rather than as `Optional(nil)`.
    XCTAssertTrue(rendered.contains("—"))
    XCTAssertFalse(rendered.contains("Optional"))
  }

  func testSerialisesUnderTheNamesTheApiUses() throws {
    let info = makeEngine(key: "k").debugInfo()
    let data = try JSONEncoder().encode(info)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(object["sdk_version"] as? String, Carillon.sdkVersion)
    XCTAssertNotNil(object["queued_events"])
  }
}

final class StoreTests: XCTestCase {
  private func defaults() throws -> UserDefaults {
    let suite = try XCTUnwrap(UserDefaults(suiteName: "dev.carillon.tests.\(UUID().uuidString)"))

    return suite
  }

  func testRoundTripsTheWholeStateThroughTheContainer() throws {
    let store = UserDefaultsStore(defaults: try defaults())
    var state = fullState()
    state.tags = ["plan": "pro", "seats": 5, "beta": true, "ratio": 1.5]

    store.state = state
    store.deviceId = "01937b1e-0000-7000-8000-000000000001"
    store.registeredFingerprint = state.fingerprint()
    store.events = [
      QueuedEvent(type: "opened", deliveryId: "a", at: Date(timeIntervalSince1970: 1_770_000_000))
    ]

    XCTAssertEqual(store.state, state)
    XCTAssertEqual(store.deviceId, "01937b1e-0000-7000-8000-000000000001")
    XCTAssertEqual(store.registeredFingerprint, state.fingerprint())
    XCTAssertEqual(store.events.count, 1)
  }

  func testKeepsABooleanTagABoolean() throws {
    // A tag that went in as `true` and comes back as `1` is an audience filter
    // that silently stops matching.
    let store = UserDefaultsStore(defaults: try defaults())
    var state = DeviceState()
    state.tags = ["beta": true, "seats": 1]
    store.state = state

    XCTAssertEqual(store.state?.tags["beta"], .bool(true))
    XCTAssertEqual(store.state?.tags["seats"], .int(1))
  }

  func testDropsAValueItCannotRead() throws {
    // Written by an older or newer install. The state rebuilds itself on the next
    // registration, and a queue that cannot be read could never be sent either.
    let suite = try defaults()
    suite.set(Data("not json".utf8), forKey: "dev.carillon.state")
    let store = UserDefaultsStore(defaults: suite)

    XCTAssertNil(store.state)
    XCTAssertTrue(store.events.isEmpty)
  }

  func testFingerprintIgnoresTheOrderADictionaryHappensToHave() {
    // Compared as a serialised body, with sorted keys. A dictionary that
    // serialised differently on the next launch would make every cold start look
    // like a change and re-register the whole park.
    var one = DeviceState()
    one.token = "ab"
    one.tags = ["a": 1, "b": 2, "c": 3]

    var two = DeviceState()
    two.token = "ab"
    two.tags = ["c": 3, "b": 2, "a": 1]

    XCTAssertEqual(one.fingerprint(), two.fingerprint())
  }

  func testFingerprintChangesWhenAnythingTheServerWouldSeeChanges() {
    var state = fullState()
    let before = state.fingerprint()
    state.optedIn = false

    XCTAssertNotEqual(before, state.fingerprint())
  }

  func testFingerprintNoticesARevokedPermission() {
    // Stated separately from the case above because this is the one nobody in
    // the app ever calls a setter for: it changes in Settings, while the app is
    // not running, and the only thing that carries it to the server is the next
    // launch finding a body it has not sent before.
    var state = fullState()
    let before = state.fingerprint()
    state.pushPermission = .denied

    XCTAssertNotEqual(before, state.fingerprint())
  }
}
