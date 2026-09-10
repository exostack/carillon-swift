import UserNotifications
import CarillonNotificationExtension

final class NotificationService: UNNotificationServiceExtension {
  private var helper: CarillonNotificationExtension?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
    helper = CarillonNotificationExtension.didReceive(request, withContentHandler: handler)
  }

  override func serviceExtensionTimeWillExpire() {
    CarillonNotificationExtension.serviceExtensionTimeWillExpire(helper)
  }
}
