import XCTest

@testable import Carillon

/// Registration is the call the whole product depends on: a device that never
/// registers receives nothing, and the failure is invisible from the app.
final class RegistrationTests: XCTestCase {
  func testSendsTheWholeTableAsTheServerDefinesIt() async {
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.refreshDeviceAttributes(
      timezoneId: "Europe/Paris", locale: "fr-FR", appVersion: "1.4.2", appBuild: "4271",
      bundleId: "com.example.app")
    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .provisional)
    engine.identify("user-42")
    engine.setTags(["plan": "pro", "seats": 5, "beta": true])
    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    let body = transport.bodies.last ?? [:]

    XCTAssertEqual(transport.requests.last?.method, "POST")
    XCTAssertEqual(transport.requests.last?.path, "/v1/devices")
    XCTAssertEqual(body["token"] as? String, String(repeating: "ab", count: 32))
    XCTAssertEqual(body["platform"] as? String, "ios")
    XCTAssertEqual(body["environment"] as? String, "sandbox")
    XCTAssertEqual(body["external_id"] as? String, "user-42")
    XCTAssertEqual(body["timezone_id"] as? String, "Europe/Paris")
    XCTAssertEqual(body["locale"] as? String, "fr-FR")
    XCTAssertEqual(body["app_version"] as? String, "1.4.2")
    XCTAssertEqual(body["app_build"] as? String, "4271")
    XCTAssertEqual(body["bundle_id"] as? String, "com.example.app")
    XCTAssertEqual(body["os_version"] as? String, "18.5")
    XCTAssertEqual(body["push_permission"] as? String, "provisional")
    XCTAssertEqual(body["sdk_version"] as? String, Carillon.sdkVersion)
    XCTAssertEqual(body["opted_in"] as? Bool, true)

    let tags = body["tags"] as? [String: Any] ?? [:]
    XCTAssertEqual(tags["plan"] as? String, "pro")
    XCTAssertEqual(tags["seats"] as? Int, 5)
    XCTAssertEqual(tags["beta"] as? Bool, true)
  }

  func testRegistersBeforeAnybodyHasBeenAsked() async {
    // The model, stated as an assertion. `configure` obtains a token without
    // prompting — a token is transport addressing, not consent — so the first
    // registration goes out carrying `undetermined`, and the handset is in the
    // customer's base from its first launch. A base holding only the people who
    // said yes measures an app's onboarding rather than its reach.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .undetermined)
    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.bodies.last?["push_permission"] as? String, "undetermined")
  }

  func testSendsNullForWhatTheHandsetHasNotAnsweredYet() async {
    // The permission read is asynchronous, so a registration can go out before
    // iOS has answered. An explicit null says "not known"; omitting the field
    // would say "unchanged", which for a device that has never reported one is
    // a different and untrue statement.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    let body = transport.bodies.last ?? [:]
    XCTAssertTrue(body["push_permission"] is NSNull)
    XCTAssertTrue(body["os_version"] is NSNull)
    XCTAssertTrue(body["app_build"] is NSNull)
    XCTAssertTrue(body["bundle_id"] is NSNull)
  }

  func testRegistersAgainWhenThePermissionOrTheOperatingSystemChanges() async {
    // The mechanism is the fingerprint, and it is the serialised body: a state
    // saying something new about the handset is by construction a state the
    // server has not been told. Somebody switching notifications off in
    // Settings is invisible to an app that is not running, so the next launch
    // is when it is discovered — and this is what makes that launch cost a call
    // while a launch that discovered nothing still costs none.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.setToken(String(repeating: "ab", count: 32))
    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .allowed)
    await engine.settle()
    XCTAssertEqual(transport.requests.count, 1)

    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .allowed)
    await engine.settle()
    XCTAssertEqual(transport.requests.count, 1)

    engine.refreshOperatingSystem(osVersion: "18.5", pushPermission: .denied)
    await engine.settle()
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(transport.bodies.last?["push_permission"] as? String, "denied")

    engine.refreshOperatingSystem(osVersion: "26.0", pushPermission: .denied)
    await engine.settle()
    XCTAssertEqual(transport.requests.count, 3)
    XCTAssertEqual(transport.bodies.last?["os_version"] as? String, "26.0")
  }

  func testCarriesTheKeyAsABearerToken() async {
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport, key: "carillon_mk_live_abc")

    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    XCTAssertEqual(transport.requests.first?.key, "carillon_mk_live_abc")
  }

  func testSendsNullRatherThanOmittingAClearedIdentity() async {
    // The server reads an absent field as "unchanged" and an explicit null as
    // "erase". `clearIdentity()` can only mean the second, so the null has to be
    // on the wire — omitting it would leave the old identifier in place for ever
    // with nothing failing to say so.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.setToken(String(repeating: "ab", count: 32))
    engine.identify("user-42")
    await engine.settle()

    engine.identify(nil)
    await engine.settle()

    let body = transport.bodies.last ?? [:]
    XCTAssertTrue(body["external_id"] is NSNull)
  }

  func testSendsNothingBeforeATokenExists() async {
    // A registration without a token names no device. Everything set before APNs
    // answers is held, and goes out with the first real call.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.identify("user-42")
    engine.setTags(["plan": "pro"])
    await engine.settle()

    XCTAssertTrue(transport.requests.isEmpty)

    engine.setToken(String(repeating: "cd", count: 32))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.bodies.last?["external_id"] as? String, "user-42")
  }

  func testSendsNothingBeforeAKeyExists() async {
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport, key: "")

    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    XCTAssertTrue(transport.requests.isEmpty)

    engine.configure(
      key: "carillon_mk_live_abc",
      endpoint: URL(string: "https://api-staging.carillon.dev")!,
      debug: false,
      transport: nil
    )
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 1)
  }

  func testCoalescesSeveralChangesIntoTheLatestState() async {
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    engine.setToken(String(repeating: "ab", count: 32))
    engine.identify("first")
    engine.identify("second")
    engine.setTags(["plan": "pro"])
    await engine.settle()

    // Never two at once: both would upsert the same row, and the one that lands
    // second is whichever was slower — which is not the newer one.
    XCTAssertEqual(transport.peakConcurrency, 1)
    XCTAssertLessThan(transport.requests.count, 4)
    XCTAssertEqual(transport.bodies.last?["external_id"] as? String, "second")
  }

  func testHoldsAChangeMadeMidFlightAndSendsItNext() async {
    let gate = Gate()
    let transport = FakeTransport()
    transport.beforeSend = { index in
      // Only the first call waits. The test opens the gate once it has made a
      // change behind it.
      if index == 0 { await gate.wait() }
    }

    let engine = makeEngine(transport: transport)
    engine.setToken(String(repeating: "ab", count: 32))

    // The first registration is now open. Anything set here has to reach the
    // server without racing the call already in flight.
    while transport.requests.isEmpty { await Task.yield() }
    engine.identify("arrived-mid-flight")

    await gate.open()
    await engine.settle()

    XCTAssertEqual(transport.peakConcurrency, 1)
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertTrue(transport.bodies[0]["external_id"] is NSNull)
    XCTAssertEqual(transport.bodies[1]["external_id"] as? String, "arrived-mid-flight")
  }

  func testSaysNothingTwiceWhenNothingChanged() async {
    // A cold start with an unchanged device costs no call at all, which is what
    // makes "call register() on every launch" the cheap instruction the
    // documentation says it is.
    let transport = FakeTransport()
    let store = MemoryStore()
    let engine = makeEngine(transport: transport, store: store)

    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()
    XCTAssertEqual(transport.requests.count, 1)

    let second = makeEngine(transport: transport, store: store)
    second.setToken(String(repeating: "ab", count: 32))
    await second.settle()

    XCTAssertEqual(transport.requests.count, 1)
  }

  func testRestoresItsStateAfterTheAppIsKilled() async {
    let store = MemoryStore()
    let first = makeEngine(store: store)

    first.identify("user-42")
    first.setTags(["plan": "pro"])
    first.setToken(String(repeating: "ab", count: 32))
    await first.settle()

    // A fresh process, the same container. The token from the previous launch is
    // what lets an app that has been offline register the moment it starts.
    let transport = FakeTransport()
    let restored = makeEngine(transport: transport, store: store)

    XCTAssertEqual(restored.currentState.externalId, "user-42")
    XCTAssertEqual(restored.currentState.token, String(repeating: "ab", count: 32))
    XCTAssertEqual(restored.currentState.tags["plan"], .string("pro"))
  }

  func testRetriesWhenThereIsNoAnswerAndBacksOff() async {
    let clock = FakeClock()
    let transport = FakeTransport([
      .failure("offline"),
      .failure("offline"),
      .response(status: 503, body: Data()),
      .response(status: 200, body: Data(#"{"id":"01937b1e-0000-7000-8000-000000000001"}"#.utf8)),
    ])

    let store = MemoryStore()
    let engine = makeEngine(transport: transport, clock: clock, store: store)

    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 4)
    XCTAssertEqual(clock.sleeps, [1, 2, 4])
    XCTAssertEqual(store.deviceId, "01937b1e-0000-7000-8000-000000000001")
  }

  func testDoesNotRetryAnythingElseInTheFourHundreds() async {
    // A 422 retried forever is a bug loop rather than resilience: the token will
    // be just as malformed in five minutes.
    let clock = FakeClock()
    let transport = FakeTransport([
      .response(
        status: 422,
        body: problemBody(
          code: "invalid_request", status: 422,
          detail: "An APNs token is hexadecimal."))
    ])

    let engine = makeEngine(transport: transport, clock: clock)
    engine.setToken("not-hexadecimal")
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertTrue(clock.sleeps.isEmpty)
    XCTAssertEqual(
      engine.debugInfo().lastRegistrationResult,
      "invalid_request: An APNs token is hexadecimal.")
  }

  func testRetriesA429BecauseTheAnswerIsToSlowDownRatherThanToStop() async {
    let clock = FakeClock()
    let transport = FakeTransport([
      .response(status: 429, body: problemBody(code: "rate_limited", status: 429)),
      .response(status: 200, body: Data("{}".utf8)),
    ])

    let engine = makeEngine(transport: transport, clock: clock)
    engine.setToken(String(repeating: "ab", count: 32))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(clock.sleeps, [1])
  }
}
