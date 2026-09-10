import XCTest
@testable import Carillon

final class ReceivedTests: XCTestCase {
  func testSeparatesCustomerDataFromProviderMetadata() {
    let received = ReceivedNotification(userInfo: ["aps": ["alert": "Hello"], "carillon": ["delivery_id": "id", "image": "https://example.com/a.jpg", "thread_id": "orders"], "order": "123"], title: "Hello", body: "World")
    XCTAssertEqual(received.deliveryId, "id")
    XCTAssertEqual(received.threadId, "orders")
    XCTAssertEqual(received.data.count, 1)
    XCTAssertEqual(received.data["order"] as? String, "123")
  }

  func testExposesOtherNotificationsWithoutForgingADeliveryID() {
    let received = ReceivedNotification(userInfo: ["order": "123"], title: "Hello", body: nil)
    XCTAssertNil(received.deliveryId)
    XCTAssertNil(received.image)
    XCTAssertNil(received.threadId)
  }
}
