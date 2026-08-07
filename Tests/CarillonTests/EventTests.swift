import XCTest

@testable import Carillon

/// Opens are the half of the product the customer cannot fake, and the half the
/// SDK can silently lose. Every test here is about not losing one.
final class EventTests: XCTestCase {
  private let deliveryId = "01937b1e-0000-7000-8000-0000000000ff"

  private func payload(_ id: String) -> [AnyHashable: Any] {
    [
      "aps": ["alert": ["title": "Your order shipped"]],
      "order_id": "42",
      "carillon": ["delivery_id": id],
    ]
  }

  func testQueuesAndReportsAnOpen() async {
    let transport = FakeTransport()
    let clock = FakeClock()
    let engine = makeEngine(transport: transport, clock: clock, key: "carillon_mk_live_abc")

    XCTAssertTrue(engine.didOpen(userInfo: payload(deliveryId)))
    await engine.settle()

    let request = transport.requests.last
    XCTAssertEqual(request?.method, "POST")
    XCTAssertEqual(request?.path, "/v1/events")

    let events = transport.bodies.last?["events"] as? [[String: Any]] ?? []
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?["type"] as? String, "opened")
    XCTAssertEqual(events.first?["delivery_id"] as? String, deliveryId)
    XCTAssertEqual(events.first?["at"] as? String, ISO8601.string(from: clock.now))
  }

  func testIgnoresANotificationThatIsNotOurs() async {
    // Another SDK's notification, or a local one the app scheduled itself. There
    // is no delivery to report an open against, and possession of a delivery id
    // is the only thing that proves a notification arrived at all. Silence here
    // is what lets the app forward every response without sorting them first.
    let transport = FakeTransport()
    let engine = makeEngine(transport: transport)

    XCTAssertFalse(engine.didOpen(userInfo: ["aps": ["alert": "Hello"]]))
    XCTAssertFalse(engine.didOpen(userInfo: ["carillon": ["something_else": "x"]]))
    await engine.settle()

    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertEqual(engine.debugInfo().queuedEvents, 0)
  }

  func testKeepsAnEventUntilTheServerTakesIt() async {
    // At-least-once, by design. The server is idempotent per delivery and event
    // type, so a replay after a dropped connection changes nothing — which is
    // what makes it safe to keep the event until a 2xx has actually been seen
    // rather than dropping it the moment it went to the network.
    let clock = FakeClock()
    let store = MemoryStore()
    let transport = FakeTransport([
      .failure("offline"),
      .response(status: 503, body: Data()),
      .response(status: 202, body: Data(#"{"received":1}"#.utf8)),
    ])

    let engine = makeEngine(transport: transport, clock: clock, store: store)
    engine.didOpen(userInfo: payload(deliveryId))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 3)
    XCTAssertEqual(clock.sleeps, [1, 2])
    XCTAssertTrue(store.events.isEmpty)
  }

  func testSurvivesTheAppBeingKilledBeforeItCouldReport() async {
    let store = MemoryStore()
    let first = makeEngine(store: store, key: "")

    first.didOpen(userInfo: payload(deliveryId))
    await first.settle()

    XCTAssertEqual(store.events.count, 1)

    // A new process, the same container: the open is still owed and goes out.
    let transport = FakeTransport()
    let restored = makeEngine(transport: transport, store: store)
    restored.startEventLoop()
    await restored.settle()

    let events = transport.bodies.last?["events"] as? [[String: Any]] ?? []
    XCTAssertEqual(events.first?["delivery_id"] as? String, deliveryId)
    XCTAssertTrue(store.events.isEmpty)
  }

  func testSendsAtMostAHundredAtATime() async {
    let transport = FakeTransport()
    let store = MemoryStore()
    // Queued with no key, so the whole backlog exists before anything is sent —
    // which is exactly the situation the cap is for: an app that has been
    // offline, or opened before it was configured.
    let engine = makeEngine(transport: transport, store: store, key: "")

    for index in 0..<250 {
      engine.didOpen(userInfo: payload(String(format: "01937b1e-0000-7000-8000-%012d", index)))
    }
    await engine.settle()
    XCTAssertEqual(store.events.count, 250)

    engine.configure(
      key: "carillon_mk_live_abc",
      endpoint: URL(string: "https://api-staging.carillon.dev")!,
      debug: false,
      transport: nil
    )
    await engine.settle()

    let batches = transport.bodies.map { ($0["events"] as? [[String: Any]] ?? []).count }
    XCTAssertEqual(batches, [100, 100, 50])
    XCTAssertTrue(store.events.isEmpty)
  }

  func testDropsABatchTheServerWillNeverAcceptRatherThanLoopingOnIt() async {
    // The queue would otherwise grow for the life of the install, retrying a
    // body that is just as invalid every time. The reason is logged instead.
    let clock = FakeClock()
    let store = MemoryStore()
    let transport = FakeTransport([
      .response(status: 400, body: problemBody(code: "invalid_request", status: 400))
    ])

    let engine = makeEngine(transport: transport, clock: clock, store: store)
    engine.didOpen(userInfo: payload(deliveryId))
    await engine.settle()

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertTrue(clock.sleeps.isEmpty)
    XCTAssertTrue(store.events.isEmpty)
  }

  func testHandsAColdStartOpenToTheFirstSubscriber() async {
    // An app launched by a tap runs its whole startup before anything attaches a
    // handler, and that tap is the journey the notification was sent to start.
    let engine = makeEngine()
    engine.didOpen(userInfo: payload(deliveryId))

    var seen: [String] = []
    engine.setOnOpened { seen.append($0.deliveryId) }

    XCTAssertEqual(seen, [deliveryId])

    // And once someone is listening, opens arrive as they happen rather than
    // being held a second time.
    engine.didOpen(userInfo: payload("01937b1e-0000-7000-8000-000000000002"))
    XCTAssertEqual(seen.count, 2)

    await engine.settle()
  }

  func testHandsTheWholePayloadOverBecauseTheDestinationIsTheCustomersOwn() async {
    let engine = makeEngine()
    var received: OpenedNotification?
    engine.setOnOpened { received = $0 }

    engine.didOpen(userInfo: payload(deliveryId))
    await engine.settle()

    XCTAssertEqual(received?.userInfo["order_id"] as? String, "42")
  }
}
