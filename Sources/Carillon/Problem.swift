import Foundation

/// An error as the API states it: RFC 9457 Problem Details.
///
/// Parsed rather than ignored because the registry that produces these writes
/// every message to say what to do next. Swallowing the body and logging
/// "registration failed" throws away the one sentence that would have told the
/// developer their token is a `Data` description, or that their key may not
/// register a device.
struct Problem {
  let type: String
  let title: String
  let status: Int
  let code: String
  let detail: String?

  /// Nil when the body is not a problem document — an edge proxy answering with
  /// HTML, most often. The status line still carries the verdict, so a failure
  /// to parse is never a failure to act.
  init?(body: Data) {
    guard
      let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let type = object["type"] as? String,
      let title = object["title"] as? String,
      let status = object["status"] as? Int,
      let code = object["code"] as? String
    else { return nil }

    self.type = type
    self.title = title
    self.status = status
    self.code = code
    self.detail = object["detail"] as? String
  }

  /// What goes in a log line: the class, then this occurrence.
  var summary: String {
    detail.map { "\(code): \($0)" } ?? code
  }
}
