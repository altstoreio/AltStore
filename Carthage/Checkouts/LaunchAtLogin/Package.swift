// swift-tools-version:5.3
import PackageDescription

let package = Package(
	name: "LaunchAtLogin",
	platforms: [
		.macOS(.v10_12)
	],
	products: [
		.library(
			name: "LaunchAtLogin",
			targets: ["LaunchAtLogin"]
		)
	],
	targets: [
		.target(
			name: "LaunchAtLogin",
			exclude: [
				"Info.plist",
				"copy-helper.sh"
			],
			resources: [
				.copy("LaunchAtLogin.entitlements"),
				.copy("copy-helper-swiftpm.sh"),
				.copy("LaunchAtLoginHelper.zip"),
				.copy("LaunchAtLoginHelper-with-runtime.zip")
			]
		)
	]
)
