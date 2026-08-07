import XCTest

@testable import Carillon

/// A stub the URL loading system routes through, so the real transport is
/// exercised — headers, body, status handling — without a network.
final class StubProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse?, Data, Error?))?
  nonisolated(unsafe) static var lastRequest: URLRequest?
  nonisolated(unsafe) static var lastBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    StubProtocol.lastRequest = request
    // URLProtocol strips the body into a stream, which is where a test has to
    // read it back from — `httpBody` is nil by the time it arrives here.
    StubProtocol.lastBody = request.httpBodyStream.map { stream in
      stream.open()
      defer { stream.close() }

      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)

      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(contentsOf: buffer[0..<read])
      }

      return data
    }

    let (response, data, error) = StubProtocol.handler?(request) ?? (nil, Data(), nil)

    if let error {
      client?.urlProtocol(self, didFailWithError: error)

      return
    }

    if let response {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class TransportTests: XCTestCase {
  private func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]

    return URLSession(configuration: configuration)
  }

  override func tearDown() {
    StubProtocol.handler = nil
    StubProtocol.lastRequest = nil
    StubProtocol.lastBody = nil
    super.tearDown()
  }

  func testBuildsTheRequestTheApiExpects() async {
    let endpoint = URL(string: "https://api-staging.carillon.dev")!
    StubProtocol.handler = { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
        Data("{}".utf8), nil
      )
    }

    let transport = URLSessionTransport(endpoint: endpoint, session: session())
    _ = await transport.send(
      HTTPRequest(
        method: "POST", path: "/v1/devices", body: Data(#"{"token":"ab"}"#.utf8),
        key: "carillon_mk_live_abc"))

    let sent = StubProtocol.lastRequest
    XCTAssertEqual(sent?.url?.absoluteString, "https://api-staging.carillon.dev/v1/devices")
    XCTAssertEqual(sent?.httpMethod, "POST")
    XCTAssertEqual(
      sent?.value(forHTTPHeaderField: "Authorization"), "Bearer carillon_mk_live_abc")
    XCTAssertEqual(sent?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(StubProtocol.lastBody, Data(#"{"token":"ab"}"#.utf8))
  }

  func testKeepsThePathWhenTheEndpointCarriesATrailingSlash() async {
    StubProtocol.handler = { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
        Data(), nil
      )
    }

    let transport = URLSessionTransport(
      endpoint: URL(string: "https://api-staging.carillon.dev/")!, session: session())
    _ = await transport.send(
      HTTPRequest(method: "POST", path: "/v1/events", body: Data(), key: "k"))

    XCTAssertEqual(
      StubProtocol.lastRequest?.url?.absoluteString, "https://api-staging.carillon.dev/v1/events")
  }

  func testReportsAFailureToReachTheServerRatherThanThrowing() async {
    StubProtocol.handler = { _ in
      (nil, Data(), URLError(.notConnectedToInternet))
    }

    let transport = URLSessionTransport(
      endpoint: URL(string: "https://api-staging.carillon.dev")!, session: session())
    let outcome = await transport.send(
      HTTPRequest(method: "POST", path: "/v1/devices", body: Data(), key: "k"))

    guard case .failure = outcome else {
      return XCTFail("an unreachable server has to read as no answer, not as a response")
    }
  }
}

final class VerdictTests: XCTestCase {
  func testAcceptsAnythingInTheTwoHundreds() {
    for status in [200, 202, 204] {
      guard case .accepted = Verdict(.response(status: status, body: Data())) else {
        return XCTFail("\(status) is a success")
      }
    }
  }

  func testRetriesWhatTimeMightFix() {
    // No answer, a rate limit, and a server having a bad minute. None of the
    // three says anything is wrong with the request.
    for outcome: HTTPOutcome in [
      .failure("offline"),
      .response(status: 429, body: Data()),
      .response(status: 500, body: Data()),
      .response(status: 503, body: Data()),
    ] {
      guard case .retry = Verdict(outcome) else { return XCTFail("\(outcome) is worth retrying") }
    }
  }

  func testRefusesTheRestOfTheFourHundredsOnceAndForAll() {
    for status in [400, 401, 403, 404, 422] {
      guard case .refused = Verdict(.response(status: status, body: Data())) else {
        return XCTFail("\(status) will not be fixed by trying again")
      }
    }
  }

  func testCarriesTheProblemSoTheLogCanSayWhatToDoNext() {
    let body = problemBody(
      code: "invalid_request", status: 422, title: "The request could not be understood",
      detail: "An APNs token is hexadecimal.")

    guard case let .refused(problem, status) = Verdict(.response(status: 422, body: body)) else {
      return XCTFail("a 422 is a refusal")
    }

    XCTAssertEqual(status, 422)
    XCTAssertEqual(problem?.code, "invalid_request")
    XCTAssertEqual(problem?.title, "The request could not be understood")
    XCTAssertEqual(problem?.detail, "An APNs token is hexadecimal.")
    XCTAssertEqual(problem?.summary, "invalid_request: An APNs token is hexadecimal.")
  }

  func testSurvivesABodyThatIsNotAProblemDocument() {
    // An edge answering with HTML, most often. The status line still carries the
    // verdict, so failing to parse must never be failing to act.
    guard case let .refused(problem, status) = Verdict(
      .response(status: 403, body: Data("<html>Forbidden</html>".utf8)))
    else { return XCTFail("a 403 is a refusal whatever the body says") }

    XCTAssertNil(problem)
    XCTAssertEqual(status, 403)
  }

  func testAProblemWithoutADetailStillNamesItsClass() {
    let problem = Problem(body: problemBody(code: "rate_limited", status: 429))

    XCTAssertEqual(problem?.summary, "rate_limited")
  }
}
