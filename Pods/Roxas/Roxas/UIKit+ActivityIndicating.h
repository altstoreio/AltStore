//
//  UIKit+ActivityIndicating.h
//  Roxas
//
//  Created by Riley Testut on 4/8/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTActivityIndicating.h"

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface UIButton (ActivityIndicating) <RSTActivityIndicating>
@property (nonatomic, readonly) UIActivityIndicatorView *rst_activityIndicatorView NS_SWIFT_NAME(activityIndicatorView);
@end

@interface UIBarButtonItem (ActivityIndicating) <RSTActivityIndicating>
@property (nonatomic, readonly) UIActivityIndicatorView *rst_activityIndicatorView NS_SWIFT_NAME(activityIndicatorView);
@end

@interface UIImageView (ActivityIndicating) <RSTActivityIndicating>
@property (nonatomic, readonly) UIActivityIndicatorView *rst_activityIndicatorView NS_SWIFT_NAME(activityIndicatorView);
@end

@interface UITextField (ActivityIndicating) <RSTActivityIndicating>
@property (nonatomic, readonly) UIActivityIndicatorView *rst_activityIndicatorView NS_SWIFT_NAME(activityIndicatorView);
@end

@interface UIApplication (ActivityIndicating) <RSTActivityIndicating>
@end

NS_ASSUME_NONNULL_END

