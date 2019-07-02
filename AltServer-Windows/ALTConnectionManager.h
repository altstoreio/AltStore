//
//  ALTConnectionManager.h
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTConnectionManager : NSObject

@property (class, nonatomic, readonly) ALTConnectionManager *sharedManager;

- (void)start;

@end

NS_ASSUME_NONNULL_END
