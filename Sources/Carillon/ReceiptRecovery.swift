#if canImport(UIKit)
import Foundation
import UIKit
import UserNotifications
import CarillonReceiptStore

internal enum ReceiptRecovery {
  private static let lock = NSLock()
  private static var observer: NSObjectProtocol?

  static func start() {
    lock.lock()
    if observer == nil {
      observer = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { _ in recover() }
    }
    lock.unlock()
    recover()
  }

  private static func recover() {
    if let group = Bundle.main.object(forInfoDictionaryKey: "CarillonAppGroup") as? String,
      let store = ReceiptStore(appGroup: group) {
      store.drain { receipt in
        Carillon.engine.didReceive(userInfo: ["carillon": ["delivery_id": receipt.id]], at: receipt.at)
      }
    }
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      for notification in notifications {
        Carillon.engine.didReceive(userInfo: notification.request.content.userInfo, at: notification.date)
      }
    }
  }
}
#endif
