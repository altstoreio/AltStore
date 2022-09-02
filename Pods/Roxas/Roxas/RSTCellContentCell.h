//
//  RSTCellContentCell.h
//  Roxas
//
//  Created by Riley Testut on 2/20/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@protocol RSTCellContentCell <NSObject>

@property (class, nullable, nonatomic, readonly) UINib *nib;

+ (nullable instancetype)instantiateWithNib:(UINib *)nib;

@end

NS_ASSUME_NONNULL_END
