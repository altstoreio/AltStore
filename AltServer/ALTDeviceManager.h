//
//  ALTDeviceManager.h
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AltSign/AltSign.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ALTDeviceErrorDomain;

typedef NS_ERROR_ENUM(ALTDeviceErrorDomain, ALTDeviceError)
{
    ALTDeviceErrorUnknown,
    ALTDeviceErrorNotConnected,
    ALTDeviceErrorConnectionFailed,
    ALTDeviceErrorWriteFailed,
};

@interface ALTDeviceManager : NSObject

@property (class, nonatomic, readonly) ALTDeviceManager *sharedManager;

@property (nonatomic, readonly) NSArray<ALTDevice *> *connectedDevices;

- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDevice:(ALTDevice *)altDevice completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
