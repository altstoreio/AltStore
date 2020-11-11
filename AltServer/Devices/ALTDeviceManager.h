//
//  ALTDeviceManager.h
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AltSign.h"

@class ALTWiredConnection;
@class ALTNotificationConnection;

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ALTDeviceManagerDeviceDidConnectNotification NS_SWIFT_NAME(deviceManagerDeviceDidConnect);
extern NSNotificationName const ALTDeviceManagerDeviceDidDisconnectNotification NS_SWIFT_NAME(deviceManagerDeviceDidDisconnect);

@interface ALTDeviceManager : NSObject

@property (class, nonatomic, readonly) ALTDeviceManager *sharedManager;

@property (nonatomic, readonly) NSArray<ALTDevice *> *connectedDevices;
@property (nonatomic, readonly) NSArray<ALTDevice *> *availableDevices;

- (void)start;

/* App Installation */
- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)udid activeProvisioningProfiles:(nullable NSSet<NSString *> *)activeProvisioningProfiles completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;
- (void)removeAppForBundleIdentifier:(NSString *)bundleIdentifier fromDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

- (void)installProvisioningProfiles:(NSSet<ALTProvisioningProfile *> *)provisioningProfiles toDeviceWithUDID:(NSString *)udid activeProvisioningProfiles:(nullable NSSet<NSString *> *)activeProvisioningProfiles completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;
- (void)removeProvisioningProfilesForBundleIdentifiers:(NSSet<NSString *> *)bundleIdentifiers fromDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

/* Connections */
- (void)startWiredConnectionToDevice:(ALTDevice *)device completionHandler:(void (^)(ALTWiredConnection *_Nullable connection, NSError *_Nullable error))completionHandler;
- (void)startNotificationConnectionToDevice:(ALTDevice *)device completionHandler:(void (^)(ALTNotificationConnection *_Nullable connection, NSError *_Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
