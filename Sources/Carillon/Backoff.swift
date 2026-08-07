import Foundation

/// How long to wait before the next attempt.
///
/// Doubling from one second to a ceiling of five minutes. The ceiling matters
/// more than the curve: a device that has been offline all day must keep trying
/// often enough to register within a minute of coming back, and an SDK that has
/// backed off to an hour looks exactly like an SDK that is broken.
///
/// A pure function of the attempt number, so the schedule is a thing that can be
/// asserted rather than a behaviour that has to be waited for.
enum Backoff {
  static let base: TimeInterval = 1
  static let ceiling: TimeInterval = 300

  /// `attempt` is the number of failures so far, so the first retry is `base`.
  static func delay(afterFailures attempt: Int) -> TimeInterval {
    guard attempt > 0 else { return 0 }

    // Capped before the shift, not after: 1 << 62 seconds is not a long wait,
    // it is an overflow trap on a 64-bit `Int`.
    let doublings = min(attempt - 1, 16)

    return min(base * TimeInterval(1 << doublings), ceiling)
  }
}
