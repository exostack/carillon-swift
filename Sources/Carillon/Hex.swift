import Foundation

/// The device token, as the server has always been told to expect it.
///
/// APNs hands the token over as `Data`, and the single most common integration
/// mistake in this whole SDK is forwarding `token.description` instead: on older
/// runtimes that produced `<a1b2 c3d4 …>`, and on newer ones it produces
/// something else again. The server refuses both, but by then the customer has
/// shipped. Doing the encoding here means the customer never holds the string.
///
/// Lowercase, because the server folds case on iOS tokens and two spellings of
/// one token would otherwise become two devices: counted twice, sent to twice,
/// and only half of it struck off when Apple forgets the token.
enum Hex {
  static func encode(_ data: Data) -> String {
    // Built from a byte table rather than `String(format:)` per byte, which
    // allocates a formatter's worth of work for every one of 32 bytes on a path
    // that runs at every app start.
    let digits = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    out.reserveCapacity(data.count * 2)

    for byte in data {
      out.append(digits[Int(byte >> 4)])
      out.append(digits[Int(byte & 0x0f)])
    }

    return String(decoding: out, as: UTF8.self)
  }
}
