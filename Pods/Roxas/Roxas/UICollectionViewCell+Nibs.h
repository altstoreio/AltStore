//
//  UICollectionViewCell+Nibs.h
//  Roxas
//
//  Created by Riley Testut on 8/3/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface UICollectionViewCell (Nibs)

@property (class, nullable, nonatomic, readonly) UINib *nib;

+ (nullable instancetype)instantiateWithNib:(UINib *)nib;

@end

NS_ASSUME_NONNULL_END
