//
//  NSError+ALTServerError.m
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "NSError+ALTServerError.h"

NSErrorDomain const AltServerErrorDomain = @"com.rileytestut.AltServer";
NSErrorDomain const AltServerInstallationErrorDomain = @"com.rileytestut.AltServer.Installation";
NSErrorDomain const AltServerConnectionErrorDomain = @"com.rileytestut.AltServer.Connection";

NSErrorUserInfoKey const ALTUnderlyingErrorDomainErrorKey = @"underlyingErrorDomain";
NSErrorUserInfoKey const ALTUnderlyingErrorCodeErrorKey = @"underlyingErrorCode";
NSErrorUserInfoKey const ALTProvisioningProfileBundleIDErrorKey = @"bundleIdentifier";
NSErrorUserInfoKey const ALTAppNameErrorKey = @"appName";
NSErrorUserInfoKey const ALTDeviceNameErrorKey = @"deviceName";

@implementation NSError (ALTServerError)

+ (void)load
{
    [NSError setUserInfoValueProviderForDomain:AltServerErrorDomain provider:^id _Nullable(NSError * _Nonnull error, NSErrorUserInfoKey  _Nonnull userInfoKey) {
        if ([userInfoKey isEqualToString:NSLocalizedFailureReasonErrorKey])
        {
            return [error altserver_localizedFailureReason];
        }
        else if ([userInfoKey isEqualToString:NSLocalizedRecoverySuggestionErrorKey])
        {
            return [error altserver_localizedRecoverySuggestion];
        }
        
        return nil;
    }];
    
    [NSError setUserInfoValueProviderForDomain:AltServerConnectionErrorDomain provider:^id _Nullable(NSError * _Nonnull error, NSErrorUserInfoKey  _Nonnull userInfoKey) {
        if ([userInfoKey isEqualToString:NSLocalizedDescriptionKey])
        {
            return [error altserver_connection_localizedDescription];
        }
        else if ([userInfoKey isEqualToString:NSLocalizedRecoverySuggestionErrorKey])
        {
            return [error altserver_connection_localizedRecoverySuggestion];
        }
        
        return nil;
    }];
}

- (nullable NSString *)altserver_localizedFailureReason
{
    switch ((ALTServerError)self.code)
    {
        case ALTServerErrorUnderlyingError:
        {
            NSError *underlyingError = self.userInfo[NSUnderlyingErrorKey];
            if (underlyingError.localizedFailureReason != nil)
            {
                return underlyingError.localizedFailureReason;
            }

            NSString *underlyingErrorCode = self.userInfo[ALTUnderlyingErrorCodeErrorKey];
            if (underlyingErrorCode != nil)
            {
                return [NSString stringWithFormat:NSLocalizedString(@"Error code: %@", @""), underlyingErrorCode];
            }
            
            return nil;
        }
        
        case ALTServerErrorUnknown:
            return NSLocalizedString(@"An unknown error occured.", @"");
            
        case ALTServerErrorConnectionFailed:
#if TARGET_OS_OSX
            return NSLocalizedString(@"Could not connect to device.", @"");
#else
            return NSLocalizedString(@"Could not connect to AltServer.", @"");
#endif
            
        case ALTServerErrorLostConnection:
            return NSLocalizedString(@"Lost connection to AltServer.", @"");
            
        case ALTServerErrorDeviceNotFound:
            return NSLocalizedString(@"AltServer could not find this device.", @"");
            
        case ALTServerErrorDeviceWriteFailed:
            return NSLocalizedString(@"Failed to write app data to device.", @"");
            
        case ALTServerErrorInvalidRequest:
            return NSLocalizedString(@"AltServer received an invalid request.", @"");
            
        case ALTServerErrorInvalidResponse:
            return NSLocalizedString(@"AltServer sent an invalid response.", @"");
            
        case ALTServerErrorInvalidApp:
            return NSLocalizedString(@"The app is invalid.", @"");
            
        case ALTServerErrorInstallationFailed:
            return NSLocalizedString(@"An error occured while installing the app.", @"");
            
        case ALTServerErrorMaximumFreeAppLimitReached:
            return NSLocalizedString(@"Cannot activate more than 3 apps and app extensions.", @"");
            
        case ALTServerErrorUnsupportediOSVersion:
            return NSLocalizedString(@"Your device must be running iOS 12.2 or later to install AltStore.", @"");
            
        case ALTServerErrorUnknownRequest:
            return NSLocalizedString(@"AltServer does not support this request.", @"");
            
        case ALTServerErrorUnknownResponse:
            return NSLocalizedString(@"Received an unknown response from AltServer.", @"");
            
        case ALTServerErrorInvalidAnisetteData:
            return NSLocalizedString(@"Invalid anisette data.", @"");
            
        case ALTServerErrorPluginNotFound:
            return NSLocalizedString(@"Could not connect to Mail plug-in.", @"");
            
        case ALTServerErrorProfileNotFound:
            return [self profileErrorLocalizedDescriptionWithBaseDescription:NSLocalizedString(@"Could not find profile", "")];
            
        case ALTServerErrorAppDeletionFailed:
            return NSLocalizedString(@"An error occured while removing the app.", @"");
    }
}

- (nullable NSString *)altserver_localizedRecoverySuggestion
{
    switch ((ALTServerError)self.code)
    {
        case ALTServerErrorConnectionFailed:
        case ALTServerErrorDeviceNotFound:
            return NSLocalizedString(@"Make sure you have trusted this device with your computer and WiFi sync is enabled.", @"");
            
        case ALTServerErrorPluginNotFound:
            return NSLocalizedString(@"Make sure Mail is running and the plug-in is enabled in Mail's preferences.", @"");
            
        case ALTServerErrorMaximumFreeAppLimitReached:
            return NSLocalizedString(@"Make sure “Offload Unused Apps” is disabled in Settings > iTunes & App Stores, then install or delete all offloaded apps.", @"");
            
        default:
            return nil;
    }
}

- (NSString *)profileErrorLocalizedDescriptionWithBaseDescription:(NSString *)baseDescription
{
    NSString *localizedDescription = nil;
    
    NSString *bundleID = self.userInfo[ALTProvisioningProfileBundleIDErrorKey];
    if (bundleID)
    {
        localizedDescription = [NSString stringWithFormat:@"%@ “%@”", baseDescription, bundleID];
    }
    else
    {
        localizedDescription = [NSString stringWithFormat:@"%@.", baseDescription];
    }
    
    return localizedDescription;
}

#pragma mark - AltServerConnectionErrorDomain -

- (nullable NSString *)altserver_connection_localizedDescription
{
    switch ((ALTServerConnectionError)self.code)
    {
        case ALTServerConnectionErrorUnknown:
        {
            NSString *underlyingErrorDomain = self.userInfo[ALTUnderlyingErrorDomainErrorKey];
            NSString *underlyingErrorCode = self.userInfo[ALTUnderlyingErrorCodeErrorKey];
            
            if (underlyingErrorDomain != nil && underlyingErrorCode != nil)
            {
                return [NSString stringWithFormat:NSLocalizedString(@"%@ error %@.", @""), underlyingErrorDomain, underlyingErrorCode];
            }
            else if (underlyingErrorCode != nil)
            {
                return [NSString stringWithFormat:NSLocalizedString(@"Connection error code: %@", @""), underlyingErrorCode];
            }
            
            return nil;
        }
            
        case ALTServerConnectionErrorDeviceLocked:
        {
            NSString *deviceName = self.userInfo[ALTDeviceNameErrorKey] ?: NSLocalizedString(@"The device", @"");
            return [NSString stringWithFormat:NSLocalizedString(@"%@ is currently locked.", @""), deviceName];
        }
            
        case ALTServerConnectionErrorInvalidRequest:
        {
            NSString *deviceName = self.userInfo[ALTDeviceNameErrorKey] ?: NSLocalizedString(@"The device", @"");
            return [NSString stringWithFormat:NSLocalizedString(@"%@ received an invalid request from AltServer.", @""), deviceName];
        }
            
        case ALTServerConnectionErrorInvalidResponse:
        {
            NSString *deviceName = self.userInfo[ALTDeviceNameErrorKey] ?: NSLocalizedString(@"the device", @"");
            return [NSString stringWithFormat:NSLocalizedString(@"AltServer received an invalid response from %@.", @""), deviceName];
        }
            
        case ALTServerConnectionErrorUsbmuxd:
        {
            return NSLocalizedString(@"There was an issue communicating with the usbmuxd daemon.", @"");
        }
            
        case ALTServerConnectionErrorSSL:
        {
            NSString *deviceName = self.userInfo[ALTDeviceNameErrorKey] ?: NSLocalizedString(@"the device", @"");
            return [NSString stringWithFormat:NSLocalizedString(@"AltServer could not establish a secure connection to %@.", @""), deviceName];
        }
            
        case ALTServerConnectionErrorTimedOut:
        {
            NSString *deviceName = self.userInfo[ALTDeviceNameErrorKey] ?: NSLocalizedString(@"the device", @"");
            return [NSString stringWithFormat:NSLocalizedString(@"AltServer's connection to %@ timed out.", @""), deviceName];
        }
    }
    
    return nil;
}

- (nullable NSString *)altserver_connection_localizedRecoverySuggestion
{
    switch ((ALTServerConnectionError)self.code)
    {
        case ALTServerConnectionErrorDeviceLocked:
        {
            return NSLocalizedString(@"Please unlock the device with your passcode and try again.", @"");
        }
            
        case ALTServerConnectionErrorUnknown:
        case ALTServerConnectionErrorInvalidRequest:
        case ALTServerConnectionErrorInvalidResponse:
        case ALTServerConnectionErrorUsbmuxd:
        case ALTServerConnectionErrorSSL:
        case ALTServerConnectionErrorTimedOut:
        {
            return nil;
        }
    }
}
    
@end
