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

## Request permission

```swift
let permission = await Carillon.requestPermission()
```

Requests alert, badge, and sound authorization. Returns the current permission
and syncs it to Carillon. Registration and notification display permission are
separate: `configure` does not display this prompt.

## Update the device

```swift
Carillon.identify("user-42")
Carillon.setTags(["plan": "pro", "seats": 12])
Carillon.clearIdentity()
Carillon.optOut()
Carillon.optIn()
```

Tags replace the entire map. Clearing identity keeps the device registered.
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
Token rotation reuses that ID when the server validates the proof. Reinstallation
or merging with an existing token registration can change the ID; the callback
fires on first registration and when the confirmed ID changes. The ID itself is
not a credential. Never log or export the installation secret.
