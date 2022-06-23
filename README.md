# SideStore

> SideStore is an alternative app store for non-jailbroken iOS devices that can sideload using a VPN over the internet. 

[![Swift Version](https://img.shields.io/badge/swift-5.0-orange.svg)](https://swift.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://makeapullrequest.com)
[![Build and Upload SideStore](https://github.com/SideStore/SideStore/actions/workflows/build.yml/badge.svg)](https://github.com/SideStore/SideStore/actions/workflows/build.yml)

SideStore is an iOS application that allows you to sideload other apps (.ipa files) onto your iOS device with just your Apple ID. SideStore resigns apps with your personal development certificate and sends them to a desktop app called AltServer or use the SideStore VPN, which installs the resigned apps back to your device using iTunes WiFi sync or using the SideStore VPN where you can sideload at any place over wifi that supports zerotier that has internet. To prevent apps from expiring, SideStore just like AltStore will also periodically refresh your apps in the background when on the same WiFi as AltServer or using SideStore VPN over wifi on any network that includes a internet connection.

The goal of this project is to allow easy and a mostly computerless experience to sideload apps on iOS based devices. This project is meant as a alternative of AltStore where you can do anything AltStore can (maybe even more) but over a vpn. You will be able to use SideStore just like if you were using AltStore with benifits.
 (contributions welcome! 🙂).


## Requirements
- Xcode 11
- iOS 12.2+ (SideStore)
- macOS 10.14.4+ (TBD)
- Swift 5+
- Visual Studio Code

## Project Overview

### SideStore
SideStore is a alternative to AltStore and is a sandboxed iOS application like AltStore. The SideStore app target contains the vast majority of AltStore's functionality, including all the logic for downloading and updating apps through SideStore.

### Netmuxd
[Netmuxd](https://github.com/jkcoxson/netmuxd) is a program that replaces Usbmuxd to be able to connect over a VPN reliably.  It is programmed in the Rust programming language and it is open source.

### Roxas
[Roxas](https://github.com/rileytestut/roxas) is Riley Testut's internal framework from AltStore used across many of their iOS projects, developed to simplify a variety of common tasks used in iOS development.

## Compilation Instructions
AltStore and AltServer are both fairly straightforward to compile and run if you're already an iOS or macOS developer. To compile AltStore and/or AltServer:

1. Clone the repository 
	```
	git clone https://github.com/SideStore/SideStore.git --recurse-submodules
	```
2. Open `AltStore.xcodeproj` and select the AltStore project in the project navigator. On the `Signing & Capabilities` tab, change the team from to your own account.
3. **(Development only)** Change the value for `ALTDeviceID` in the Info.plist to your device's UDID. Normally, SideServer embeds the device's UDID in SideStore's Info.plist during installation. When running through Xcode you'll need to set the value yourself or else SideStore won't resign (or even install) apps for the proper device. You can achieve this by changing a few things to be able to build and use SideStore.
5. Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig`
6. Fill out all of the properties in `CodeSigning.xcconfig` to match your account.
7. In `Shared/Extensions/Bundle+AltStore.swift`, replace "group.com.rileytestut.AltStore" with your own App Group ID. 
8. Build + run app! 🎉

## Licensing

This project is licensed under the **AGPLv3 license**.
