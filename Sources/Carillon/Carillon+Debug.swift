#if DEBUG
  import Foundation

  extension Carillon {
    /// Receives debug log lines, also written to the platform logger.
    /// Available only in DEBUG builds.
    public static var onDebugLine: ((String) -> Void)? {
      get { Log.onLine }
      set { Log.onLine = newValue }
    }
  }
#endif
