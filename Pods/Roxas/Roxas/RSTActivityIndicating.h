//
//  RSTActivityIndicating.h
//  Roxas
//
//  Created by Riley Testut on 4/2/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@protocol RSTActivityIndicating <NSObject>

@property (nonatomic, getter=isIndicatingActivity) BOOL indicatingActivity;

@property (nonatomic, readonly) NSUInteger activityCount;

- (void)incrementActivityCount;
- (void)decrementActivityCount;

@end

NS_ASSUME_NONNULL_END
