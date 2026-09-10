// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Carillon",
  // iOS is the product. macOS appears so that the host toolchain can build and
  // run the tests with `swift test`: everything except the two AppDelegate entry
  // points is platform-neutral and is verified there, on every machine, without
  // a simulator. The UIKit surface is compiled only where UIKit exists.
  platforms: [.iOS(.v15), .macOS(.v12)],
  products: [
    .library(name: "Carillon", targets: ["Carillon"]),
    .library(name: "CarillonNotificationExtension", targets: ["CarillonNotificationExtension"])
  ],
  targets: [
    .target(name: "Carillon"),
    .target(name: "CarillonNotificationExtension"),
    .testTarget(name: "CarillonNotificationExtensionTests", dependencies: ["CarillonNotificationExtension"]),
    .testTarget(name: "CarillonTests", dependencies: ["Carillon"]),
  ]
)
