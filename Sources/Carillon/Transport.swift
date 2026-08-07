import Foundation

/// One call to the API.
///
/// The key travels as a bearer token. It is a mobile key — public by
/// construction, since anyone can pull it out of the binary — which is why it is
/// allowed to do so little: register its own device and report that device's
/// events, and nothing else.
struct HTTPRequest {
  let method: String
  /// Path only. The endpoint is configuration, and a test that had to guess the
  /// host in order to assert the path would be asserting the host.
  let path: String
  let body: Data
  let key: String
}

/// What came back, before anything decides what it means.
enum HTTPOutcome {
  case response(status: Int, body: Data)
  /// No answer at all: offline, DNS, a timeout. Carries the system's own
  /// description, which is what a developer reads in the log.
  case failure(String)
}

protocol Transport: AnyObject {
  func send(_ request: HTTPRequest) async -> HTTPOutcome
}

/// What to do about an outcome. The whole retry policy, as one decision.
///
/// Retry on no answer, on 429 and on 5xx; never on any other 4xx. A 422 retried
/// forever is a bug loop rather than resilience: the payload will be just as
/// invalid in five minutes, and the queue holding it grows for the life of the
/// install.
enum Verdict {
  case accepted(body: Data)
  case retry(reason: String)
  case refused(Problem?, status: Int)

  init(_ outcome: HTTPOutcome) {
    switch outcome {
    case let .failure(reason):
      self = .retry(reason: reason)
    case let .response(status, body):
      if (200..<300).contains(status) {
        self = .accepted(body: body)
      } else if status == 429 || status >= 500 {
        self = .retry(reason: Problem(body: body)?.summary ?? "HTTP \(status)")
      } else {
        self = .refused(Problem(body: body), status: status)
      }
    }
  }
}

final class URLSessionTransport: Transport {
  private let endpoint: URL
  private let session: URLSession

  init(endpoint: URL, session: URLSession = .shared) {
    self.endpoint = endpoint
    self.session = session
  }

  func send(_ request: HTTPRequest) async -> HTTPOutcome {
    guard let url = URL(string: request.path, relativeTo: endpoint) else {
      return .failure("the endpoint could not be combined with \(request.path)")
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(request.key)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("carillon-swift/\(Carillon.sdkVersion)", forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await session.data(for: urlRequest)

      guard let http = response as? HTTPURLResponse else {
        // Reachable only when the endpoint override names a non-HTTP scheme.
        // Treated as no answer, so it retries and stays visible in the log
        // rather than silently dropping the registration.
        return .failure("the endpoint did not answer over HTTP")
      }

      return .response(status: http.statusCode, body: data)
    } catch {
      return .failure(error.localizedDescription)
    }
  }
}
