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


extension ReceivedTests {
  func testSharedRichNotificationFixture() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ConformanceFixtures/notification.json")
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var userInfo = fixture["data"] as! [String: Any]
    userInfo["carillon"] = fixture["carillon"]
    let received = ReceivedNotification(userInfo: userInfo, title: fixture["title"] as? String, body: fixture["body"] as? String)
    XCTAssertEqual(received.deliveryId, "01937b1e-0000-7000-8000-0000000000ff")
    XCTAssertEqual(received.image, "https://example.com/order.png")
    XCTAssertEqual(received.threadId, "orders")
    XCTAssertEqual(received.data["order_id"] as? String, "42")
  }
}
