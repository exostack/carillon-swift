import Foundation

public enum NotificationPresentation { case show, suppress }

public struct ReceivedNotification {
  public let deliveryId: String?
  public let title: String?
  public let body: String?
  public let data: [AnyHashable: Any]
  public let image: String?
  public let threadId: String?

  public init(userInfo: [AnyHashable: Any], title: String?, body: String?) {
    let stamp = userInfo["carillon"] as? [String: Any]
    self.deliveryId = stamp?["delivery_id"] as? String
    self.title = title
    self.body = body
    self.image = stamp?["image"] as? String
    self.threadId = stamp?["thread_id"] as? String
    self.data = userInfo.filter { ($0.key as? String) != "aps" && ($0.key as? String) != "carillon" }
  }
}
