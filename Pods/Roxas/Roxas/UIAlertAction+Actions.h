//
//  UIAlertAction+Actions.h
//  Roxas
//
//  Created by Riley Testut on 5/9/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface UIAlertAction (Actions)

@property (class, nonatomic, readonly) UIAlertAction *okAction;
@property (class, nonatomic, readonly) UIAlertAction *cancelAction;

@end

NS_ASSUME_NONNULL_END
