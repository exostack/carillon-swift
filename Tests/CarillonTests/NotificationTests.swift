import UserNotifications
import XCTest

@testable import Carillon

/// The facade's notification-center surface, exercised against an installed
/// engine with the system calls replaced.
final class NotificationTests: XCTestCase {
  private var engine: Engine!

  override func setUp() {
    engine = makeEngine()
    Carillon.install(engine)
  }

  override func tearDown() {
    Carillon.install(nil)
    Carillon.onReceived = nil
    Carillon.authorizationStatus = {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    Carillon.removeAllDeliveredNotifications = {
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
  }

  private let stamped: [AnyHashable: Any] = [
    "aps": ["alert": ["title": "Hello", "body": "World"]],
    "carillon": ["delivery_id": "01937b1e-0000-7000-8000-0000000000ff"],
    "order": "42",
  ]

  func testSuppressHandsBackNoPresentationOptions() {
    Carillon.onReceived = { _ in .suppress }

    XCTAssertEqual(Carillon.willPresent(userInfo: stamped), [])
  }

  func testWithoutAHandlerTheSystemPresentsEverything() {
    XCTAssertEqual(Carillon.willPresent(userInfo: stamped), [.banner, .list, .sound, .badge])
  }

  func testShowHandsBackEveryPresentationOption() {
    Carillon.onReceived = { _ in .show }

    XCTAssertEqual(Carillon.willPresent(userInfo: stamped), [.banner, .list, .sound, .badge])
  }

  func testReadsTitleBodyAndDataFromThePayload() {
    var received: ReceivedNotification?
    Carillon.onReceived = { received = $0; return .show }

    _ = Carillon.willPresent(userInfo: stamped)

    XCTAssertEqual(received?.deliveryId, "01937b1e-0000-7000-8000-0000000000ff")
    XCTAssertEqual(received?.title, "Hello")
    XCTAssertEqual(received?.body, "World")
    XCTAssertEqual(received?.data["order"] as? String, "42")
  }

  func testAPlainStringAlertIsTheBody() {
    var received: ReceivedNotification?
    Carillon.onReceived = { received = $0; return .show }

    _ = Carillon.willPresent(userInfo: ["aps": ["alert": "Just text"]])

    XCTAssertNil(received?.title)
    XCTAssertEqual(received?.body, "Just text")
  }

  func testANotificationWithoutAStampReachesTheHandlerWithoutADeliveryId() {
    var received: ReceivedNotification?
    Carillon.onReceived = { received = $0; return .suppress }

    let options = Carillon.willPresent(userInfo: ["aps": ["alert": "Hello"], "order": "42"])

    XCTAssertNotNil(received)
    XCTAssertNil(received?.deliveryId)
    XCTAssertEqual(received?.data["order"] as? String, "42")
    XCTAssertEqual(options, [])
  }

  func testClearNotificationsRemovesEverythingDelivered() {
    var calls = 0
    Carillon.removeAllDeliveredNotifications = { calls += 1 }

    Carillon.clearNotifications()

    XCTAssertEqual(calls, 1)
  }

  func testDidOpenWithAPayloadQueuesTheOpen() async {
    Carillon.didOpen(userInfo: stamped)
    Carillon.didOpen(userInfo: ["aps": ["alert": "Hello"]])

    XCTAssertEqual(engine.debugInfo().queuedEvents, 1)

    await engine.settle()
  }

  func testGetPermissionReadsWithoutPromptingAndSyncs() async {
    Carillon.authorizationStatus = { .denied }

    let permission = await Carillon.getPermission()

    XCTAssertEqual(permission, .denied)
    XCTAssertEqual(engine.currentState.pushPermission, .denied)

    await engine.settle()
  }

  func testCanRequestPermissionOnlyWhileNobodyHasBeenAsked() async {
    Carillon.authorizationStatus = { .notDetermined }
    let before = await Carillon.canRequestPermission()

    Carillon.authorizationStatus = { .authorized }
    let after = await Carillon.canRequestPermission()

    XCTAssertTrue(before)
    XCTAssertFalse(after)
    XCTAssertEqual(engine.currentState.pushPermission, .allowed)

    await engine.settle()
  }
}
