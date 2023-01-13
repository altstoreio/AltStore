# SideStore

> SideStore is an *untethered, community driven* alternative app store for non-jailbroken iOS devices

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://makeapullrequest.com)
[![Build and Upload SideStore](https://github.com/SideStore/SideStore/actions/workflows/build.yml/badge.svg)](https://github.com/SideStore/SideStore/actions/workflows/build.yml)

SideStore is an iOS application that allows you to sideload apps onto your iOS device with just your Apple ID. SideStore resigns apps with your personal development certificate, and then uses a [specially designed VPN](https://github.com/jkcoxson/Secret-Tunnel) in order to trick iOS into installing them. SideStore will periodically "refresh" your apps in the background, to keep their normal 7-day development period from expiring.

SideStore's goal is to provide an untethered sideloading experience. It's a community driven fork of [AltStore](https://github.com/rileytestut/AltStore), and has already implemented some of the community's most-requested features.

(Contributions are welcome! 🙂)


## Requirements
- Xcode 14
- iOS 14+
- Rustup (`brew install rustup`)

Why iOS 14? Targeting such a recent version of iOS allows us to accelerate development, especially since not many developers have older devices to test on. This is corrobated by the fact that SwiftUI support is much better, allowing us to transistion to a more modern UI codebase.
## Project Overview

### SideStore
SideStore is a just regular, sandboxed iOS application. The AltStore app target contains the vast majority of SideStore's functionality, including all the logic for downloading and updating apps through SideStore. SideStore makes heavy use of standard iOS frameworks and technologies most iOS developers are familiar with.

### EM Proxy
[SideServer mobile](https://github.com/jkcoxson/em_proxy) powers the defining feature of SideStore: untethered app installation. By levaraging an App Store app with additional entitlements (WireGuard) to create the VPN tunnel for us, it allows SideStore to take advantage of [Jitterbug](https://github.com/osy/Jitterbug)'s loopback method without requiring a paid developer account.

### Minimuxer
[Minimuxer](https://github.com/jkcoxson/minimuxer) is a lockdown muxer that can run inside iOS’s sandbox. It replicates Apple’s usbmuxd protocol on MacOS to “discover” devices to interface with wireguard On-Device.

### Roxas
[Roxas](https://github.com/rileytestut/roxas) is Riley Testut's internal framework from AltStore used across many of their iOS projects, developed to simplify a variety of common tasks used in iOS development.

We're hoping to eventually eliminate our dependency on it, as it increases the amount of unnecessary Objective-C in the project.

## Compilation Instructions
SideStore is fairly straightforward to compile and run if you're already an iOS or macOS developer. Here are some basic instructions to get you started:

1. Clone the repository 
	```
	git clone https://github.com/SideStore/SideStore.git --recurse-submodules
	```
2. After installing Rustup, run `rustup target add aarch64-apple-ios`
12. Within the Dependencies/em_proxy and Dependencies/minimuxer directories, run `cargo build --release --target aarch64-apple-ios`
2. Open `AltStore.xcodeproj` and select the AltStore project in the project navigator. On the `Signing & Capabilities` tab, change the team from to your own account.
3. **(Development only)** Change the value for `ALTDeviceID` in the Info.plist to your device's UDID. Normally, SideServer embeds the device's UDID in SideStore's Info.plist during installation. When running through Xcode you'll need to set the value yourself or else SideStore won't resign (or even install) apps for the proper device. You can achieve this by changing a few things to be able to build and use SideStore.
5. Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig`
6. Fill out all of the properties in `CodeSigning.xcconfig` to match your account.
7. In `Shared/Extensions/Bundle+AltStore.swift`, replace "group.com.rileytestut.AltStore" with your own App Group ID. 
8. Build + run app! 🎉

## Licensing

This project is licensed under the **AGPLv3 license**.
