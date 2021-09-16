//
//  RSTHasher.h
//  Roxas
//
//  Created by Riley Testut on 11/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface RSTHasher : NSObject

+ (nullable NSString *)sha1HashOfFileAtURL:(NSURL *)fileURL error:(NSError **)error;
+ (NSString *)sha1HashOfData:(NSData *)data;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
