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

NSErrorUserInfoKey const ALTUnderlyingErrorCodeErrorKey = @"underlyingErrorCode";
NSErrorUserInfoKey const ALTProvisioningProfileBundleIDErrorKey = @"bundleIdentifier";

@implementation NSError (ALTServerError)

+ (void)load
{
    [NSError setUserInfoValueProviderForDomain:AltServerErrorDomain provider:^id _Nullable(NSError * _Nonnull error, NSErrorUserInfoKey  _Nonnull userInfoKey) {
        if ([userInfoKey isEqualToString:NSLocalizedDescriptionKey])
        {
            return [error alt_localizedDescription];
        }
        
        return nil;
    }];
}

- (nullable NSString *)alt_localizedDescription
{
    switch ((ALTServerError)self.code)
    {
        case ALTServerErrorUnknown:
            return NSLocalizedString(@"An unknown error occured.", @"");
            
        case ALTServerErrorConnectionFailed:
            return NSLocalizedString(@"Could not connect to AltServer.", @"");
            
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
            return NSLocalizedString(@"You have reached the limit of 3 apps per device.", @"");
            
        case ALTServerErrorUnsupportediOSVersion:
            return NSLocalizedString(@"Your device must be running iOS 12.2 or later to install AltStore.", @"");
            
        case ALTServerErrorUnknownRequest:
            return NSLocalizedString(@"AltServer does not support this request.", @"");
            
        case ALTServerErrorUnknownResponse:
            return NSLocalizedString(@"Received an unknown response from AltServer.", @"");
            
        case ALTServerErrorInvalidAnisetteData:
            return NSLocalizedString(@"Invalid anisette data.", @"");
            
        case ALTServerErrorPluginNotFound:
            return NSLocalizedString(@"Could not connect to Mail plug-in. Please make sure Mail is running and that you've enabled the plug-in in Mail's preferences, then try again.", @"");
            
        case ALTServerErrorProfileInstallFailed:
            return [self underlyingProfileErrorLocalizedDescriptionWithBaseDescription:NSLocalizedString(@"Could not install profile", "")];
            
        case ALTServerErrorProfileCopyFailed:
            return [self underlyingProfileErrorLocalizedDescriptionWithBaseDescription:NSLocalizedString(@"Could not copy provisioning profiles", "")];
        
        case ALTServerErrorProfileRemoveFailed:
            return [self underlyingProfileErrorLocalizedDescriptionWithBaseDescription:NSLocalizedString(@"Could not remove profile", "")];
    }
}

- (NSString *)underlyingProfileErrorLocalizedDescriptionWithBaseDescription:(NSString *)baseDescription
{
    NSMutableString *localizedDescription = [NSMutableString string];
    
    NSString *bundleID = self.userInfo[ALTProvisioningProfileBundleIDErrorKey];
    if (bundleID)
    {
        [localizedDescription appendFormat:NSLocalizedString(@"%@ “%@”", @""), baseDescription, bundleID];
    }
    else
    {
        [localizedDescription appendString:baseDescription];
    }
    
    NSString *underlyingErrorCode = self.userInfo[ALTUnderlyingErrorCodeErrorKey];
    if (underlyingErrorCode)
    {
        [localizedDescription appendFormat:@" (%@)", underlyingErrorCode];
    }
    
    [localizedDescription appendString:@"."];
    
    return localizedDescription;
}
    
@end
