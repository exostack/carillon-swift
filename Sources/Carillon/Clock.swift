import Foundation

/// The passage of time, injected.
///
/// Both halves are here for the same reason: a backoff schedule that can only be
/// verified by waiting five minutes is a schedule nobody verifies. Reading the
/// instant is separated too, because an event carries the moment it happened and
/// a test asserting that field needs to know what that moment was.
protocol Clock: AnyObject {
  var now: Date { get }
  func sleep(_ seconds: TimeInterval) async
}

final class SystemClock: Clock {
  var now: Date { Date() }

  func sleep(_ seconds: TimeInterval) async {
    guard seconds > 0 else { return }

    // Cancellation is deliberately swallowed: the caller is a retry loop whose
    // next move on cancellation is to stop, which it checks for itself.
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }
}
