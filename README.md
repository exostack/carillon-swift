# carillon-swift

Carillon SDK for iOS 15 and later. Requires Swift 5.9 or later.

## Install

Add `https://github.com/exostack/carillon-swift` as a Swift Package Manager
dependency and select the `Carillon` product.

Enable the **Push Notifications** capability on the app target. In Carillon,
upload an APNs credential for the app bundle identifier and copy a mobile key.

## Configure

Call once at app startup:

```swift
import Carillon

Carillon.configure(key: "YOUR_MOBILE_KEY", debug: true)
```

This starts APNs token acquisition and device registration without a permission
prompt. Registration completes after a token is available and the API is reachable.
For staging or local development, pass an API base URL as `endpoint`.
Debug logging is disabled in release builds.

## Forward callbacks

Set `UNUserNotificationCenter.current().delegate` to your notification delegate
during `didFinishLaunching`. Forward registration callbacks from the app delegate
and opens from the notification delegate:

```swift
func application(_ app: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
  Carillon.didRegister(token: token)
}

func application(_ app: UIApplication,
                 didFailToRegisterForRemoteNotificationsWithError error: Error) {
  Carillon.didFailToRegister(error)
}

func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completion: @escaping () -> Void) {
  Carillon.didOpen(response)
  completion()
}
```

Pass the APNs token as `Data`; the SDK encodes it. The SDK does not install these
callbacks automatically.

If another library owns `UNUserNotificationCenter.current().delegate`, forward
the payload it hands you instead:

```swift
Carillon.didOpen(userInfo: response.notification.request.content.userInfo)

let options = Carillon.willPresent(userInfo: notification.request.content.userInfo)
```

`didOpen(userInfo:)` queues the open exactly as `didOpen(_:)` does.
`willPresent(userInfo:)` runs `onReceived` and returns the presentation options
to pass to the system's completion handler. Both accept any payload: one without
a Carillon stamp is ignored by the first and reaches `onReceived` with
`deliveryId == nil` through the second.

## Request permission

```swift
let permission = await Carillon.requestPermission()
```

Requests alert, badge, and sound authorization. Returns the current permission
and syncs it to Carillon. Registration and notification display permission are
separate: `configure` does not display this prompt.

```swift
let current = await Carillon.getPermission()
if await Carillon.canRequestPermission() {
  await Carillon.requestPermission()
} else if current == .denied {
  Carillon.openNotificationSettings()
}
```

`getPermission()` reads the current permission without prompting and syncs it
to Carillon. `canRequestPermission()` is true only while the prompt has never
been shown; iOS shows it once, so after a refusal the only way back is the app's
notification settings, which `openNotificationSettings()` opens.

## Update the device

```swift
Carillon.identify("user-42")
Carillon.setTag("plan", "pro")
Carillon.setTagNumber("seats", 12)
Carillon.setTag("language", "fr")
Carillon.removeTagNumber("seats")
Carillon.removeTag("language")
Carillon.clearIdentity()
Carillon.optOut()
Carillon.optIn()
```

Tags merge with existing keys, including tags written by your backend. Use `setTag` to update one key and `removeTag` to delete one. In `setTags`, a null value (`nil` in Swift) removes that key; omitted keys are preserved. Clearing identity keeps the device registered.
Opt-in changes sync to the server and do not change OS permission.

## Handle opens

```swift
Carillon.onOpened = { notification in
  print(notification.deliveryId)
  print(notification.userInfo)
}
```

Opens received before the handler is set are replayed when it attaches.

## Verify registration

```swift
print(Carillon.debugInfo())
```

Check `device_id` and `last_registration_result`. If registration has not
completed, check the token, endpoint, and APNs callback errors. Send a test
notification from the dashboard, tap it, and check that `onOpened` runs.
Diagnostics include the mobile key and token and are available in release builds.

## Develop

`Sources/` contains the library; `Example/` contains a separate test app.
Run host tests from the repository root:

```sh
swift test
```

Host tests do not exercise UIKit callbacks. Build the example on an iOS device
or simulator to verify platform integration.

`Tests/ConformanceFixtures/` defines shared registration and event requests.
Regenerate only for an intentional protocol change, then update the other SDKs:

```sh
CARILLON_WRITE_FIXTURES=1 swift test
```


## Device identity

```swift
let id = Carillon.deviceId
Carillon.onDeviceIdChanged = { id in print(id) }
```

The SDK persists a random installation secret and the last confirmed device ID.
Token rotation reuses that ID when the server validates the proof. Merging with
an existing token registration can change the ID. The callback fires on first
registration and when the confirmed ID changes; a handler set while an ID is
already known is called once with it, so subscribing after registration
completed still delivers it. The ID itself is not a credential. Never log or
export the installation secret.

The secret and the device ID are stored in the Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Device state, the last
registered fingerprint and queued events stay in `UserDefaults`. A backup
restored onto another device therefore carries the state but not the identity:
the restored app generates a new secret and registers as a new device, and the
original device keeps its row. An install upgraded from a version that kept the
secret in `UserDefaults` moves it to the Keychain on first run and keeps its
identity.

## Foreground notifications

Forward the notification-center callback explicitly:

```swift
func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  willPresent notification: UNNotification,
  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
  Carillon.willPresent(notification, completionHandler: completionHandler)
}

Carillon.onReceived = { notification in
  // Return .suppress when your app presents its own interface.
  return .show
}
```

Without a handler, the SDK requests the banner, list, sound and badge. A notification
without a Carillon stamp reaches the handler with `deliveryId == nil`.
`Carillon.clearNotifications()` removes the app's delivered notifications from Notification Center.

## Notification images

The server sets `mutable-content: 1` on every notification that carries an
`image`, which is what routes it through a service extension. A raw `apns`
override that replaces `aps` wholesale replaces that flag too, and the image is
not attached; keep `mutable-content: 1` in the override or leave `aps` to the
server.

Add a Notification Service Extension target in Xcode. A bundle ID ending in
`.CarillonNotificationExtension` is a convention, not a requirement: any
extension bundle ID works. Add the Swift package's
`CarillonNotificationExtension` product to that target, then use:

```swift
import UserNotifications
import CarillonNotificationExtension

final class NotificationService: UNNotificationServiceExtension {
  private var helper: CarillonNotificationExtension?

  override func didReceive(_ request: UNNotificationRequest,
    withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
    helper = CarillonNotificationExtension.didReceive(request, withContentHandler: handler)
  }

  override func serviceExtensionTimeWillExpire() {
    CarillonNotificationExtension.serviceExtensionTimeWillExpire(helper)
  }
}
```

Keep the returned helper until completion. It reads `carillon.image`, downloads over HTTPS
with a 20-second budget and a 10 MiB cap, and falls back to the original notification on failure.
No App Group is required. Include the extension bundle ID in signing provisioning profiles,
including Fastlane `match`. If the app already has a notification service extension,
integrate the helper into that extension rather than embedding a second one.


## Typed tags

Use `setTag` for strings, `setTagNumber` for finite numbers, `setTagBoolean` for
booleans, and `setTagDate` for native dates (Swift `Date`, Kotlin `java.util.Date`,
JavaScript `Date`). Dates are serialized as UTC ISO timestamps. `setTags` accepts
string values or null removals only.

Each type has its own namespace: the same key may exist independently in several
types. Remove values with `removeTag`, `removeTagNumber`, `removeTagBoolean`, or
`removeTagDate`. Pending writes and removals survive restarts and retries.

See the [tags guide](https://carillon.dev/docs/concepts/tags) for API formats,
shared user profiles, audience filters, limits and examples.

## Changing the mobile key

Calling `configure` with another key or API endpoint registers the current device
again even when its token and attributes are unchanged. Repeating the same
configuration does not cause another registration after a successful response.
A key change during an in-flight request is followed by a registration using the
new configuration. Version 0.4.1 includes this behavior.

The device ID and installation proof survive reinstalls in this app's iOS
Keychain. They do not grant access to another Carillon app: the server checks the
app, key mode, platform and proof before reusing a device ID. If the previous ID
belongs to another app, registration resolves the token inside the newly selected
app and returns that app's device ID. It does not move or remove the previous
app's device record. Switching back registers again.

Use separate bundle identifiers for development and production installations
that must coexist on a phone. Changing keys does not clear your application-set
user identity or tags; update those explicitly when the signed-in user changes.

## Receipt tracking

SDK 0.5.0 queues a `received` event when a notification reaches `Carillon.willPresent`.
It also checks notifications still present in Notification Center at configuration
and whenever the app becomes active. Opening the app directly can therefore report
receipts without a tap. Notifications already removed cannot be recovered this way.
A receipt does not call `onOpened` or mean that someone read the notification.

To retain receipts while the app is not running, install the notification service
extension described above and enable the same **App Groups** capability on both
app and extension targets, for example `group.com.example.app.carillon`. Add the
`CarillonAppGroup` string with that identifier to both targets' Info.plist files.
Both provisioning profiles must include the group. Build and install the new binary.

The extension stores the delivery ID and receipt date in the shared container before
processing an image. The app queues these receipts at its next launch or activation,
including notifications removed before that launch. No API key is stored in the group.
Carillon alert payloads include `mutable-content: 1`; overriding it or sending a
silent notification prevents this extension path. iOS does not guarantee extension
execution, so missing receipts are not proof of failed delivery.

Events persist offline and retry. The trace exposes `received_at` (observed time)
and `received_reported_at` (server report time), which can differ after an offline period.
