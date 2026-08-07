import Foundation

/// Mutual exclusion, in the one shape that is safe to use from async code.
///
/// `NSRecursiveLock.lock()` is deliberately unavailable inside an async function,
/// because a lock taken before a suspension point and released after it blocks a
/// thread the cooperative pool needs. A scoped body cannot suspend, so the rule
/// the annotation exists to enforce is enforced by the shape here instead of by
/// remembering it — and the engine can hold state and run network calls without
/// either an actor or a warning.
///
/// Recursive because a mutation records state and then asks, still holding, what
/// to do about it.
final class Lock {
  private let underlying = NSRecursiveLock()

  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    underlying.lock()
    defer { underlying.unlock() }

    return try body()
  }
}
