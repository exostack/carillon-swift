#if DEBUG
  import Foundation

  extension Carillon {
    /// Every debug line, as it is written.
    ///
    /// The lines already go to the platform's own logger under the `Carillon`
    /// category, which is where they belong. This exists for the one case that
    /// cannot reach Console: a test bench showing what the SDK is doing inside
    /// the app itself, on a device in someone's hand.
    ///
    /// Debug-only, like the logging it mirrors — the whole file is compiled out
    /// of a release build, so this cannot become something an app depends on in
    /// production.
    public static var onDebugLine: ((String) -> Void)? {
      get { Log.onLine }
      set { Log.onLine = newValue }
    }
  }
#endif
