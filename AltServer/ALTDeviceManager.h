//
//  ALTDeviceManager.h
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <AltSign/AltSign.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTDeviceManager : NSObject

@property (class, nonatomic, readonly) ALTDeviceManager *sharedManager;

@property (nonatomic, readonly) NSArray<ALTDevice *> *connectedDevices;

@end

NS_ASSUME_NONNULL_END
