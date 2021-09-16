//
//  RSTLaunchViewController.h
//  Roxas
//
//  Created by Riley Testut on 3/24/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface RSTLaunchCondition : NSObject

@property (nonatomic, copy, readonly) BOOL (^condition)(void);
@property (nonatomic, copy, readonly) void (^action)(void (^completionHandler)(NSError *_Nullable error));

- (instancetype)initWithCondition:(BOOL (^)(void))condition action:(void (^)(void (^completionHandler)(NSError *_Nullable error)))action;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface RSTLaunchViewController : UIViewController

@property (nonatomic, readonly) NSArray<RSTLaunchCondition *> *launchConditions;

- (void)handleLaunchConditions;
- (void)handleLaunchError:(NSError *)error;

- (void)finishLaunching;

@end

NS_ASSUME_NONNULL_END
