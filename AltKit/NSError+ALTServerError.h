//
//  NSError+ALTServerError.h
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSErrorDomain const AltServerErrorDomain;
extern NSErrorDomain const AltServerInstallationErrorDomain;

extern NSErrorUserInfoKey const ALTUnderlyingErrorCodeErrorKey;
extern NSErrorUserInfoKey const ALTProvisioningProfileBundleIDErrorKey;

typedef NS_ERROR_ENUM(AltServerErrorDomain, ALTServerError)
{
    ALTServerErrorUnknown = 0,
    ALTServerErrorConnectionFailed = 1,
    ALTServerErrorLostConnection = 2,
    
    ALTServerErrorDeviceNotFound = 3,
    ALTServerErrorDeviceWriteFailed = 4,
    
    ALTServerErrorInvalidRequest = 5,
    ALTServerErrorInvalidResponse = 6,
    
    ALTServerErrorInvalidApp = 7,
    ALTServerErrorInstallationFailed = 8,
    ALTServerErrorMaximumFreeAppLimitReached = 9,
    ALTServerErrorUnsupportediOSVersion = 10,
    
    ALTServerErrorUnknownRequest = 11,
    ALTServerErrorUnknownResponse = 12,
    
    ALTServerErrorInvalidAnisetteData = 13,
    ALTServerErrorPluginNotFound = 14,
    
    ALTServerErrorProfileInstallFailed = 15,
    ALTServerErrorProfileCopyFailed = 16,
    ALTServerErrorProfileRemoveFailed = 17,
};

NS_ASSUME_NONNULL_BEGIN

@interface NSError (ALTServerError)
@end

NS_ASSUME_NONNULL_END
