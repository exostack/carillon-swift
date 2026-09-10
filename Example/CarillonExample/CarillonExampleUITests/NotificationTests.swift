import XCTest

final class NotificationTests: XCTestCase {
  func testNotificationPermission() {
    let app = XCUIApplication()
    app.launch()
    addUIInterruptionMonitor(withDescription: "Notifications") { alert in
      if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
      return false
    }
    let request = app.buttons["requestPermission()"]
    XCTAssertTrue(request.waitForExistence(timeout: 10))
    request.tap()
    app.tap()
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
