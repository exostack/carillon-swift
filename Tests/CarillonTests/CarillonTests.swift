import XCTest
@testable import Carillon

final class CarillonTests: XCTestCase {
  func testVersionIsSemver() {
    XCTAssertFalse(Carillon.sdkVersion.isEmpty)
    XCTAssertEqual(Carillon.sdkVersion.split(separator: ".").count, 3)
  }
}
