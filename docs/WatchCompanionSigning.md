# Apple Watch companion signing (Classic)

Classic prepares embedded Apple Watch companions as part of the iPhone IPA. It discovers modern `Watch/*.app` bundles, older Watch apps containing `PlugIns/*.appex`, and first-generation WatchKit apps inside an iPhone extension. Each executable app/extension receives its own App ID, provisioning profile and entitlements. These additional bundles count toward the account's App ID quota; they are not added to the iPhone extension slot count.

All bundle identifiers derive from the actual resigned iPhone identifier, including a previously installed identifier or a randomized identifier. The complete original-to-resigned mapping updates `CFBundleIdentifier`, `WKCompanionAppBundleIdentifier` and legacy `NSExtension.NSExtensionAttributes.WKAppBundleIdentifier` references. For example, `com.calebmech.Race` becoming `com.calebmech.Race.Z9NVYMZ644` also changes its Watch companion's reference to that exact identifier.

AltSign embeds a matching profile in every nested app/extension. Its ldid dependency signs nested Watch executables before sealing their parents. Source permission verification and added-permission review include Watch entitlements and privacy usage descriptions. Ordinary iPhone apps and immediate extensions keep their existing handling.

## Provisioning requirements and limitations

Apple's [iOS App Development profile type covers iOS and watchOS](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile). A valid companion profile may list `iOS` in its `Platform` array without a literal `watchOS` entry. Profiles from another family, such as tvOS, are rejected for Watch executables.

The target Watch must already be registered with the signing team and included in its development profiles. AltStore currently registers the iPhone; this change does not discover, register, pair with or directly install to an Apple Watch. Register the Watch with Xcode or the developer portal first. See Apple's [registered-device distribution guidance](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

HealthKit is requested through the existing modern capability API. Watch capability entitlements must be authorized by the returned profile; missing authorization produces an error instead of silently stripping a requested capability. Capability availability depends on Apple's account and platform policies. This does not bypass personal-team restrictions or implement approval for managed capabilities. Other existing unsupported capabilities remain unsupported.

The signed IPA follows the existing iPhone installation path. Watch transfer and installation remain the operating system's responsibility. Standalone Watch-only app installation is outside this change.

## Refresh

An app with embedded Watch content uses the full resign-and-reinstall path on refresh, even with the same signing certificate. Installing profiles on the iPhone alone cannot establish that the Watch's embedded profiles have refreshed. The installed app's expiration date also reflects an earlier-expiring Watch profile. Actual transfer, installation, refresh, launch and HealthKit authorization on a paired Watch still require hardware validation.

## Regression validation

Initialize the signing submodules, then run on macOS with Xcode command-line tools and Python 3:

```sh
git submodule update --init --recursive Dependencies/AltSign
python3 Dependencies/AltSign/Tests/run-watch-signing-tests.py
```

The suite compiles the production AltSign/ldid signing code without GrandSlam authentication dependencies. It creates disposable native executables, a local test certificate and synthetic CMS provisioning profiles. It checks the exact team-suffixed mismatch, randomized identifiers, modern/legacy layouts, capability rejection, per-bundle profile/entitlement assignment, plain iPhone apps, extensions, and `codesign --verify --deep --strict` resource/signature integrity.

For a physical-device build already on disk:

```sh
python3 Dependencies/AltSign/Tests/run-watch-signing-tests.py --app /path/to/Example.app
```

This operates on a temporary copy. It adds synthetic HealthKit entitlements to the copy, remaps and signs it with test assets, and checks its nested signatures. It never installs anything and does not establish Apple trust or real-device provisioning validity.

`AltTests.testWatchOnlyPermissionsAndRefresh` covers Watch-only HealthKit/privacy discovery and the full-refresh decision, alongside an ordinary iPhone extension regression. Run it with the existing `AltTests` Xcode scheme when the full app's dependencies and test environment are available.
