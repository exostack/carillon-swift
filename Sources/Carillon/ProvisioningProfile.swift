import Foundation

/// Which APNs environment this build's token belongs to.
///
/// It decides which of Apple's two servers the notification is sent to, and the
/// two do not share tokens: a sandbox token pushed to the production host is
/// rejected as unknown, and the customer sees devices that register happily and
/// never receive anything.
public enum PushEnvironment: String {
  case production
  case sandbox
}

/// The environment, read from the build rather than configured.
///
/// The protocol makes this the SDK's job on purpose. A customer who has to
/// declare it declares it once, correctly, and then ships a TestFlight build
/// with the debug value still in place — and the failure is silent on every
/// device at once.
///
/// The source of truth is `embedded.mobileprovision`, the provisioning profile
/// Xcode copies into the bundle. It is a CMS-signed blob with an XML property
/// list inside it; the signature is Apple's business, and reading the payload
/// needs no verification because a tampered profile would not have launched.
enum ProvisioningProfile {
  /// The entitlement under both spellings it is written with.
  ///
  /// iOS profiles carry `aps-environment`. The prefixed form is what the same
  /// entitlement is called elsewhere in Apple's tooling, and it costs one array
  /// element to survive meeting it.
  private static let entitlementKeys = ["aps-environment", "com.apple.developer.aps-environment"]

  /// Resolves from a bundle, which is what the SDK does at runtime.
  static func environment(in bundle: Bundle = .main) -> PushEnvironment {
    guard
      let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
      let contents = try? Data(contentsOf: url)
    else {
      // No profile in the bundle. This is an App Store or TestFlight build:
      // Apple strips the profile when it re-signs, and both of those are
      // production. It is also what a simulator build looks like, which is why
      // the simulator is decided before this is ever consulted.
      return .production
    }

    return environment(inProfile: contents)
  }

  /// The parse itself, over bytes, so every branch below can be exercised
  /// without a signed profile in the repository.
  static func environment(inProfile contents: Data) -> PushEnvironment {
    guard
      let plist = embeddedPlist(in: contents),
      let profile = try? PropertyListSerialization.propertyList(from: plist, format: nil)
        as? [String: Any],
      let entitlements = profile["Entitlements"] as? [String: Any]
    else {
      // A profile that cannot be read is most often an enterprise or ad-hoc
      // distribution whose layout has moved. Both are production; guessing
      // sandbox here would break the one case where being wrong is permanent.
      return .production
    }

    let declared = entitlementKeys.compactMap { entitlements[$0] as? String }.first

    // `development` is the only value that means sandbox. `production` says so,
    // and anything else — a value Apple has not introduced yet — is treated as
    // production for the same reason an unreadable profile is.
    return declared == "development" ? .sandbox : .production
  }

  /// The XML plist inside the signed container.
  ///
  /// Located by its own markers rather than by decoding the CMS structure: the
  /// payload is plain XML at a variable offset, the markers are unambiguous, and
  /// an ASN.1 decoder written here would be a dependency in all but name.
  private static func embeddedPlist(in contents: Data) -> Data? {
    guard
      let opening = contents.range(of: Data("<?xml".utf8)),
      // Searched backwards: the signature that follows the payload can itself
      // contain the closing bytes, and taking the first match would truncate the
      // plist mid-document on exactly the profiles that are hardest to obtain
      // for a test.
      let closing = contents.range(of: Data("</plist>".utf8), options: .backwards),
      closing.upperBound > opening.lowerBound
    else { return nil }

    return contents.subdata(in: opening.lowerBound..<closing.upperBound)
  }
}
