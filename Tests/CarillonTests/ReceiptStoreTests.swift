import XCTest
import CarillonReceiptStore

final class ReceiptStoreTests: XCTestCase {
  func testPersistsUntilConsumedAndKeepsFirstReceipt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ReceiptStore(directory: directory)
    let id = UUID().uuidString
    let at = Date(timeIntervalSince1970: 1_790_000_000)
    store.record(id: "../invalid", at: at)
    store.record(id: id, at: at)
    store.record(id: id, at: at.addingTimeInterval(10))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    let restored = ReceiptStore(directory: directory)
    restored.drain { receipt in
      XCTAssertEqual(receipt.id, id)
      XCTAssertEqual(receipt.at, at)
      return false
    }
    var consumed = 0
    restored.drain { _ in consumed += 1; return true }
    restored.drain { _ in XCTFail("Already consumed"); return true }
    XCTAssertEqual(consumed, 1)
  }

  func testMissingDirectoryAndMalformedReceiptDoNotInterruptRecovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ReceiptStore(directory: directory)
    store.drain { _ in XCTFail("Empty store"); return true }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("invalid".utf8).write(to: directory.appendingPathComponent("broken.json"))
    store.record(id: UUID().uuidString, at: Date())
    var consumed = 0
    store.drain { _ in consumed += 1; return true }
    XCTAssertEqual(consumed, 1)
  }
}
