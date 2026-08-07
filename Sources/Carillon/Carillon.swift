import Foundation

/// Carillon iOS SDK.
///
/// Native, zero dependencies. The public surface is additive forever: this code
/// ships inside customer binaries and cannot be updated by us, so a mistake here
/// is paid for in app-store release cycles rather than in a deploy.
///
/// ```swift
/// Carillon.configure(key: "carillon_mk_live_…", debug: true)
/// await Carillon.register()
/// ```
///
/// Then two lines in the app delegate, forwarded explicitly — the SDK swizzles
/// nothing. See `didRegister(token:)` and `didOpen(_:)`.
public enum Carillon {
  /// The SDK version reported at registration.
  public static let sdkVersion = "0.1.0"

  /// Production. Overridden for staging, and for nothing else.
  public static let defaultEndpoint = "https://api.carillon.dev"

  private static let installLock = NSLock()
  private static var installed: Engine?

  /// The engine, built on first use.
  ///
  /// It exists before `configure` is called so that a callback arriving early —
  /// an app launched by a tap runs its delegate before anything else — is held
  /// rather than dropped. Without a key it sends nothing; it just remembers.
  static var engine: Engine {
    installLock.lock()
    defer { installLock.unlock() }

    if let installed { return installed }

    let endpoint = URL(string: defaultEndpoint)!
    let engine = Engine(
      store: UserDefaultsStore(),
      transport: URLSessionTransport(endpoint: endpoint),
      clock: SystemClock(),
      environment: ProvisioningProfile.environment()
    )
    installed = engine

    return engine
  }

  /// Replaces the engine. Used by the tests, and by nothing that ships.
  static func install(_ engine: Engine?) {
    installLock.lock()
    installed = engine
    installLock.unlock()
  }

  // MARK: - Configuration

  /// Configures the SDK. Call once, early, before anything else.
  ///
  /// - Parameters:
  ///   - key: a mobile key, `carillon_mk_live_…` or `carillon_mk_test_…`. It is
  ///     public by construction — it ships inside this binary — which is why it
  ///     can only register this device and report this device's events.
  ///   - endpoint: the API. Defaults to production; override it for staging.
  ///   - debug: verbose logging. Honoured only in a debug build: the logging
  ///     paths are compiled out of a release, so a `true` left in shipped code
  ///     logs nothing and costs nothing.
  public static func configure(
    key: String,
    endpoint: String = defaultEndpoint,
    debug: Bool = false
  ) {
    // An unusable endpoint falls back to production rather than throwing. This
    // is called from `didFinishLaunching`; a crash there is a customer's app
    // failing to start over a typo in a staging URL.
    let url = URL(string: endpoint) ?? URL(string: defaultEndpoint)!

    engine.configure(
      key: key,
      endpoint: url,
      debug: debug,
      transport: URLSessionTransport(endpoint: url)
    )
    refreshAttributes()
  }

  // MARK: - The state the app owns

  /// Your own identifier for the person using this device.
  ///
  /// An attribute of the device, never an entity: one person on two handsets is
  /// two devices, and both carry the same identifier.
  public static func identify(_ externalId: String) {
    engine.identify(externalId)
  }

  /// Forgets the identifier. The device stays registered and reachable — this
  /// says who is using it is no longer known, not that it should stop receiving.
  public static func clearIdentity() {
    engine.identify(nil)
  }

  /// Replaces the tags whole.
  ///
  /// The SDK holds the canonical map and the server replaces what it holds, so
  /// this is the complete set every time. Merging would make removing a tag
  /// impossible without inventing a word for "remove".
  public static func setTags(_ tags: [String: TagValue]) {
    engine.setTags(tags)
  }

  /// Opts the device back in. Notifications resume at the next send.
  public static func optIn() {
    engine.setOptedIn(true)
  }

  /// Opts the device out. The row stays, so the person can be opted back in, and
  /// so the customer can still see that this handset exists.
  public static func optOut() {
    engine.setOptedIn(false)
  }

  // MARK: - The delegate callbacks the app forwards

  /// Forwarded from
  /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
  ///
  /// Takes the `Data` APNs handed over and hex-encodes it here, so the customer
  /// never holds the string. Passing `token.description` instead is the single
  /// most common integration mistake there is, and this is the shape that makes
  /// it impossible.
  public static func didRegister(token: Data) {
    refreshAttributes()
    engine.setToken(Hex.encode(token))
  }

  // MARK: - Opens

  /// Called when a notification sent by Carillon is opened.
  ///
  /// Set it once, wherever the app decides what a tap means. An open that
  /// arrived before a handler was attached — a cold start, which is the most
  /// valuable tap there is — is delivered as soon as one is.
  public static var onOpened: ((OpenedNotification) -> Void)? {
    get { engine.currentOnOpened }
    set { engine.setOnOpened(newValue) }
  }

  // MARK: - Support

  /// One value, made to be pasted into a support ticket.
  ///
  /// Available in every configuration, release included. Debug logging speaks
  /// unprompted and is absent from a release; this answers when asked, and
  /// answering is never the wrong thing to do.
  public static func debugInfo() -> DebugInfo {
    engine.debugInfo()
  }

  /// What the operating system can answer for itself, re-read rather than
  /// remembered: a person who changes their phone's language has changed which
  /// text they should be sent.
  static func refreshAttributes(bundle: Bundle = .main) {
    engine.refreshDeviceAttributes(
      timezoneId: TimeZone.current.identifier,
      locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )
    // The push environment is an environment fact, not a stored one: state
    // persisted before a fix — or restored on a machine whose world changed —
    // must never outvote what the binary can observe right now. A sandbox
    // token pushed at the production host answers BadEnvironmentKeyInToken,
    // and that is exactly how this line earned its place.
    #if targetEnvironment(simulator)
      engine.setEnvironment(.sandbox)
    #else
      engine.setEnvironment(ProvisioningProfile.environment(in: bundle))
    #endif
  }
}
