//
//  TestErrors.swift
//  AltTests
//
//  Created by Riley Testut on 10/17/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
@testable import AltStore
@testable import AltStoreCore

import AltSign

typealias TestError = TestErrorCode.Error
enum TestErrorCode: Int, ALTErrorEnum, CaseIterable
{
    static var errorDomain: String {
        return "TestErrorDomain"
    }
    
    case computerOnFire
    case alienInvasion
    
    var errorFailureReason: String {
        switch self
        {
        case .computerOnFire: return "Your computer is on fire."
        case .alienInvasion: return "There is an ongoing alien invasion."
        }
    }
}

extension DefaultLocalizedError<TestErrorCode>
{
    static var allErrors: [TestError] {
        return Code.allCases.map { TestError($0) }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .computerOnFire: return "Try using a fire extinguisher!"
        case .alienInvasion: return nil // Nothing you can do to stop the aliens.
        }
    }
}

let allTestErrors = TestErrorCode.allCases.map { TestError($0) }

extension ALTLocalizedError where Self.Code: ALTErrorEnum & CaseIterable
{
    static var testErrors: [DefaultLocalizedError<Code>] {
        return Code.allCases.map { DefaultLocalizedError<Code>($0) }
    }
}

extension AuthenticationError
{
    static var testErrors: [AuthenticationError] {
        return AuthenticationError.Code.allCases.map { code -> AuthenticationError in
            return AuthenticationError(code)
        }
    }
}


extension VerificationError
{
    static var testErrors: [VerificationError] {
        let app = ALTApplication(fileURL: Bundle.main.bundleURL)!
        
        return VerificationError.Code.allCases.compactMap { code -> VerificationError? in
            switch code
            {
            case .mismatchedBundleIdentifiers: return VerificationError.mismatchedBundleIdentifiers(sourceBundleID: "com.rileytestut.App", app: app)
            case .iOSVersionNotSupported: return VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: OperatingSystemVersion(majorVersion: 21, minorVersion: 1, patchVersion: 0))
            case .mismatchedHash: return VerificationError.mismatchedHash("12345", expectedHash: "67890", app: app)
            case .mismatchedVersion: return VerificationError.mismatchedVersion("1.0", expectedVersion: "1.1", app: app)
            case .mismatchedBuildVersion: return VerificationError.mismatchedBuildVersion("1", expectedVersion: "28", app: app)
            case .undeclaredPermissions: return VerificationError.undeclaredPermissions([ALTEntitlement.appGroups, ALTAppPrivacyPermission.bluetooth], app: app)
            case .addedPermissions: return nil //VerificationError.addedPermissions([ALTAppPrivacyPermission.appleMusic, ALTEntitlement.interAppAudio], appVersion: app)
            }
        }
    }
}

extension PatchAppError
{
    static var testErrors: [PatchAppError] {
        PatchAppError.Code.allCases.map { code -> PatchAppError in
            switch code
            {
            case .unsupportedOperatingSystemVersion: return PatchAppError(.unsupportedOperatingSystemVersion(.init(majorVersion: 15, minorVersion: 5, patchVersion: 1)))
            }
        }
    }
}

extension AltTests
{
    static var allLocalErrors: [any ALTLocalizedError] {
        let errors = [
            OperationError.testErrors as [any ALTLocalizedError],
            AuthenticationError.testErrors as [any ALTLocalizedError],
            VerificationError.testErrors as [any ALTLocalizedError],
            PatreonAPIError.testErrors as [any ALTLocalizedError],
            RefreshError.testErrors as [any ALTLocalizedError],
            PatchAppError.testErrors as [any ALTLocalizedError]
        ].flatMap { $0 }
        
        return errors
    }
    
    static var allRemoteErrors: [any Error] {
        let errors: [any Error] = ALTServerError.testErrors + ALTAppleAPIError.testErrors
        return errors
    }
    
    static var allRealErrors: [any Error] {
        return self.allLocalErrors + self.allRemoteErrors
    }
}

extension ALTServerError
{
    static var testErrors: [ALTServerError] {
        [
//            ALTServerError(.underlyingError), // Doesn't occur in practice? But does mess up tests
            
            ALTServerError(.underlyingError, userInfo: [NSUnderlyingErrorKey: ALTServerError(.pluginNotFound)]),
            ALTServerError(ALTServerError(.pluginNotFound)),
            ALTServerError(TestError(.computerOnFire)),
            ALTServerError(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "~/Desktop/TestFile"])),
            
            ALTServerError(.unknown),
            
            ALTServerError(.connectionFailed),
            ALTServerError(ALTServerConnectionError(.timedOut, userInfo: [ALTUnderlyingErrorDomainErrorKey: "Mobile Image Mounter",
                                                                            ALTUnderlyingErrorCodeErrorKey: -27,
                                                                                     ALTDeviceNameErrorKey: "Riley's iPhone"])),
            
            ALTServerError(.lostConnection),
            ALTServerError(.deviceNotFound),
            ALTServerError(.deviceWriteFailed),
            ALTServerError(.invalidRequest),
            ALTServerError(.invalidResponse),
            ALTServerError(.invalidApp),
            ALTServerError(.installationFailed),
            ALTServerError(.maximumFreeAppLimitReached),
            ALTServerError(.unsupportediOSVersion),
            ALTServerError(.unknownRequest),
            ALTServerError(.unknownResponse),
            ALTServerError(.invalidAnisetteData),
            ALTServerError(.pluginNotFound),
            ALTServerError(.profileNotFound),
            ALTServerError(.appDeletionFailed),
            ALTServerError(.requestedAppNotRunning, userInfo: [ALTAppNameErrorKey: "Delta", ALTDeviceNameErrorKey: "Riley's iPhone"]),
            ALTServerError(.incompatibleDeveloperDisk, userInfo: [ALTOperatingSystemNameErrorKey: "iOS",
                                                               ALTOperatingSystemVersionErrorKey: "13.0",
                                                                              NSFilePathErrorKey: URL(fileURLWithPath: "~/Library/Application Support/com.rileytestut.AltServer/DeveloperDiskImages/iOS/13.0/DeveloperDiskImage.dmg").path]),
        ]
    }
}

extension ALTAppleAPIError.Code: CaseIterable
{
    public static var allCases: [Self] {
        return [.unknown, .invalidParameters,
                .incorrectCredentials, .appSpecificPasswordRequired,
                .noTeams,
                .invalidDeviceID, .deviceAlreadyRegistered,
                .invalidCertificateRequest, .certificateDoesNotExist,
                .invalidAppIDName, .invalidBundleIdentifier, .bundleIdentifierUnavailable, .appIDDoesNotExist, .maximumAppIDLimitReached,
                .invalidAppGroup, .appGroupDoesNotExist,
                .invalidProvisioningProfileIdentifier, .provisioningProfileDoesNotExist,
                .requiresTwoFactorAuthentication, .incorrectVerificationCode, .authenticationHandshakeFailed,
                .invalidAnisetteData]
    }
}

extension ALTAppleAPIError
{
    static var testErrors: [Self] {
        Code.allCases.map { code -> ALTAppleAPIError in
            return ALTAppleAPIError(code)
//
//            switch code
//            {
//            case .unknown: return ALTAppleAPIError(.unknown)
//            case .invalidParameters:
//            case .incorrectCredentials:
//            case .appSpecificPasswordRequired:
//            case .noTeams:
//            case .invalidDeviceID:
//            case .deviceAlreadyRegistered:
//            case .invalidCertificateRequest:
//            case .certificateDoesNotExist:
//            case .invalidAppIDName:
//            case .invalidBundleIdentifier:
//            case .bundleIdentifierUnavailable:
//            case .appIDDoesNotExist:
//            case .maximumAppIDLimitReached:
//            case .invalidAppGroup:
//            case .appGroupDoesNotExist:
//            case .invalidProvisioningProfileIdentifier:
//            case .provisioningProfileDoesNotExist:
//            case .requiresTwoFactorAuthentication:
//            case .incorrectVerificationCode:
//            case .authenticationHandshakeFailed:
//            case .invalidAnisetteData:
//            @unknown default:
//            }
        }
    }
}

extension OperationError
{
    static var testErrors: [OperationError] {
        OperationError.Code.allCases.map { code -> OperationError in
            switch code
            {
            case .unknown: return .unknown()
            case .unknownResult: return .unknownResult
            case .timedOut: return .timedOut
            case .notAuthenticated: return .notAuthenticated
            case .appNotFound: return .appNotFound(name: "Delta")
            case .unknownUDID: return .unknownUDID
            case .invalidApp: return .invalidApp
            case .invalidParameters: return .invalidParameters
            case .maximumAppIDLimitReached: return .maximumAppIDLimitReached(appName: "Delta", requiredAppIDs: 2, availableAppIDs: 1, expirationDate: Date())
            case .noSources: return .noSources
            case .openAppFailed: return .openAppFailed(name: "Delta")
            case .missingAppGroup: return .missingAppGroup
            case .serverNotFound: return .serverNotFound
            case .connectionFailed: return .connectionFailed
            case .connectionDropped: return .connectionDropped
            case .forbidden: return .forbidden()
            case .pledgeRequired: return .pledgeRequired(appName: "Delta")
            case .pledgeInactive: return .pledgeInactive(appName: "Delta")
            }
        }
    }
}
