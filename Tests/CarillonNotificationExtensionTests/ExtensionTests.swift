import XCTest
import UserNotifications
@testable import CarillonNotificationExtension

final class ExtensionTests: XCTestCase {
  func testMissingImageFallsBackExactlyOnce() {
    let content = UNMutableNotificationContent()
    content.title = "Hello"
    var calls = 0
    let helper = CarillonNotificationExtension(content: content) { received in
      calls += 1
      XCTAssertEqual(received.title, "Hello")
    }
    helper.start(configuration: .ephemeral)
    CarillonNotificationExtension.serviceExtensionTimeWillExpire(helper)
    helper.finish()
    XCTAssertEqual(calls, 1)
  }

  func testNonHTTPSFallsBack() {
    let content = UNMutableNotificationContent()
    content.userInfo = ["carillon": ["image": "http://example.com/image.jpg"]]
    var calls = 0
    let helper = CarillonNotificationExtension(content: content) { _ in calls += 1 }
    helper.start(configuration: .ephemeral)
    XCTAssertEqual(calls, 1)
  }

  func testMIMEProvidesAnExtensionForSignedURLs() {
    XCTAssertEqual(CarillonNotificationExtension.fileExtension(mime: "image/png", url: URL(string: "https://example.com/download?signature=x")), "png")
    XCTAssertEqual(CarillonNotificationExtension.fileExtension(mime: nil, url: URL(string: "https://example.com/image.gif")), "gif")
  }
}

private final class ImageProtocol: URLProtocol {
  static var reply: (ImageProtocol) -> Void = { _ in }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.reply(self) }
  override func stopLoading() {}
}

extension ExtensionTests {
  func testDownloadsAnImageWithoutAFileExtension() async {
    ImageProtocol.reply = { connection in
      let response = HTTPURLResponse(url: connection.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/gif"])!
      connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
      connection.client?.urlProtocol(connection, didLoad: Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!)
      connection.client?.urlProtocolDidFinishLoading(connection)
    }
    let done = expectation(description: "image attached")
    let content = UNMutableNotificationContent()
    content.title = "Hello"
    content.userInfo = ["carillon": ["image": "https://example.com/download"]]
    let helper = CarillonNotificationExtension(content: content) { received in
      XCTAssertEqual(received.title, "Hello")
      XCTAssertEqual(received.attachments.count, 1)
      done.fulfill()
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageProtocol.self]
    helper.start(configuration: configuration)
    await fulfillment(of: [done], timeout: 30)
    helper.finish()
  }

  func testHTTPFailureFallsBackToText() async {
    ImageProtocol.reply = { connection in
      let response = HTTPURLResponse(url: connection.request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!
      connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
      connection.client?.urlProtocolDidFinishLoading(connection)
    }
    let done = expectation(description: "fallback")
    let content = UNMutableNotificationContent()
    content.title = "Hello"
    content.userInfo = ["carillon": ["image": "https://example.com/missing"]]
    let helper = CarillonNotificationExtension(content: content) { received in
      XCTAssertEqual(received.title, "Hello")
      XCTAssertTrue(received.attachments.isEmpty)
      done.fulfill()
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageProtocol.self]
    helper.start(configuration: configuration)
    await fulfillment(of: [done], timeout: 30)
  }
}


extension ExtensionTests {
  func testInvalidImageAndNetworkErrorsKeepTheOriginalContent() async {
    for mode in ["html", "oversize", "network", "expiry"] {
      ImageProtocol.reply = { connection in
        if mode == "expiry" { return }
        if mode == "network" {
          connection.client?.urlProtocol(connection, didFailWithError: URLError(.timedOut))
          return
        }
        let headers = mode == "html" ? ["Content-Type": "text/html"] : ["Content-Type": "image/png", "Content-Length": "11000000"]
        let response = HTTPURLResponse(url: connection.request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
        connection.client?.urlProtocol(connection, didLoad: Data("not an image".utf8))
        connection.client?.urlProtocolDidFinishLoading(connection)
      }
      let done = expectation(description: mode)
      let content = UNMutableNotificationContent()
      content.title = "Original"
      content.userInfo = ["carillon": ["image": "https://example.com/image.png"]]
      let helper = CarillonNotificationExtension(content: content) { result in
        XCTAssertEqual(result.title, "Original")
        XCTAssertTrue(result.attachments.isEmpty)
        done.fulfill()
      }
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [ImageProtocol.self]
      helper.start(configuration: configuration)
      if mode == "expiry" { CarillonNotificationExtension.serviceExtensionTimeWillExpire(helper) }
      await fulfillment(of: [done], timeout: 30)
      helper.finish()
    }
  }

  func testADownloadThatNeverAnswersTimesOutToTheOriginalContent() async {
    ImageProtocol.reply = { _ in }
    let done = expectation(description: "timed out")
    let content = UNMutableNotificationContent()
    content.title = "Original"
    content.userInfo = ["carillon": ["image": "https://example.com/slow.png"]]
    var calls = 0
    let helper = CarillonNotificationExtension(content: content) { result in
      calls += 1
      XCTAssertEqual(result.title, "Original")
      XCTAssertTrue(result.attachments.isEmpty)
      done.fulfill()
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageProtocol.self]
    helper.start(configuration: configuration, timeout: 0.2)
    await fulfillment(of: [done], timeout: 30)
    helper.finish()
    XCTAssertEqual(calls, 1)
  }
}
