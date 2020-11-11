# AltStore

> AltStore is an alternative app store for non-jailbroken iOS devices. 

[![Swift Version](https://img.shields.io/badge/swift-5.0-orange.svg)](https://swift.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

AltStore is an iOS application that allows you to sideload other apps (.ipa files) onto your iOS device with just your Apple ID. AltStore resigns apps with your personal development certificate and sends them to a desktop app, AltServer, which installs the resigned apps back to your device using iTunes WiFi sync. To prevent apps from expiring, AltStore will also periodically refresh your apps in the background when on the same WiFi as AltServer.

For the initial release, I focused on building a solid foundation for distributing my own apps — primarily Delta, [my all-in-one emulator for iOS](https://github.com/rileytestut/Delta). Now that Delta has been released, however, I'm beginning work on adding support for *anyone* to list and distribute their apps through AltStore (contributions welcome! 🙂).

## Features
- Resigns and installs any app with your Apple ID
- Installs apps over WiFi using AltServer
- Refreshes apps periodically in the background to prevent them from expiring (when on same WiFi as AltServer)
- Handles app updates directly through AltStore 

## Requirements
- Xcode 11
- iOS 12.2+ (AltStore)
- macOS 10.14.4+ (AltServer)
- Swift 5+

Why iOS 12.2+ and macOS 10.14.4+? Doing so allows me to distribute all AltStore apps without embedding Swift libraries inside them. This helps me afford bandwidth costs by reducing download sizes by roughly 30%, but also noticeably improves how long it takes to install/refresh apps with AltStore. If you're compiling AltStore and/or AltServer yourself, however, you should be able to lower their deployment targets to iOS 12.0 and macOS 10.14.0, respectively, without any issues.

## Project Overview

### AltStore
AltStore is a just regular, sandboxed iOS application. The AltStore app target contains the vast majority of AltStore's functionality, including all the logic for downloading and updating apps through AltStore. AltStore makes heavy use of standard iOS frameworks and technologies most iOS developers are familiar with, such as:
* Core Data
* Storyboards/Nibs
* Auto Layout
* Background App Refresh
* Network.framework (new in iOS 12)

### AltServer
AltServer is also just a regular, sandboxed macOS application. AltServer is significantly less complex than AltStore though, and for that reason consists of only a handful of files.

### AltKit
AltKit is a shared framework that includes common code between AltStore and AltServer.

### AltSign
AltSign is my internal framework used by both AltStore and AltServer to communicate with Apple's servers and resign apps. For more info, check the [AltSign repo](https://github.com/rileytestut/altsign).

### Roxas
Roxas is my internal framework used across all my iOS projects, developed to simplify a variety of common tasks used in iOS development. For more info, check the [Roxas repo](https://github.com/rileytestut/roxas).

## Compilation Instructions
AltStore and AltServer are both fairly straightforward to compile and run if you're already an iOS or macOS developer. To compile AltStore and/or AltServer:

1. Clone the repository 
	``` 
	git clone https://github.com/rileytestut/AltStore.git
	```
2. Update submodules: 
	```
	cd AltStore 
	git submodule update --init --recursive
	```
3. Open `AltStore.xcworkspace` and select the AltStore project in the project navigator. On the `Signing & Capabilities` tab, change the team from `Yvette Testut` to your own account.
4. **(AltStore only)** Change the value for `ALTDeviceID` in the Info.plist to your device's UDID. Normally, AltServer embeds the device's UDID in AltStore's Info.plist during installation. When running through Xcode you'll need to set the value yourself or else AltStore won't resign (or even install) apps for the proper device.
5. **(AltStore only)** Change the value for `ALTServerID` in the Info.plist to your AltServer's serverID. This is embedded by AltServer during installation to help AltStore distinguish between multiple AltServers on the same network, and you can find this by using a Bonjour browsing application and noting the serverID advertised by AltServer. This isn't strictly necessary, because if AltStore can't find the AltServer with the embedded serverID it still falls back to trying another AltServer. However, this will help in cases where there are multiple AltServers running (plus the error messages are more helpful).
6. Build + run app! 🎉

## Licensing

Due to the licensing of some dependencies used by AltStore, I have no choice but to distribute AltStore under the **AGPLv3 license**. That being said, my goal for AltStore is for it to be an open source project *anyone* can use without restrictions, so I explicitly give permission for anyone to use, modify, and distribute all *my* original code for this project in any form, with or without attribution, without fear of legal consequences (dependencies remain under their original licenses, however).

## Contact Me

* Email: riley@rileytestut.com
* Twitter: [@rileytestut](https://twitter.com/rileytestut)

Questions about AltStore in general? Make sure to read the FAQ at https://altstore.io/faq/
