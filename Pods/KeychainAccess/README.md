# KeychainAccess
[![CI Status](http://img.shields.io/travis/kishikawakatsumi/KeychainAccess.svg)](https://travis-ci.org/kishikawakatsumi/KeychainAccess)
[![codecov](https://codecov.io/gh/kishikawakatsumi/KeychainAccess/branch/master/graph/badge.svg)](https://codecov.io/gh/kishikawakatsumi/KeychainAccess)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Version](https://img.shields.io/cocoapods/v/KeychainAccess.svg)](http://cocoadocs.org/docsets/KeychainAccess)
[![Platform](https://img.shields.io/cocoapods/p/KeychainAccess.svg)](http://cocoadocs.org/docsets/KeychainAccess)
[![Swift 3.x](https://img.shields.io/badge/Swift-3.x-orange.svg?style=flat)](https://swift.org/)
[![Swift 4.0](https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat)](https://swift.org/)
[![Swift 4.1](https://img.shields.io/badge/Swift-4.1-orange.svg?style=flat)](https://swift.org/)
[![Swift 4.2](https://img.shields.io/badge/Swift-4.2-orange.svg?style=flat)](https://swift.org/)

KeychainAccess is a simple Swift wrapper for Keychain that works on iOS and OS X. Makes using Keychain APIs extremely easy and much more palatable to use in Swift.

<img src="https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/master/Screenshots/01.png" width="320px" />
<img src="https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/master/Screenshots/02.png" width="320px" />
<img src="https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/master/Screenshots/03.png" width="320px" />

## :bulb: Features

- Simple interface
- Support access group
- [Support accessibility](#accessibility)
- [Support iCloud sharing](#icloud_sharing)
- **[Support TouchID and Keychain integration (iOS 8+)](#touch_id_integration)**
- **[Support Shared Web Credentials (iOS 8+)](#shared_web_credentials)**
- [Works on both iOS & OS X](#requirements)
- [watchOS and tvOS are supported](#requirements)
- **[Swift 4 & Swift 3 compatible](#requirements)**

## :book: Usage

##### :eyes: See also:  
- [:link: iOS Example Project](https://github.com/kishikawakatsumi/KeychainAccess/tree/master/Examples/Example-iOS)

### :key: Basics

#### Saving Application Password

```swift
let keychain = Keychain(service: "com.example.github-token")
keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

#### Saving Internet Password

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)
keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

### :key: Instantiation

#### Create Keychain for Application Password

```swift
let keychain = Keychain(service: "com.example.github-token")
```

```swift
let keychain = Keychain(service: "com.example.github-token", accessGroup: "12ABCD3E4F.shared")
```

#### Create Keychain for Internet Password

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)
```

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https, authenticationType: .htmlForm)
```

### :key: Adding an item

#### subscripting

##### for String

```swift
keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

```swift
keychain[string: "kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

##### for NSData

```swift
keychain[data: "secret"] = NSData(contentsOfFile: "secret.bin")
```

#### set method

```swift
keychain.set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
```

#### error handling

```swift
do {
    try keychain.set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
}
catch let error {
    print(error)
}
```

### :key: Obtaining an item

#### subscripting

##### for String (If the value is NSData, attempt to convert to String)

```swift
let token = keychain["kishikawakatsumi"]
```

```swift
let token = keychain[string: "kishikawakatsumi"]
```

##### for NSData

```swift
let secretData = keychain[data: "secret"]
```

#### get methods

##### as String

```swift
let token = try? keychain.get("kishikawakatsumi")
```

```swift
let token = try? keychain.getString("kishikawakatsumi")
```

##### as NSData

```swift
let data = try? keychain.getData("kishikawakatsumi")
```

### :key: Removing an item

#### subscripting

```swift
keychain["kishikawakatsumi"] = nil
```

#### remove method

```swift
do {
    try keychain.remove("kishikawakatsumi")
} catch let error {
    print("error: \(error)")
}
```

### :key: Set Label and Comment

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)
do {
    try keychain
        .label("github.com (kishikawakatsumi)")
        .comment("github access token")
        .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
} catch let error {
    print("error: \(error)")
}
```

### :key: Obtaining Other Attributes

#### PersistentRef

```swift
let keychain = Keychain()
let persistentRef = keychain[attributes: "kishikawakatsumi"].persistentRef
...
```

#### Creation Date

```swift
let keychain = Keychain()
let creationDate = keychain[attributes: "kishikawakatsumi"].creationDate
...
```

#### All Attributes

```swift
let keychain = Keychain()
do {
    let attributes = try keychain.get("kishikawakatsumi") { $0 }
    print(attributes.comment)
    print(attributes.label)
    print(attributes.creator)
    ...
} catch let error {
    print("error: \(error)")
}
```

##### subscripting

```swift
let keychain = Keychain()
let attributes = keychain[attributes: "kishikawakatsumi"]
print(attributes.comment)
print(attributes.label)
print(attributes.creator)
```

### :key: Configuration (Accessibility, Sharing, iCloud Sync)

**Provides fluent interfaces**

```swift
let keychain = Keychain(service: "com.example.github-token")
    .label("github.com (kishikawakatsumi)")
    .synchronizable(true)
    .accessibility(.afterFirstUnlock)
```

#### <a name="accessibility"> Accessibility

##### Default accessibility matches background application (=kSecAttrAccessibleAfterFirstUnlock)

```swift
let keychain = Keychain(service: "com.example.github-token")
```

##### For background application

###### Creating instance

```swift
let keychain = Keychain(service: "com.example.github-token")
    .accessibility(.afterFirstUnlock)

keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

###### One-shot

```swift
let keychain = Keychain(service: "com.example.github-token")

do {
    try keychain
        .accessibility(.afterFirstUnlock)
        .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
} catch let error {
    print("error: \(error)")
}
```

##### For foreground application

###### Creating instance

```swift
let keychain = Keychain(service: "com.example.github-token")
    .accessibility(.whenUnlocked)

keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

###### One-shot

```swift
let keychain = Keychain(service: "com.example.github-token")

do {
    try keychain
        .accessibility(.whenUnlocked)
        .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
} catch let error {
    print("error: \(error)")
}
```

#### :couple: Sharing Keychain items

```swift
let keychain = Keychain(service: "com.example.github-token", accessGroup: "12ABCD3E4F.shared")
```

#### <a name="icloud_sharing"> :arrows_counterclockwise: Synchronizing Keychain items with iCloud

###### Creating instance

```swift
let keychain = Keychain(service: "com.example.github-token")
    .synchronizable(true)

keychain["kishikawakatsumi"] = "01234567-89ab-cdef-0123-456789abcdef"
```

###### One-shot

```swift
let keychain = Keychain(service: "com.example.github-token")

do {
    try keychain
        .synchronizable(true)
        .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
} catch let error {
    print("error: \(error)")
}
```

### <a name="touch_id_integration"> :fu: Touch ID integration

**Any Operation that require authentication must be run in the background thread.**  
**If you run in the main thread, UI thread will lock for the system to try to display the authentication dialog.**

#### :closed_lock_with_key: Adding a Touch ID protected item

If you want to store the Touch ID protected Keychain item, specify `accessibility` and `authenticationPolicy` attributes.  

```swift
let keychain = Keychain(service: "com.example.github-token")

DispatchQueue.global().async {
    do {
        // Should be the secret invalidated when passcode is removed? If not then use `.WhenUnlocked`
        try keychain
            .accessibility(.whenPasscodeSetThisDeviceOnly, authenticationPolicy: .userPresence)
            .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
    } catch let error {
        // Error handling if needed...
    }
}
```

#### :closed_lock_with_key: Updating a Touch ID protected item

The same way as when adding.  

**Do not run in the main thread if there is a possibility that the item you are trying to add already exists, and protected.**
**Because updating protected items requires authentication.**

Additionally, you want to show custom authentication prompt message when updating, specify an `authenticationPrompt` attribute.
If the item not protected, the `authenticationPrompt` parameter just be ignored.

```swift
let keychain = Keychain(service: "com.example.github-token")

DispatchQueue.global().async {
    do {
        // Should be the secret invalidated when passcode is removed? If not then use `.WhenUnlocked`
        try keychain
            .accessibility(.whenPasscodeSetThisDeviceOnly, authenticationPolicy: .userPresence)
            .authenticationPrompt("Authenticate to update your access token")
            .set("01234567-89ab-cdef-0123-456789abcdef", key: "kishikawakatsumi")
    } catch let error {
        // Error handling if needed...
    }
}
```

#### :closed_lock_with_key: Obtaining a Touch ID protected item

The same way as when you get a normal item. It will be displayed automatically Touch ID or passcode authentication If the item you try to get is protected.  
If you want to show custom authentication prompt message, specify an `authenticationPrompt` attribute.
If the item not protected, the `authenticationPrompt` parameter just be ignored.

```swift
let keychain = Keychain(service: "com.example.github-token")

DispatchQueue.global().async {
    do {
        let password = try keychain
            .authenticationPrompt("Authenticate to login to server")
            .get("kishikawakatsumi")

        print("password: \(password)")
    } catch let error {
        // Error handling if needed...
    }
}
```

#### :closed_lock_with_key: Removing a Touch ID protected item

The same way as when you remove a normal item.
There is no way to show Touch ID or passcode authentication when removing Keychain items.

```swift
let keychain = Keychain(service: "com.example.github-token")

do {
    try keychain.remove("kishikawakatsumi")
} catch let error {
    // Error handling if needed...
}
```

### <a name="shared_web_credentials"> :key: Shared Web Credentials

> Shared web credentials is a programming interface that enables native iOS apps to share credentials with their website counterparts. For example, a user may log in to a website in Safari, entering a user name and password, and save those credentials using the iCloud Keychain. Later, the user may run a native app from the same developer, and instead of the app requiring the user to reenter a user name and password, shared web credentials gives it access to the credentials that were entered earlier in Safari. The user can also create new accounts, update passwords, or delete her account from within the app. These changes are then saved and used by Safari.  
<https://developer.apple.com/library/ios/documentation/Security/Reference/SharedWebCredentialsRef/>


```swift
let keychain = Keychain(server: "https://www.kishikawakatsumi.com", protocolType: .HTTPS)

let username = "kishikawakatsumi@mac.com"

// First, check the credential in the app's Keychain
if let password = try? keychain.get(username) {
    // If found password in the Keychain,
    // then log into the server
} else {
    // If not found password in the Keychain,
    // try to read from Shared Web Credentials
    keychain.getSharedPassword(username) { (password, error) -> () in
        if password != nil {
            // If found password in the Shared Web Credentials,
            // then log into the server
            // and save the password to the Keychain

            keychain[username] = password
        } else {
            // If not found password either in the Keychain also Shared Web Credentials,
            // prompt for username and password

            // Log into server

            // If the login is successful,
            // save the credentials to both the Keychain and the Shared Web Credentials.

            keychain[username] = inputPassword
            keychain.setSharedPassword(inputPassword, account: username)
        }
    }
}
```

#### Request all associated domain's credentials

```swift
Keychain.requestSharedWebCredential { (credentials, error) -> () in

}
```

#### Generate strong random password

Generate strong random password that is in the same format used by Safari autofill (xxx-xxx-xxx-xxx).

```swift
let password = Keychain.generatePassword() // => Nhu-GKm-s3n-pMx
```

#### How to set up Shared Web Credentials

> 1. Add a com.apple.developer.associated-domains entitlement to your app. This entitlement must include all the domains with which you want to share credentials.

> 2. Add an apple-app-site-association file to your website. This file must include application identifiers for all the apps with which the site wants to share credentials, and it must be properly signed.

> 3. When the app is installed, the system downloads and verifies the site association file for each of its associated domains. If the verification is successful, the app is associated with the domain.

**More details:**  
<https://developer.apple.com/library/ios/documentation/Security/Reference/SharedWebCredentialsRef/>

### :key: Debugging

#### Display all stored items if print keychain object

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)
print("\(keychain)")
```

```
=>
[
  [authenticationType: default, key: kishikawakatsumi, server: github.com, class: internetPassword, protocol: https]
  [authenticationType: default, key: hirohamada, server: github.com, class: internetPassword, protocol: https]
  [authenticationType: default, key: honeylemon, server: github.com, class: internetPassword, protocol: https]
]
```

#### Obtaining all stored keys

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)

let keys = keychain.allKeys()
for key in keys {
  print("key: \(key)")
}
```

```
=>
key: kishikawakatsumi
key: hirohamada
key: honeylemon
```

#### Obtaining all stored items

```swift
let keychain = Keychain(server: "https://github.com", protocolType: .https)

let items = keychain.allItems()
for item in items {
  print("item: \(item)")
}
```

```
=>
item: [authenticationType: Default, key: kishikawakatsumi, server: github.com, class: InternetPassword, protocol: https]
item: [authenticationType: Default, key: hirohamada, server: github.com, class: InternetPassword, protocol: https]
item: [authenticationType: Default, key: honeylemon, server: github.com, class: InternetPassword, protocol: https]
```

## Requirements

|            | OS                                     | Swift         |
|------------|----------------------------------------|---------------|
| **v1.1.x** | iOS 7+, OSX 10.9+                      | 1.1           |
| **v1.2.x** | iOS 7+, OSX 10.9+                      | 1.2           |
| **v2.0.x** | iOS 7+, OSX 10.9+, watchOS 2+          | 2.0           |
| **v2.1.x** | iOS 7+, OSX 10.9+, watchOS 2+          | 2.0           |
| **v2.2.x** | iOS 8+, OSX 10.9+, watchOS 2+, tvOS 9+ | 2.0, 2.1      |
| **v2.3.x** | iOS 8+, OSX 10.9+, watchOS 2+, tvOS 9+ | 2.0, 2.1, 2.2 |
| **v2.4.x** | iOS 8+, OSX 10.9+, watchOS 2+, tvOS 9+ | 2.2, 2.3      |
| **v3.0.x** | iOS 8+, OSX 10.9+, watchOS 2+, tvOS 9+ | 3.x           |
| **v3.1.x** | iOS 8+, OSX 10.9+, watchOS 2+, tvOS 9+ | 4.0, 4.1, 4.2 |

## Installation

### CocoaPods

KeychainAccess is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following lines to your Podfile:

```ruby
use_frameworks!
pod 'KeychainAccess'
```

### Carthage

KeychainAccess is available through [Carthage](https://github.com/Carthage/Carthage). To install
it, simply add the following line to your Cartfile:

`github "kishikawakatsumi/KeychainAccess"`

### Swift Package Manager

KeychainAccess is also available through [Swift Package Manager](https://github.com/apple/swift-package-manager/).
First, create `Package.swift` that its package declaration includes:

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", majorVersion: 2)
    ]
)
```

Then, type

```shell
$ swift build
```

### To manually add to your project

1. Add `Lib/KeychainAccess.xcodeproj` to your project
2. Link `KeychainAccess.framework` with your target
3. Add `Copy Files Build Phase` to include the framework to your application bundle

_See [iOS Example Project](https://github.com/kishikawakatsumi/KeychainAccess/tree/master/Examples/Example-iOS) as reference._

<img src="https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/master/Screenshots/Installation.png" width="800px" />

## Author

kishikawa katsumi, kishikawakatsumi@mac.com

## License

KeychainAccess is available under the MIT license. See the LICENSE file for more info.
