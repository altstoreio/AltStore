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

@interface ALTDeviceManager : NSObject

@property (class, nonatomic, readonly) ALTDeviceManager *sharedManager;

@property (nonatomic, readonly) NSArray<ALTDevice *> *connectedDevices;

- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
