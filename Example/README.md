# Run the example

Open `CarillonExample/CarillonExample.xcodeproj` and run the `CarillonExample` scheme on an iPhone or an APNs-capable simulator. The project uses the SDK from this checkout and embeds its notification service extension.

For device signing, create `CarillonExample/Signing.local.xcconfig` with your own
Apple development team ID:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

This file is ignored by Git and applies to the app, extension and UI test targets.
Keep personal signing settings there instead of editing the shared project.

Set the endpoint and a mobile key in the app, apply them, then request notification permission. For a local API on the simulator, use `http://127.0.0.1:28080`. A physical phone needs a reachable server address. Use a live mobile key and matching APNs credentials for a real notification; test keys simulate delivery and do not reach the device.

Send from a server using a secret key and an audience containing only the device ID displayed by the example. Include an HTTPS `payload.image` URL that returns an image. Put the app in the background, receive the notification, expand it to inspect the image, then tap it. Verify `opened` in the campaign trace. Provider acceptance alone does not verify display or opening.

Keep the installed app in place between sending and inspecting the notification. Rebuilding or reinstalling changes the environment being tested.

## Permission UI test

The `CarillonExampleE2E` scheme includes a permission interaction test. It does not send a push or assert image rendering:

```sh
xcodebuild -project CarillonExample/CarillonExample.xcodeproj \
  -scheme CarillonExampleE2E \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' test
```

To test real delivery on a simulator, preserve code signing and its APNs entitlement. A successful SDK package build alone does not verify that the app embeds and launches its notification service extension.
