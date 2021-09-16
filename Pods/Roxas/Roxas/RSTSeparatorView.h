//
//  RSTSeparatorView.h
//  Roxas
//
//  Created by Riley Testut on 6/29/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

IB_DESIGNABLE
@interface RSTSeparatorView : UIView

@property (null_resettable, nonatomic) UIColor *tintColor;

@property (nonatomic) IBInspectable CGFloat lineWidth;

@end

NS_ASSUME_NONNULL_END
