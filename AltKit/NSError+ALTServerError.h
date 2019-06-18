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

typedef NS_ERROR_ENUM(AltServerErrorDomain, ALTServerError)
{
    ALTServerErrorUnknown,
    ALTServerErrorConnectionFailed,
    ALTServerErrorLostConnection,
    
    ALTServerErrorDeviceNotFound,
    ALTServerErrorDeviceWriteFailed,
    
    ALTServerErrorInvalidRequest,
    ALTServerErrorInvalidResponse,
    
    ALTServerErrorInvalidApp,
    ALTServerErrorInstallationFailed,
    ALTServerErrorMaximumFreeAppLimitReached,
};

NS_ASSUME_NONNULL_BEGIN

@interface NSError (ALTServerError)
@end

NS_ASSUME_NONNULL_END
