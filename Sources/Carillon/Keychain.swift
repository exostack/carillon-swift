import Foundation
import Security

/// The device-bound half of the store: what identifies this installation to the
/// server, and therefore what must never follow a backup onto another handset.
protocol Keychain: AnyObject {
  func read(_ account: String) -> String?
  func write(_ value: String?, account: String)
}

final class SystemKeychain: Keychain {
  private let service: String

  init(service: String = "dev.carillon") {
    self.service = service
  }

  func read(_ account: String) -> String? {
    var query = query(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }

    return String(data: data, encoding: .utf8)
  }

  func write(_ value: String?, account: String) {
    let query = query(account)
    SecItemDelete(query as CFDictionary)

    guard let value else { return }

    var attributes = query
    attributes[kSecValueData as String] = Data(value.utf8)
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(attributes as CFDictionary, nil)
  }

  private func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
