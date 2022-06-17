//
//  NSError+libimobiledevice.m
//  AltServer
//
//  Created by Riley Testut on 3/23/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#import "NSError+libimobiledevice.h"
#import "NSError+ALTServerError.h"

@implementation NSError (libimobiledevice)

+ (nullable instancetype)errorWithMobileImageMounterError:(mobile_image_mounter_error_t)error device:(nullable ALTDevice *)device
{
    NSMutableDictionary *userInfo = [@{
        ALTUnderlyingErrorDomainErrorKey: @"Mobile Image Mounter",
        ALTUnderlyingErrorCodeErrorKey: [@(error) description],
    } mutableCopy];
    
    if (device)
    {
        userInfo[ALTDeviceNameErrorKey] = device.name;
    }
    
    switch (error)
    {
        case MOBILE_IMAGE_MOUNTER_E_SUCCESS: return nil;
        case MOBILE_IMAGE_MOUNTER_E_INVALID_ARG: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidRequest userInfo:userInfo];
        case MOBILE_IMAGE_MOUNTER_E_PLIST_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidResponse userInfo:userInfo];
        case MOBILE_IMAGE_MOUNTER_E_CONN_FAILED: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUsbmuxd userInfo:userInfo];
        case MOBILE_IMAGE_MOUNTER_E_COMMAND_FAILED: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidRequest userInfo:userInfo];
        case MOBILE_IMAGE_MOUNTER_E_DEVICE_LOCKED: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorDeviceLocked userInfo:userInfo];
        case MOBILE_IMAGE_MOUNTER_E_UNKNOWN_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUnknown userInfo:userInfo];
    }
}

+ (nullable instancetype)errorWithDebugServerError:(debugserver_error_t)error device:(nullable ALTDevice *)device
{
    NSMutableDictionary *userInfo = [@{
        ALTUnderlyingErrorDomainErrorKey: @"Debug Server",
        ALTUnderlyingErrorCodeErrorKey: [@(error) description],
    } mutableCopy];
    
    if (device)
    {
        userInfo[ALTDeviceNameErrorKey] = device.name;
    }
    
    switch (error)
    {
        case DEBUGSERVER_E_SUCCESS: return nil;
        case DEBUGSERVER_E_INVALID_ARG: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidRequest userInfo:userInfo];
        case DEBUGSERVER_E_MUX_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUsbmuxd userInfo:userInfo];
        case DEBUGSERVER_E_SSL_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorSSL userInfo:userInfo];
        case DEBUGSERVER_E_RESPONSE_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidResponse userInfo:userInfo];
        case DEBUGSERVER_E_TIMEOUT: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorTimedOut userInfo:userInfo];
        case DEBUGSERVER_E_UNKNOWN_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUnknown userInfo:userInfo];
    }
}

+ (nullable instancetype)errorWithInstallationProxyError:(instproxy_error_t)error device:(nullable ALTDevice *)device
{
    NSMutableDictionary *userInfo = [@{
        ALTUnderlyingErrorDomainErrorKey: @"Installation Proxy",
        ALTUnderlyingErrorCodeErrorKey: [@(error) description],
    } mutableCopy];
    
    if (device)
    {
        userInfo[ALTDeviceNameErrorKey] = device.name;
    }
    
    switch (error)
    {
        case INSTPROXY_E_SUCCESS: return nil;
        case INSTPROXY_E_INVALID_ARG: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidRequest userInfo:userInfo];
        case INSTPROXY_E_PLIST_ERROR: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorInvalidResponse userInfo:userInfo];
        case INSTPROXY_E_CONN_FAILED: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUsbmuxd userInfo:userInfo];
        case INSTPROXY_E_RECEIVE_TIMEOUT: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorTimedOut userInfo:userInfo];
//        case INSTPROXY_E_DEVICE_OS_VERSION_TOO_LOW: return [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorUnsupportediOSVersion userInfo:nil]; // Error message assumes we're installing AltStore
        default: return [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUnknown userInfo:userInfo];
    }
}

@end
