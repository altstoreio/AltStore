# Sparkle 2 ![Build Status](https://github.com/sparkle-project/Sparkle/workflows/Build%20%26%20Tests/badge.svg?branch=2.x) ![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-4BC51D.svg?style=flat) [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) [![CocoaPods](https://img.shields.io/cocoapods/v/Sparkle.svg?cacheSeconds=86400)](https://cocoapods.org/pods/Sparkle)

Secure and reliable software update framework for macOS.

<img src="Resources/Screenshot.png" width="732" alt="Sparkle shows familiar update window with release notes">

Sparkle 2 adds support for application sandboxing, custom user interfaces, updating external bundles, and a more modern architecture which includes faster and more reliable installs.

Pre-releases when available can be found on the [Sparkle's Releases](https://github.com/sparkle-project/Sparkle/releases) or on your favorite package manager. More nightly builds can be downloaded by selecting a recent [workflow run](https://github.com/sparkle-project/Sparkle/actions?query=event%3Apush+is%3Asuccess+branch%3A2.x) and downloading the corresponding Sparkle-distribution artifact.

The current status for future versions of Sparkle is tracked by [its roadmap](https://github.com/sparkle-project/Sparkle/milestones).

Please visit [Sparkle's website](http://sparkle-project.org) for up to date documentation on using and migrating over to Sparkle 2. Refer to [Changelog](CHANGELOG) for a more detailed list of changes. More internal design documents to the project can be found in the repository under [Documentation](Documentation/).

## Features

* Seamless. There's no mention of Sparkle; your icons and app name are used.
* Secure. Updates are verified using EdDSA signatures and Apple Code Signing. Supports Sandboxed applications in Sparkle 2.
* Fast. Supports delta updates which only patch files that have changed and atomic-safe installs.
* Easy to install. Sparkle requires no code in your app, and only needs static files on a web server.
* Customizable. Sparkle 2 supports plugging in a custom UI for updates.
* Flexible. Supports applications, package installers, preference panes, and other plug-ins. Sparkle 2 supports updating external bundles.
* Handles permissions, quarantine, and automatically asks for authentication if needed.
* Uses RSS-based appcasts for release information. Appcasts are a de-facto standard supported by 3rd party update-tracking programs and websites.
* Stays hidden until second launch for better first impressions.
* Truly self-updating — the user can choose to automatically download and install all updates in the background.
* Ability to use channels for beta updates (in Sparkle 2), add phased rollouts to users, and mark updates as critical or major.
* Progress and status notifications for the host app.

## Requirements

* Runtime: macOS 10.13 or greater for 2.3, macOS 10.11 or greater for 2.2.x
* Build: Latest major Xcode (stable or beta, whichever is latest) and one major version less.
* HTTPS server for serving updates (see [App Transport Security](http://sparkle-project.org/documentation/app-transport-security/))

## Usage

See [getting started guide](https://sparkle-project.org/documentation/). No code is necessary, but a bit of Xcode configuration is required.

### Troubleshooting

  * Please check **Console.app** for logs under your application. Sparkle prints detailed information there about all problems it encounters. It often also suggests solutions to the problems, so please read Sparkle's log messages carefully.

  * Use the `generate_appcast` tool which creates appcast files, correct signatures, and delta updates automatically.

  * Make sure the URL specified in [`SUFeedURL`](https://sparkle-project.org/documentation/customization/) is valid (typos/404s are a common error!), and that it uses modern TLS ([test it](https://www.ssllabs.com/ssltest/)).

### API symbols

Sparkle is built with `-fvisibility=hidden -fvisibility-inlines-hidden` which means no symbols are exported by default.
If you are adding a symbol to the public API you must decorate the declaration with the `SU_EXPORT` macro (grep the source code for examples).

### Building the distribution package

`cd` to the root of the Sparkle source tree and run `make release`. Sparkle-*VERSION*.tar.xz (or .bz2) will be created in a temporary directory and revealed in Finder after the build has completed.

Alternatively, build the Distribution scheme in the Xcode UI.

### Code of Conduct

We pledge to have an open and welcoming environment. See our [Code of Conduct](CODE_OF_CONDUCT.md).
