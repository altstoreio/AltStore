//
//  RSTCollectionViewCell.h
//  Roxas
//
//  Created by Riley Testut on 5/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface RSTCollectionViewCell : UICollectionViewCell

@property (nonatomic, readonly) UILabel *textLabel;
@property (nonatomic, readonly) UILabel *detailTextLabel;
@property (nonatomic, readonly) UIImageView *imageView;

@property (nonatomic, readonly) UIStackView *stackView;

@end

NS_ASSUME_NONNULL_END
