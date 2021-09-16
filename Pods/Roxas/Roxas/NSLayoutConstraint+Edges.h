//
//  NSLayoutConstraint+Edges.h
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface NSLayoutConstraint (Edges)

+ (NSArray<NSLayoutConstraint *> *)constraintsPinningEdgesOfView:(UIView *)view1 toEdgesOfView:(UIView *)view2;
+ (NSArray<NSLayoutConstraint *> *)constraintsPinningEdgesOfView:(UIView *)view1 toEdgesOfView:(UIView *)view2 withInsets:(UIEdgeInsets)insets;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface UIView (PinnedEdges)

- (void)addSubview:(UIView *)view pinningEdgesWithInsets:(UIEdgeInsets)insets;

@end

NS_ASSUME_NONNULL_END
