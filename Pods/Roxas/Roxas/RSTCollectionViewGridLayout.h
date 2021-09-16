//
//  RSTCollectionViewGridLayout.h
//  Roxas
//
//  Created by Riley Testut on 5/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import UIKit;

typedef NS_ENUM(NSInteger, RSTCollectionViewGridLayoutDistribution)
{
    RSTCollectionViewGridLayoutDistributionFlow,
    RSTCollectionViewGridLayoutDistributionFill
};

NS_ASSUME_NONNULL_BEGIN

@interface RSTCollectionViewGridLayoutAttributes : UICollectionViewLayoutAttributes

@property (nonatomic) CGSize preferredItemSize;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface RSTCollectionViewGridLayout : UICollectionViewFlowLayout

#if TARGET_INTERFACE_BUILDER
@property (nonatomic) IBInspectable NSInteger distribution;
#else
@property (nonatomic) IBInspectable RSTCollectionViewGridLayoutDistribution distribution;
#endif

@property (nonatomic) IBInspectable BOOL automaticallyAdjustsSectionInsets;

@end

NS_ASSUME_NONNULL_END
