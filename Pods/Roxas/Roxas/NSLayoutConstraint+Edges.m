//
//  NSLayoutConstraint+Edges.m
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "NSLayoutConstraint+Edges.h"

@implementation NSLayoutConstraint (Edges)

+ (NSArray<NSLayoutConstraint *> *)constraintsPinningEdgesOfView:(UIView *)view1 toEdgesOfView:(UIView *)view2
{
    return [self constraintsPinningEdgesOfView:view1 toEdgesOfView:view2 withInsets:UIEdgeInsetsZero];
}

+ (NSArray<NSLayoutConstraint *> *)constraintsPinningEdgesOfView:(UIView *)view1 toEdgesOfView:(UIView *)view2 withInsets:(UIEdgeInsets)insets
{
    NSLayoutConstraint *topConstraint = [view1.topAnchor constraintEqualToAnchor:view2.topAnchor constant:insets.top];
    NSLayoutConstraint *bottomConstraint = [view2.bottomAnchor constraintEqualToAnchor:view1.bottomAnchor constant:insets.bottom];
    NSLayoutConstraint *leftConstraint = [view1.leftAnchor constraintEqualToAnchor:view2.leftAnchor constant:insets.left];
    NSLayoutConstraint *rightConstraint = [view2.rightAnchor constraintEqualToAnchor:view1.rightAnchor constant:insets.right];
    
    return @[topConstraint, bottomConstraint, leftConstraint, rightConstraint];
}

@end


@implementation UIView (PinnedEdges)

- (void)addSubview:(UIView *)view pinningEdgesWithInsets:(UIEdgeInsets)insets
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:view];
    
    NSArray<NSLayoutConstraint *> *pinningConstraints = [NSLayoutConstraint constraintsPinningEdgesOfView:view toEdgesOfView:self withInsets:insets];
    [NSLayoutConstraint activateConstraints:pinningConstraints];
}

@end
