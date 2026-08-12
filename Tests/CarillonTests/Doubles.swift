import Foundation

@testable import Carillon

/// The network, scripted.
///
/// Records every request in order, so a test can state the exact call the SDK
/// made rather than that it made one — the request body is the contract with the
/// server, and it is the thing worth being precise about.
final class FakeTransport: Transport {
  private let lock = Lock()
  private var scripted: [HTTPOutcome] = []
  private var recorded: [HTTPRequest] = []
  private var inFlight = 0
  private var peak = 0

  /// Awaited before each send. A test uses it to hold a call open and prove that
  /// nothing else starts while it is.
  var beforeSend: ((Int) async -> Void)?

  /// Returned once the script runs out. A device that keeps trying is the normal
  /// state of this SDK, so the fallback has to be an answer rather than a crash.
  var fallback: HTTPOutcome = .response(status: 200, body: Data("{}".utf8))

  init(_ scripted: [HTTPOutcome] = []) {
    self.scripted = scripted
  }

  var requests: [HTTPRequest] { lock.withLock { recorded } }
  var bodies: [[String: Any]] {
    requests.map { (try? JSONSerialization.jsonObject(with: $0.body)) as? [String: Any] ?? [:] }
  }
  /// The highest number of calls that were ever open at once. One is the whole
  /// point of the registration loop.
  var peakConcurrency: Int { lock.withLock { peak } }

  func send(_ request: HTTPRequest) async -> HTTPOutcome {
    let index = lock.withLock { () -> Int in
      recorded.append(request)
      inFlight += 1
      peak = max(peak, inFlight)

      return recorded.count - 1
    }

    await beforeSend?(index)

    // Yielded a few times so that a second loop, if one existed, would have room
    // to start and be seen. Without this the peak above could read one purely
    // because nothing ever got the chance to overlap.
    for _ in 0..<4 { await Task.yield() }

    return lock.withLock {
      inFlight -= 1

      return index < scripted.count ? scripted[index] : fallback
    }
  }
}

/// Time, on demand.
///
/// A backoff schedule that can only be verified by waiting five minutes is a
/// schedule nobody verifies. Sleeping advances the clock instead, so an event
/// recorded after a retry carries the instant it would really have carried.
final class FakeClock: Clock {
  private let lock = Lock()
  private var current: Date
  private var recorded: [TimeInterval] = []

  init(now: Date = Date(timeIntervalSince1970: 1_770_000_000)) {
    self.current = now
  }

  var now: Date { lock.withLock { current } }
  var sleeps: [TimeInterval] { lock.withLock { recorded } }

  func sleep(_ seconds: TimeInterval) async {
    lock.withLock {
      recorded.append(seconds)
      current = current.addingTimeInterval(seconds)
    }
  }
}

/// A rendezvous a test controls.
///
/// Used to hold one request open across other calls, which is the only way to
/// state "nothing else started while this was in flight" as an assertion rather
/// than as a hope about scheduling.
actor Gate {
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var opened = false

  func wait() async {
    if opened { return }

    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    opened = true
    let pending = waiting
    waiting = []

    for continuation in pending { continuation.resume() }
  }
}

/// An RFC 9457 body, as the API produces them.
func problemBody(
  code: String, status: Int, title: String = "Something to fix", detail: String? = nil
) -> Data {
  var object: [String: Any] = [
    "type": "https://carillon.dev/errors/\(code)",
    "title": title,
    "status": status,
    "code": code,
    "docs": "https://carillon.dev/docs/errors#\(code)",
  ]
  if let detail { object["detail"] = detail }

  return try! JSONSerialization.data(withJSONObject: object)
}

/// A device state with every field answered, so a test asserting the body is
/// asserting the whole table rather than the half of it that happens to be set.
func fullState(token: String = String(repeating: "ab", count: 32)) -> DeviceState {
  var state = DeviceState()
  state.token = token
  state.environment = .sandbox
  state.externalId = "user-42"
  state.tags = ["plan": "pro", "seats": 5, "beta": true]
  state.timezoneId = "Europe/Paris"
  state.locale = "fr-FR"
  state.appVersion = "1.4.2"
  state.appBuild = "4271"
  state.bundleId = "com.example.app"
  state.osVersion = "18.5"
  state.pushPermission = .allowed
  state.sdkVersion = Carillon.sdkVersion
  state.optedIn = true

  return state
}

/// An engine wired to doubles, with the store and clock handed back so a test can
/// look at what survived.
func makeEngine(
  transport: FakeTransport = FakeTransport(),
  clock: FakeClock = FakeClock(),
  store: Store = MemoryStore(),
  key: String = "carillon_mk_test_" + String(repeating: "a", count: 43)
) -> Engine {
  Engine(
    store: store,
    transport: transport,
    clock: clock,
    key: key,
    endpointDescription: "https://api-staging.carillon.dev",
    environment: .sandbox
  )
}
