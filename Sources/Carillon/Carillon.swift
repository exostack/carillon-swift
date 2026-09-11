import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// Carillon iOS SDK. Configure at app startup and forward APNs registration
/// and notification-open callbacks. See the README for setup.
public enum Carillon {
  /// The SDK version reported at registration.
  public static let sdkVersion = "0.2.0"

  /// Default API endpoint. Override for staging or local development.
  public static let defaultEndpoint = "https://api.carillon.dev"

  private static let installLock = NSLock()
  private static var installed: Engine?

  /// Created before configure so early notification opens can be buffered.
  /// No requests are sent until a key and token are available.
  static var engine: Engine {
    installLock.lock()
    defer { installLock.unlock() }

    if let installed { return installed }

    let endpoint = URL(string: defaultEndpoint)!
    let engine = Engine(
      store: UserDefaultsStore(keychain: SystemKeychain()),
      transport: URLSessionTransport(endpoint: endpoint),
      clock: SystemClock(),
      environment: ProvisioningProfile.environment()
    )
    installed = engine

    return engine
  }

  /// Replaces the engine for tests.
  static func install(_ engine: Engine?) {
    installLock.lock()
    installed = engine
    installLock.unlock()
  }

  // MARK: - Configuration

  /// Starts APNs token acquisition and device registration without a permission prompt.
  /// Call once at app startup. Registration requires a token and network access.
  /// Use requestPermission() separately to request notification display permission.
  ///
  /// - Parameters:
  ///   - key: Mobile API key from the Carillon dashboard.
  ///   - endpoint: API base URL. Defaults to production.
  ///   - debug: Enables logging in debug builds only.
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

    #if canImport(UIKit)
      // Asked for now, with nothing asked of anybody: a push token is transport
      // addressing, not consent. Waiting for a prompt would make the customer's
      // base the subset of people who were asked and said yes — a measure of
      // their onboarding rather than of their reach.
      Task { await requestPushToken() }
    #endif
  }

  // MARK: - The state the app owns

  /// Sets the external user id for this device. Multiple devices may share an id.
  public static func identify(_ externalId: String) {
    engine.identify(externalId)
  }

  /// Clears the external user id without opting out or deleting the device.
  public static func clearIdentity() {
    engine.identify(nil)
  }

  /// Replaces all device tags. Omitted tags are removed.
  public static func setTags(_ tags: [String: TagValue]) {
    engine.setTags(tags)
  }

  /// Sets opted_in to true and syncs it to the server. Does not change OS permission.
  public static func optIn() {
    engine.setOptedIn(true)
  }

  /// Sets opted_in to false and syncs it to the server. Keeps the device registered.
  public static func optOut() {
    engine.setOptedIn(false)
  }

  // MARK: - The delegate callbacks the app forwards

  /// Forward application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
  /// Pass the original APNs Data token; the SDK hex-encodes it.
  public static func didRegister(token: Data) {
    refreshAttributes()
    engine.setToken(Hex.encode(token))
  }

  // MARK: - Opens

  /// Handles notification opens. Opens received before a handler is attached are replayed when it is set.
  public static var onOpened: ((OpenedNotification) -> Void)? {
    get { engine.currentOnOpened }
    set { engine.setOnOpened(newValue) }
  }

  /// Records an open from a notification payload. Queues an open for the payload
  /// delivery id and ignores payloads without one. For hosts whose
  /// notification-center delegate belongs to another library.
  public static func didOpen(userInfo: [AnyHashable: Any]) {
    engine.didOpen(userInfo: userInfo)
  }

  /// The last confirmed registration ID, or nil before registration succeeds.
  public static var deviceId: String? { engine.debugInfo().deviceId }

  /// Fires after the first successful registration and whenever its ID changes.
  /// A handler set while an ID is already known is called once with it.
  public static var onDeviceIdChanged: ((String) -> Void)? {
    get { engine.onDeviceIdChanged }
    set { engine.onDeviceIdChanged = newValue }
  }

  /// Called for foreground notifications. Returning suppress hides their system presentation.
  public static var onReceived: ((ReceivedNotification) -> NotificationPresentation)? {
    get { engine.onReceived }
    set { engine.onReceived = newValue }
  }

  // MARK: - Support

  /// Returns SDK configuration, registration status, and queued-event count. Available in release builds.
  public static func debugInfo() -> DebugInfo {
    engine.debugInfo()
  }

  /// Refreshes device attributes from current system settings.
  static func refreshAttributes(bundle: Bundle = .main) {
    engine.refreshDeviceAttributes(
      timezoneId: TimeZone.current.identifier,
      locale: localeTag(),
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      // The build behind that version. Two TestFlight uploads of "2.1.0" are one
      // app_version and two builds, and the build is the one that identifies
      // which of them a handset in the field is actually running.
      appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      bundleId: bundle.bundleIdentifier
    )

    #if canImport(UIKit)
      // The OS version and the notification permission, which only a running iOS
      // app can answer and neither of which answers synchronously. Detached
      // rather than awaited because this call site is `didFinishLaunching`: the
      // state lands a moment later and the registration loop picks it up, which
      // is the same path every other attribute already takes.
      Task { await refreshEnvironmentFacts() }
    #endif

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

  /// A BCP 47 tag of language, script where it disambiguates, and region.
  ///
  /// The raw identifier carries `@rg=` and `@calendar=` overrides when a person
  /// has set a region or calendar apart from their language, and a tag with
  /// those in it matches no localisation. `Locale.region` answers the `rg`
  /// override, so the region is the language's own.
  static func localeTag(_ locale: Locale = .current) -> String {
    if #available(iOS 16, macOS 13, *), let code = locale.language.languageCode?.identifier {
      let minimal = Locale.Language.Components(identifier: locale.language.minimalIdentifier)

      return [code, minimal.script?.identifier, locale.language.region?.identifier]
        .compactMap { $0 }
        .joined(separator: "-")
    }

    return locale.identifier
      .prefix { $0 != "@" }
      .split(separator: "_")
      .prefix(3)
      .joined(separator: "-")
  }

  static func currentOSVersion() async -> String? {
    #if canImport(UIKit)
      return await MainActor.run { UIDevice.current.systemVersion }
    #else
      return nil
    #endif
  }
}
