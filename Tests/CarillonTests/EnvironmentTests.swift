import UserNotifications
import XCTest

@testable import Carillon

/// The environment decides which of Apple's two servers a notification goes to,
/// and the two do not share tokens. Getting it wrong produces devices that
/// register happily and never receive anything — the most expensive silent
/// failure in the product, and the reason this is read from the build rather
/// than asked of the customer.
final class EnvironmentTests: XCTestCase {
  /// A profile shaped the way Apple's are: a CMS wrapper, an XML plist inside it,
  /// and a signature after it. Built here rather than committed — a real profile
  /// is a signed artefact tied to one account, and it has no business in a public
  /// repository.
  private func profile(entitlements: String, plistPresent: Bool = true) -> Data {
    var data = Data([0x30, 0x82, 0x0b, 0xd9, 0x06, 0x09, 0x2a, 0x86])  // CMS header bytes
    data.append(Data("\u{0}\u{1}binary preamble\u{0}".utf8))

    if plistPresent {
      let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>AppIDName</key>
          <string>CarillonExample</string>
          <key>Entitlements</key>
          <dict>
        \(entitlements)
          </dict>
        </dict>
        </plist>
        """
      data.append(Data(plist.utf8))
    }

    // The signature that follows the payload, carrying a decoy closing tag. A
    // search that took the first match would truncate the document here.
    data.append(Data("\u{0}signature </plist> trailing bytes\u{0}".utf8))

    return data
  }

  private func apsEnvironment(_ value: String, key: String = "aps-environment") -> String {
    "    <key>\(key)</key>\n    <string>\(value)</string>"
  }

  func testDevelopmentMeansSandbox() {
    let contents = profile(entitlements: apsEnvironment("development"))

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: contents), .sandbox)
  }

  func testProductionMeansProduction() {
    let contents = profile(entitlements: apsEnvironment("production"))

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: contents), .production)
  }

  func testReadsThePrefixedSpellingOfTheSameEntitlement() {
    let contents = profile(
      entitlements: apsEnvironment("development", key: "com.apple.developer.aps-environment"))

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: contents), .sandbox)
  }

  func testAProfileWithoutTheEntitlementIsProduction() {
    // An app that has push in its profile but not this key is not a development
    // build. Sandbox would be a guess, and the wrong one is permanent.
    let contents = profile(entitlements: "    <key>get-task-allow</key>\n    <false/>")

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: contents), .production)
  }

  func testAValueAppleHasNotIntroducedYetIsProduction() {
    let contents = profile(entitlements: apsEnvironment("something-new"))

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: contents), .production)
  }

  func testAProfileThatCannotBeReadIsProduction() {
    // Most often an enterprise or ad-hoc distribution whose layout has moved.
    // Both are production.
    XCTAssertEqual(
      ProvisioningProfile.environment(inProfile: profile(entitlements: "", plistPresent: false)),
      .production)
    XCTAssertEqual(ProvisioningProfile.environment(inProfile: Data()), .production)
  }

  func testMalformedXmlBetweenTheMarkersIsProduction() {
    var data = Data("prefix<?xml version=\"1.0\"?>".utf8)
    data.append(Data("<plist><dict><key>unclosed</plist>".utf8))

    XCTAssertEqual(ProvisioningProfile.environment(inProfile: data), .production)
  }

  func testNoProfileInTheBundleIsProduction() {
    // What an App Store or TestFlight build looks like: Apple strips the profile
    // when it re-signs. The bundle running these tests has none either, which is
    // what makes this assertable at all.
    XCTAssertEqual(ProvisioningProfile.environment(in: Bundle(for: EnvironmentTests.self)), .production)
  }
}

/// Apple has five states and the protocol has four. The fold is not arbitrary:
/// what the server is asked to record is whether a notification will be shown,
/// and `ephemeral` and `authorized` answer that question the same way.
final class PushPermissionTests: XCTestCase {
  func testAuthorizedMeansAllowed() {
    XCTAssertEqual(PushPermission(.authorized), .allowed)
  }

  func testDeniedMeansDenied() {
    XCTAssertEqual(PushPermission(.denied), .denied)
  }

  func testProvisionalStaysItsOwnState() {
    // Quiet delivery is neither yes nor no: the notification reaches the handset
    // and lands where almost nobody looks. Folding it into `allowed` would make
    // an opened rate that collapsed look like a delivery problem.
    XCTAssertEqual(PushPermission(.provisional), .provisional)
  }

  func testNotDeterminedMeansNobodyHasBeenAskedYet() {
    XCTAssertEqual(PushPermission(.notDetermined), .undetermined)
  }

  func testEphemeralIsAllowed() throws {
    // An App Clip's temporary grant: time-limited, not diminished. Named by its
    // raw value because Apple marks the case unavailable outside iOS, and this
    // suite runs on the host toolchain — which is also exactly the path a state
    // Apple has not introduced yet would take.
    let ephemeral = try XCTUnwrap(UNAuthorizationStatus(rawValue: 4))

    XCTAssertEqual(PushPermission(ephemeral), .allowed)
  }

  func testTravelsUnderTheNameTheApiUses() {
    XCTAssertEqual(PushPermission.undetermined.rawValue, "undetermined")
    XCTAssertEqual(PushPermission.provisional.rawValue, "provisional")
  }
}
