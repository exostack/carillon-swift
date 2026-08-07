# carillon-swift

Carillon iOS SDK. Native Swift, zero dependencies, Swift Package Manager.

The package is everything under `Sources/`; `Example/` hosts the test-bench
application and is never part of the published product.

## Integrating

```swift
Carillon.configure(key: "carillon_mk_live_…", debug: true)
await Carillon.register()
```

Then two lines in the app delegate. The SDK swizzles nothing, so everything it
receives is visible in your own code:

```swift
func application(_ app: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
  Carillon.didRegister(token: token)
}

func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completion: @escaping () -> Void) {
  Carillon.didOpen(response)
  completion()
}
```

## Tests

`swift test` from the repository root. Everything except the two entry points
above is platform-neutral and runs on the host without a simulator;
`xcodebuild test -scheme Carillon -destination 'platform=iOS Simulator,…'`
covers the rest.

## Conformance fixtures

`Tests/ConformanceFixtures/` holds language-neutral vectors — a device state or
an event queue, and the exact request it must produce. They are generated from
the same code the tests assert, and every Carillon SDK replays them, so two
SDKs cannot quietly disagree about what the server is told. Regenerate after a
deliberate change with:

```
CARILLON_WRITE_FIXTURES=1 swift test
```
