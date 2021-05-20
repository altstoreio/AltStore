//
//  ALTDebugConnection.h
//  AltServer
//
//  Created by Riley Testut on 2/19/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#import "AltSign.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(DebugConnection)
@interface ALTDebugConnection : NSObject

@property (nonatomic, copy, readonly) ALTDevice *device;

- (void)enableUnsignedCodeExecutionForProcessWithName:(NSString *)processName completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler;

- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
