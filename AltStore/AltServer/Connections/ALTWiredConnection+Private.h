//
//  ALTWiredConnection+Private.h
//  AltServer
//
//  Created by Riley Testut on 1/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#import "ALTWiredConnection.h"

#include <libimobiledevice/libimobiledevice.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTWiredConnection ()

@property (nonatomic, readwrite, getter=isConnected) BOOL connected;

@property (nonatomic, readonly) idevice_connection_t connection;

- (instancetype)initWithDevice:(ALTDevice *)device connection:(idevice_connection_t)connection;

@end

NS_ASSUME_NONNULL_END
