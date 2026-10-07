import Foundation

public struct Receipt: Codable {
  public let id: String
  public let at: Date
}

/// One atomic file per receipt avoids cross-process read/modify/write races.
public final class ReceiptStore {
  private let directory: URL

  public convenience init?(appGroup: String) {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
    self.init(directory: container.appendingPathComponent("CarillonReceipts", isDirectory: true))
  }

  public init(directory: URL) { self.directory = directory }

  public func record(id: String, at: Date) {
    guard let uuid = UUID(uuidString: id) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(uuid.uuidString + ".json")
    guard !FileManager.default.fileExists(atPath: file.path),
      let data = try? JSONEncoder().encode(Receipt(id: id, at: at)) else { return }
    try? data.write(to: file, options: .atomic)
  }

  public func drain(consume: (Receipt) -> Bool) {
    guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file),
        let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else { continue }
      if consume(receipt) { try? FileManager.default.removeItem(at: file) }
    }
  }
}
