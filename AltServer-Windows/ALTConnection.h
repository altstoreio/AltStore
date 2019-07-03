//
//  ALTConnection.h
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTConnection : NSObject

@property (nonatomic, readonly) NSInputStream *inputStream;
@property (nonatomic, readonly) NSOutputStream *outputStream;

- (instancetype)initWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream;

- (void)processAppRequestWithCompletion:(void (^)(BOOL success, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
