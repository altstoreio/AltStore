//
//  ALTDebugConnection+Private.h
//  AltServer
//
//  Created by Riley Testut on 2/19/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#import "ALTDebugConnection.h"

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/debugserver.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTDebugConnection ()

@property (nonatomic, readonly) dispatch_queue_t connectionQueue;

@property (nonatomic, nullable) debugserver_client_t client;

- (instancetype)initWithDevice:(ALTDevice *)device;

- (void)connectWithCompletionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
