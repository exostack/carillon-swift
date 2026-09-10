import Foundation

/// Everything the SDK actually does, with no platform in it.
///
/// The facade is static because that is the shape a customer wants to call; this
/// is an object because that is the shape a test wants to hold. The split is the
/// whole reason the protocol logic here can be exercised without a simulator, a
/// network, or a wall clock.
final class Engine {
  /// Every field below is read and written through this, and never across a
  /// suspension point — see `Lock`, whose shape is what makes that true rather
  /// than merely intended.
  private let lock = Lock()

  private let store: Store
  private let clock: Clock
  private var transport: Transport
  private var key: String
  private var endpointDescription: String
  private var debugEnabled: Bool

  private var state: DeviceState
  private var registrationTask: Task<Void, Never>?
  /// The body the server refused. Kept so the identical one is not sent again,
  /// while a changed one still is — a refusal is about a payload, not about the
  /// device, and a corrected identifier deserves another attempt.
  private var refusedFingerprint: String?
  private var eventTask: Task<Void, Never>?
  private var lastRegistrationAt: Date?
  private var lastRegistrationResult: String?

  /// Opens that arrived before anyone was listening.
  ///
  /// An app launched by a tap runs its whole startup before a handler is
  /// attached, and that tap is the most valuable one there is — it is the journey
  /// the notification was sent to start. Held until the first subscriber
  /// attaches rather than delivered into the void.
  private var heldOpens: [OpenedNotification] = []
  private var onOpened: ((OpenedNotification) -> Void)?

  init(
    store: Store,
    transport: Transport,
    clock: Clock,
    key: String = "",
    endpointDescription: String = Carillon.defaultEndpoint,
    debugEnabled: Bool = false,
    environment: PushEnvironment = .production
  ) {
    if store.installationSecret == nil {
      store.installationSecret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        .base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
      store.registeredFingerprint = nil
    }
    self.store = store
    self.transport = transport
    self.clock = clock
    self.key = key
    self.endpointDescription = endpointDescription
    self.debugEnabled = debugEnabled

    // The stored state, or a fresh one carrying what the device answers for
    // itself. Restoring first matters: a token obtained on a previous launch is
    // what lets an app that has been offline register the moment it starts.
    var restored = store.state ?? DeviceState()
    restored.environment = environment
    restored.sdkVersion = Carillon.sdkVersion
    self.state = restored
  }

  // MARK: - Configuration

  func configure(key: String, endpoint: URL, debug: Bool, transport: Transport?) {
    lock.withLock {
      self.key = key
      self.endpointDescription = endpoint.absoluteString
      self.debugEnabled = debug
      if let transport { self.transport = transport }
    }

    Log.write(debug, "configured for \(endpoint.absoluteString)")

    // A key arriving is itself news: an event queued before `configure` — a cold
    // start from a tap — has been waiting for one.
    startRegistrationLoop()
    startEventLoop()
  }

  // MARK: - The state the app sets

  func setToken(_ token: String) {
    mutate { $0.token = token }
  }

  func identify(_ externalId: String?) {
    mutate { $0.externalId = externalId }
  }

  func setTags(_ tags: [String: TagValue]) {
    // Replaced whole, never merged. The SDK holds the canonical map and the
    // server replaces what it holds — a merge here would make removing a tag
    // impossible without inventing a word for "remove".
    mutate { $0.tags = tags }
  }

  func setOptedIn(_ optedIn: Bool) {
    mutate { $0.optedIn = optedIn }
  }

  /// What the operating system answers for itself, re-read rather than
  /// remembered: a person who changes their phone's language has changed which
  /// text they should be sent, and a launch is when we find out.
  func setEnvironment(_ environment: PushEnvironment) {
    mutate { $0.environment = environment }
  }

  func didFailToRegister(describing message: String) {
    let verbose = lock.withLock {
      lastRegistrationResult = "token refused: \(message)"
      return debugEnabled
    }
    Log.write(verbose, "registration failed: \(message)")
  }

  func refreshDeviceAttributes(
    timezoneId: String?,
    locale: String?,
    appVersion: String?,
    appBuild: String?,
    bundleId: String?
  ) {
    mutate {
      $0.timezoneId = timezoneId
      $0.locale = locale
      $0.appVersion = appVersion
      $0.appBuild = appBuild
      $0.bundleId = bundleId
    }
  }

  /// The two facts only a running iOS app can answer, and only asynchronously.
  ///
  /// Apart from the rest because the read is: `UIDevice` is main-actor bound and
  /// notification settings arrive on a continuation, while everything above is
  /// answered by Foundation on the spot. They land through the same mutation, so
  /// a permission that has flipped since the last launch changes the body, which
  /// changes the fingerprint, which is what makes the device register again.
  func refreshOperatingSystem(osVersion: String?, pushPermission: PushPermission?) {
    mutate {
      $0.osVersion = osVersion
      $0.pushPermission = pushPermission
    }
  }

  private func mutate(_ change: (inout DeviceState) -> Void) {
    lock.withLock {
      change(&state)
      // Persisted on every change, not at send time. The app can be killed
      // between the two, and what survives has to be what the customer asked for
      // rather than what we last managed to deliver.
      store.state = state
    }

    startRegistrationLoop()
  }

  // MARK: - Registration

  /// One loop at a time; the latest state wins.
  ///
  /// The loop re-reads the state at the top of every attempt rather than
  /// capturing it once, so a change made while a call is in flight is picked up
  /// by the next pass instead of racing it. Two concurrent registrations for one
  /// device is the failure this prevents: they upsert the same row, and the one
  /// that lands second is whichever was slower — which is not the newer one.
  func startRegistrationLoop() {
    lock.withLock {
      guard registrationTask == nil else { return }

      registrationTask = Task { [weak self] () -> Void in
        await self?.runRegistrationLoop()
      }
    }
  }

  /// Whether another call would tell the server anything it does not know.
  ///
  /// The single question the loop turns on, and deliberately derived from state
  /// rather than tracked as a flag. A flag has to be set by every mutation and
  /// cleared by exactly the right one; this cannot be out of step with the truth,
  /// because it is computed from it. It is also what makes a token that arrives
  /// before `configure` register the moment a key does: nothing was consumed
  /// while sending was impossible.
  private func pendingRegistration() -> (DeviceState, String)? {
    lock.withLock { () -> (DeviceState, String)? in
      guard state.token != nil, !key.isEmpty else { return nil }

      let fingerprint = state.fingerprint()

      guard fingerprint != store.registeredFingerprint, fingerprint != refusedFingerprint else {
        return nil
      }

      return (state, fingerprint)
    }
  }

  private func runRegistrationLoop() async {
    var failures = 0

    while !Task.isCancelled {
      // A cold start with an unchanged device costs no call at all, which is what
      // makes "call register() on every launch" the cheap instruction the
      // documentation says it is.
      guard let (snapshot, fingerprint) = pendingRegistration() else {
        finishRegistrationLoop()

        return
      }

      let (key, debug) = lock.withLock { (self.key, debugEnabled) }
      var registration = snapshot.registrationBody()
      lock.withLock {
        registration["device_id"] = store.deviceId
        registration["installation_secret"] = store.installationSecret
      }
      let body = JSON.encode(registration) ?? Data()
      let request = HTTPRequest(method: "POST", path: "/v1/devices", body: body, key: key)

      Log.write(debug, "registering device")

      switch Verdict(await transport.send(request)) {
      case let .accepted(response):
        failures = 0
        recordRegistration(fingerprint: fingerprint, response: response, debug: debug)

      case let .retry(reason):
        failures += 1
        let delay = Backoff.delay(afterFailures: failures)
        Log.write(debug, "registration deferred (\(reason)); retrying in \(Int(delay))s")

        lock.withLock {
          lastRegistrationAt = clock.now
          lastRegistrationResult = "retrying in \(Int(delay))s: \(reason)"
        }

        // Nothing to put back: the state still differs from what the server has
        // confirmed, so the next pass finds the same work waiting.
        await clock.sleep(delay)

      case let .refused(problem, status):
        // Refused for a reason time will not change: a malformed token, a key
        // that may not register a device. Retrying would be a loop the customer
        // pays for and never sees. The reason is kept verbatim, because the API
        // writes every message to say what to do next.
        let summary = problem?.summary ?? "HTTP \(status)"

        lock.withLock {
          lastRegistrationAt = clock.now
          lastRegistrationResult = summary
          refusedFingerprint = fingerprint
        }

        Log.write(debug, "registration refused: \(summary)")
        finishRegistrationLoop()

        return
      }
    }

    finishRegistrationLoop()
  }

  /// Clears the loop and, in the same breath, restarts it if work arrived while
  /// it was winding down.
  ///
  /// Both under one acquisition on purpose. Releasing in between would leave an
  /// instant in which the task is nil and there is work waiting, and a mutation
  /// landing in that instant would find a loop apparently running and wait for
  /// the next app start.
  private func finishRegistrationLoop() {
    lock.withLock {
      registrationTask = nil

      guard pendingWorkExists() else { return }

      registrationTask = Task { [weak self] () -> Void in
        await self?.runRegistrationLoop()
      }
    }
  }

  /// The same question as `pendingRegistration`, asked from inside the lock.
  private func pendingWorkExists() -> Bool {
    guard state.token != nil, !key.isEmpty else { return false }

    let fingerprint = state.fingerprint()

    return fingerprint != store.registeredFingerprint && fingerprint != refusedFingerprint
  }

  private var deviceIdHandler: ((String) -> Void)?
  var onDeviceIdChanged: ((String) -> Void)? {
    get { lock.withLock { deviceIdHandler } }
    set { lock.withLock { deviceIdHandler = newValue } }
  }

  private func recordRegistration(fingerprint: String, response: Data, debug: Bool) {
    // The server names the device it created. Kept for `debugInfo()`, which is
    // the first thing support asks for — and read leniently, because a
    // registration that succeeded must not be undone by a response shape.
    let object = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any]
    let id = object?["id"] as? String

    let handler = lock.withLock { () -> ((String) -> Void)? in
      let changed = id != nil && id != store.deviceId
      store.registeredFingerprint = fingerprint
      refusedFingerprint = nil
      if let id { store.deviceId = id }
      lastRegistrationAt = clock.now
      lastRegistrationResult = "registered"
      return changed ? deviceIdHandler : nil
    }
    if let id { handler?(id) }

    Log.write(debug, "registered as \(id ?? "an unnamed device")")
  }

  // MARK: - Opens

  /// The delivery id is the proof, so an absent one is not an event.
  ///
  /// A notification that did not come from Carillon — another SDK's, or a local
  /// one the app scheduled itself — carries no `carillon` key, and reporting a
  /// tap on it would be reporting an open against nothing. Silence is correct
  /// here, and it is what lets the app forward every response it receives without
  /// having to work out which ones are ours.
  @discardableResult
  func didOpen(userInfo: [AnyHashable: Any]) -> Bool {
    let debug = isDebugEnabled

    guard
      let carillon = userInfo["carillon"] as? [String: Any],
      let deliveryId = carillon["delivery_id"] as? String
    else {
      Log.write(debug, "a notification was opened that carries no delivery id")

      return false
    }

    let at = clock.now
    let notification = OpenedNotification(deliveryId: deliveryId, userInfo: userInfo, openedAt: at)

    let handler = lock.withLock { () -> ((OpenedNotification) -> Void)? in
      store.events.append(QueuedEvent(type: QueuedEvent.opened, deliveryId: deliveryId, at: at))

      if onOpened == nil { heldOpens.append(notification) }

      return onOpened
    }

    Log.write(debug, "opened \(deliveryId)")
    handler?(notification)
    startEventLoop()

    return true
  }

  var currentOnOpened: ((OpenedNotification) -> Void)? {
    lock.withLock { onOpened }
  }

  func setOnOpened(_ handler: ((OpenedNotification) -> Void)?) {
    let held = lock.withLock { () -> [OpenedNotification] in
      onOpened = handler

      guard handler != nil else { return [] }

      let waiting = heldOpens
      heldOpens = []

      return waiting
    }

    guard let handler else { return }

    for notification in held { handler(notification) }
  }

  // MARK: - Events

  /// The batch cap the API enforces. Reaching it is the ordinary case for an app
  /// that has been offline, not an anomaly.
  static let maxEventsPerBatch = 100

  /// A hundred at a time, at least once, until the server takes them.
  ///
  /// At-least-once is the design rather than a concession: the server is
  /// idempotent per delivery and event type, so a replay after a connection
  /// dropped mid-request changes nothing — and that is what makes it safe to keep
  /// an event until a 202 has actually been seen, rather than dropping it the
  /// moment it was handed to the network.
  func startEventLoop() {
    lock.withLock {
      guard eventTask == nil else { return }

      eventTask = Task { [weak self] () -> Void in
        await self?.runEventLoop()
      }
    }
  }

  private func runEventLoop() async {
    var failures = 0

    while !Task.isCancelled {
      let (queued, key, debug) = lock.withLock { (store.events, self.key, debugEnabled) }

      guard !queued.isEmpty, !key.isEmpty else { break }

      let batch = Array(queued.prefix(Engine.maxEventsPerBatch))
      let body = JSON.encode(["events": batch.map { $0.json() }]) ?? Data()
      let request = HTTPRequest(method: "POST", path: "/v1/events", body: body, key: key)

      switch Verdict(await transport.send(request)) {
      case .accepted:
        failures = 0
        drop(batch)
        Log.write(debug, "reported \(batch.count) event(s)")

      case let .retry(reason):
        failures += 1
        let delay = Backoff.delay(afterFailures: failures)
        Log.write(debug, "events deferred (\(reason)); retrying in \(Int(delay))s")

        await clock.sleep(delay)

      case let .refused(problem, status):
        // The batch will be just as invalid in five minutes. Dropped so the
        // queue cannot grow for the life of the install, and logged so the
        // reason is visible rather than inferred from opens that never appear.
        drop(batch)
        Log.write(debug, "events refused: \(problem?.summary ?? "HTTP \(status)")")
      }
    }

    // Cleared and restarted under one acquisition, for the reason the
    // registration loop is: an event queued as this one ends must not wait for
    // the next launch to be reported.
    lock.withLock {
      eventTask = nil

      guard !store.events.isEmpty, !key.isEmpty else { return }

      eventTask = Task { [weak self] () -> Void in
        await self?.runEventLoop()
      }
    }
  }

  /// Removes exactly what was sent, and nothing that arrived meanwhile.
  private func drop(_ batch: [QueuedEvent]) {
    lock.withLock {
      var remaining = store.events

      for event in batch {
        guard let index = remaining.firstIndex(of: event) else { continue }

        remaining.remove(at: index)
      }

      store.events = remaining
    }
  }

  // MARK: - Reading

  func debugInfo() -> DebugInfo {
    lock.withLock {
      DebugInfo(
        sdkVersion: Carillon.sdkVersion,
        key: key,
        endpoint: endpointDescription,
        token: state.token,
        deviceId: store.deviceId,
        environment: state.environment.rawValue,
        bundleId: state.bundleId,
        appBuild: state.appBuild,
        osVersion: state.osVersion,
        pushPermission: state.pushPermission?.rawValue,
        lastRegistrationAt: lastRegistrationAt,
        lastRegistrationResult: lastRegistrationResult,
        queuedEvents: store.events.count
      )
    }
  }

  var currentState: DeviceState {
    lock.withLock { state }
  }

  var isDebugEnabled: Bool {
    lock.withLock { debugEnabled }
  }

  /// Awaits whatever is in flight.
  ///
  /// The SDK never needs this; a test always does, and the alternative is
  /// sprinkling expectations and timeouts over assertions that are otherwise
  /// exact.
  func settle() async {
    while true {
      let tasks = lock.withLock { [registrationTask, eventTask].compactMap { $0 } }

      if tasks.isEmpty { return }

      for task in tasks { await task.value }
    }
  }
}
