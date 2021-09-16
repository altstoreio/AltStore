//
//  RSTSeparatorView.m
//  Roxas
//
//  Created by Riley Testut on 6/29/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTSeparatorView.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTSeparatorView ()
{
    BOOL _layoutMarginsDidChange;
}

@property (nonatomic, readonly) UIView *separator;

@end

NS_ASSUME_NONNULL_END

@implementation RSTSeparatorView

#pragma mark - Initialization -

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self initialize];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        [self initialize];
    }
    
    return self;
}

- (void)initialize
{
    _lineWidth = 0.5;
    
    self.userInteractionEnabled = NO;
    self.backgroundColor = nil;
    
    _separator = [[UIView alloc] initWithFrame:self.frame];
    _separator.translatesAutoresizingMaskIntoConstraints = NO;
    _separator.backgroundColor = self.tintColor;
    [self addSubview:_separator];
    
    if (!_layoutMarginsDidChange)
    {
        self.layoutMargins = UIEdgeInsetsZero;
    }
    
    [NSLayoutConstraint activateConstraints:@[[_separator.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
                                              [_separator.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor],
                                              [_separator.topAnchor constraintEqualToAnchor:self.layoutMarginsGuide.topAnchor],
                                              [_separator.bottomAnchor constraintEqualToAnchor:self.layoutMarginsGuide.bottomAnchor]]];
}

#pragma mark - UIView -

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(self.lineWidth, self.lineWidth);
}

- (void)tintColorDidChange
{
    self.separator.backgroundColor = self.tintColor;
}

- (void)layoutMarginsDidChange
{
    _layoutMarginsDidChange = YES;
}

#pragma mark - Getters/Setters -

- (UIColor *)tintColor
{
    // Must override tintColor accessor methods and call super.
    // Otherwise, tintColor may not work as intended 🤷‍♂️.
    return [super tintColor];
}

- (void)setTintColor:(UIColor *)tintColor
{
    [super setTintColor:tintColor];
}

- (void)setLineWidth:(CGFloat)lineWidth
{
    if (lineWidth == _lineWidth)
    {
        return;
    }
    
    _lineWidth = lineWidth;
    
    [self invalidateIntrinsicContentSize];
}

@end
