//
//  RSTNibView.m
//  Roxas
//
//  Created by Riley Testut on 8/23/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTNibView.h"

#import "NSLayoutConstraint+Edges.h"

@implementation RSTNibView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self initializeFromNib];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        [self initializeFromNib];
    }
    
    return self;
}

- (void)initializeFromNib
{
    NSString *name = NSStringFromClass(self.class);
    
    NSArray<NSString *> *components = [name componentsSeparatedByString:@"."];
    name = [components lastObject];
    
    UINib *nib = [UINib nibWithNibName:name bundle:[NSBundle bundleForClass:self.class]];
    NSArray *views = [nib instantiateWithOwner:self options:nil];
    
    UIView *nibView = [views firstObject];
    NSAssert(nibView != nil && [nibView isKindOfClass:[UIView class]], @"The nib for %@ must contain a root UIView.", name);
    
    nibView.preservesSuperviewLayoutMargins = YES;
    [self addSubview:nibView pinningEdgesWithInsets:UIEdgeInsetsZero];
}

@end
