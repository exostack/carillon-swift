import Foundation

#if DEBUG
  import os
#endif

/// Verbose logging, present only in a debug build.
///
/// Not silenced by a flag — absent. Under `#if DEBUG` the calls below compile to
/// nothing in a release build, and the package is built with the app's own
/// configuration, so a `debug: true` left in shipped code logs nothing and costs
/// nothing. Nobody ships a support incident because a flag survived a release.
///
/// `debugInfo()` stays available everywhere: it answers when asked, where this
/// speaks unprompted.
enum Log {
  #if DEBUG
    private static let log = OSLog(subsystem: "dev.carillon", category: "Carillon")

    /// A second destination for the same lines, so a test bench can show them in
    /// the app rather than sending the developer to Console. Debug-only, like
    /// everything else here.
    static var onLine: ((String) -> Void)?

    static func write(_ enabled: Bool, _ message: @autoclosure () -> String) {
      guard enabled else { return }

      let line = message()
      os_log("%{public}@", log: log, type: .debug, line)
      onLine?(line)
    }
  #else
    static func write(_ enabled: Bool, _ message: @autoclosure () -> String) {}
  #endif
}
