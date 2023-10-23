//
//  ALTConnection.h
//  AltKit
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Connection)
@protocol ALTConnection <NSObject>

- (void)sendData:(NSData *)data completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler NS_REFINED_FOR_SWIFT;
- (void)receiveDataWithExpectedSize:(NSInteger)expectedSize completionHandler:(void (^)(NSData * _Nullable, NSError * _Nullable))completionHandler NS_SWIFT_NAME(__receiveData(expectedSize:completionHandler:));

- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
