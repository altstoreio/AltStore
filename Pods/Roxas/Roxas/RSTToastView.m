//
//  RSTToastView.m
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTToastView.h"

#import "NSLayoutConstraint+Edges.h"
#import "UISpringTimingParameters+Conveniences.h"

NSNotificationName const RSTToastViewWillShowNotification = @"RSTToastViewWillShowNotification";
NSNotificationName const RSTToastViewDidShowNotification = @"RSTToastViewDidShowNotification";
NSNotificationName const RSTToastViewWillDismissNotification = @"RSTToastViewWillDismissNotification";
NSNotificationName const RSTToastViewDidDismissNotification = @"RSTToastViewDidDismissNotification";

RSTToastViewUserInfoKey const RSTToastViewUserInfoKeyPropertyAnimator = @"RSTToastViewUserInfoKeyPropertyAnimator";

static void *RSTToastViewContext = &RSTToastViewContext;

NS_ASSUME_NONNULL_BEGIN

@interface RSTToastView ()

@property (nonatomic, readwrite, getter=isShown) BOOL shown;

@property (nonatomic, readonly) UIView *dimmingView;
@property (nonatomic, readonly) UIStackView *stackView;

@property (nullable, nonatomic) NSTimer *dismissTimer;

@property (nullable, nonatomic) NSLayoutConstraint *axisConstraint;
@property (nullable, nonatomic) NSLayoutConstraint *hiddenAxisConstraint;

@property (nullable, nonatomic) NSLayoutConstraint *alignmentConstraint;

@property (nullable, nonatomic) NSLayoutConstraint *widthConstraint;
@property (nullable, nonatomic) NSLayoutConstraint *heightConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation RSTToastView
@dynamic tintColor;

- (instancetype)initWithText:(NSString *)text detailText:(NSString *)detailText
{
    self = [super initWithFrame:CGRectZero];
    if (self)
    {
        [self initialize];
        
        _textLabel.text = text;
        _detailTextLabel.text = detailText;
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

- (instancetype)initWithError:(NSError *)error
{
    self = [self initWithText:error.localizedDescription detailText:error.localizedFailureReason];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [self initWithText:@"" detailText:nil];
    return self;
}

- (void)initialize
{
    _edgeOffset = UIOffsetMake(15, 15);
    
    _dimmingView = [[UIView alloc] initWithFrame:CGRectZero];
    _dimmingView.backgroundColor = [UIColor blackColor];
    _dimmingView.alpha = 0.1;
    _dimmingView.hidden = YES;
    [self addSubview:_dimmingView pinningEdgesWithInsets:UIEdgeInsetsZero];
    
    UIFontDescriptor *detailTextLabelFontDescriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleSubheadline];
    UIFontDescriptor *textLabelFontDescriptor = [detailTextLabelFontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    
    _textLabel = [[UILabel alloc] init];
    _textLabel.font = [UIFont fontWithDescriptor:textLabelFontDescriptor size:0.0];
    _textLabel.textColor = [UIColor whiteColor];
    _textLabel.minimumScaleFactor = 0.75;
    _textLabel.numberOfLines = 0;
    [_textLabel addObserver:self forKeyPath:NSStringFromSelector(@selector(text)) options:NSKeyValueObservingOptionOld context:RSTToastViewContext];
    
    _detailTextLabel = [[UILabel alloc] init];
    _detailTextLabel.font = [UIFont fontWithDescriptor:detailTextLabelFontDescriptor size:0.0];
    _detailTextLabel.textColor = [UIColor whiteColor];
    _detailTextLabel.minimumScaleFactor = 0.75;
    _detailTextLabel.numberOfLines = 0;
    [_detailTextLabel addObserver:self forKeyPath:NSStringFromSelector(@selector(text)) options:NSKeyValueObservingOptionOld context:RSTToastViewContext];
    
    _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _activityIndicatorView.hidesWhenStopped = YES;
    
    UIStackView *labelsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[_textLabel, _detailTextLabel]];
    labelsStackView.axis = UILayoutConstraintAxisVertical;
    labelsStackView.alignment = UIStackViewAlignmentFill;
    labelsStackView.spacing = 2.0;
    
    _stackView = [[UIStackView alloc] initWithArrangedSubviews:@[_activityIndicatorView, labelsStackView]];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.userInteractionEnabled = NO;
    _stackView.axis = UILayoutConstraintAxisHorizontal;
    _stackView.alignment = UIStackViewAlignmentCenter;
    _stackView.spacing = 8.0;
    _stackView.layoutMarginsRelativeArrangement = YES;
    _stackView.insetsLayoutMarginsFromSafeArea = NO;
    [self addSubview:_stackView];
    
    _presentationEdge = RSTViewEdgeBottom;
    _alignmentEdge = RSTViewEdgeNone;
    
    // Motion Effects
    UIInterpolatingMotionEffect *xAxis = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    xAxis.minimumRelativeValue = @(-10);
    xAxis.maximumRelativeValue = @(10);
    
    UIInterpolatingMotionEffect *yAxis = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    yAxis.minimumRelativeValue = @(-10);
    yAxis.maximumRelativeValue = @(10);
    
    UIMotionEffectGroup *group = [[UIMotionEffectGroup alloc] init];
    group.motionEffects = @[xAxis, yAxis];
    [self addMotionEffect:group];
    
    self.clipsToBounds = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.layoutMargins = UIEdgeInsetsMake(5, 10, 5, 10);
    self.preservesSuperviewLayoutMargins = NO;
    self.insetsLayoutMarginsFromSafeArea = NO;
    
    // Light blue
    self.backgroundColor = [UIColor colorWithRed:61.0/255.0 green:172.0/255.0 blue:247.0/255.0 alpha:1];
    
    // Actions
    [self addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    
    // Notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toastViewWillShow:) name:RSTToastViewWillShowNotification object:nil];
}

#pragma mark - UIView -

- (CGSize)intrinsicContentSize
{
    if (self.superview != nil)
    {
        CGFloat width = CGRectGetWidth(self.superview.bounds);
        CGFloat preferredMaxLayoutWidth = width - (self.edgeOffset.horizontal * 2) - (self.layoutMargins.left + self.layoutMargins.right);
        
        self.textLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth;
        self.detailTextLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth;
    }
    
    CGSize intrinsicContentSize = [self.stackView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    return intrinsicContentSize;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGFloat cornerRadius = MIN(10, CGRectGetMidY(self.bounds));
    self.layer.cornerRadius = cornerRadius;
    
    self.textLabel.preferredMaxLayoutWidth = CGRectGetWidth(self.superview.bounds) - self.superview.safeAreaInsets.left - self.superview.safeAreaInsets.right - self.edgeOffset.horizontal * 2;
    self.detailTextLabel.preferredMaxLayoutWidth = CGRectGetWidth(self.superview.bounds) - self.superview.safeAreaInsets.left - self.superview.safeAreaInsets.right - self.edgeOffset.horizontal * 2;
    
    [self invalidateIntrinsicContentSize];
}

- (void)updateConstraints
{
    if (self.axisConstraint != nil || self.alignmentConstraint != nil)
    {
        return [super updateConstraints];
    }
    
    if (self.superview == nil)
    {
        return [super updateConstraints];
    }
    
    // Axis Constraints
    switch (self.presentationEdge)
    {
        case RSTViewEdgeLeft:
            self.axisConstraint = [self.leftAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.leftAnchor constant:self.edgeOffset.horizontal];
            self.hiddenAxisConstraint = [self.superview.leftAnchor constraintEqualToAnchor:self.rightAnchor];
            break;
            
        case RSTViewEdgeRight:
            self.axisConstraint = [self.superview.safeAreaLayoutGuide.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:self.edgeOffset.horizontal];
            self.hiddenAxisConstraint = [self.leftAnchor constraintEqualToAnchor:self.superview.rightAnchor];
            break;
            
        case RSTViewEdgeTop:
            self.axisConstraint = [self.topAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.topAnchor constant:self.edgeOffset.vertical];
            self.hiddenAxisConstraint = [self.superview.topAnchor constraintEqualToAnchor:self.bottomAnchor];
            break;
            
        case RSTViewEdgeBottom:
        case RSTViewEdgeNone:
            self.axisConstraint = [self.superview.safeAreaLayoutGuide.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:self.edgeOffset.vertical];
            self.hiddenAxisConstraint = [self.topAnchor constraintEqualToAnchor:self.superview.bottomAnchor];
            break;
    }
    
    // Alignment Constraints
    switch (self.presentationEdge)
    {
        case RSTViewEdgeLeft:
        case RSTViewEdgeRight:
        {
            switch (self.alignmentEdge)
            {
                case RSTViewEdgeTop:
                    self.alignmentConstraint = [self.topAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.topAnchor constant:self.edgeOffset.vertical];
                    break;
                    
                case RSTViewEdgeBottom:
                    self.alignmentConstraint = [self.superview.safeAreaLayoutGuide.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:self.edgeOffset.vertical];
                    break;
                    
                case RSTViewEdgeLeft:
                case RSTViewEdgeRight:
                case RSTViewEdgeNone:
                    self.alignmentConstraint = [self.centerYAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.centerYAnchor];
                    break;
            }
            
            break;
        }
            
        case RSTViewEdgeTop:
        case RSTViewEdgeBottom:
        case RSTViewEdgeNone:
        {
            switch (self.alignmentEdge)
            {
                case RSTViewEdgeLeft:
                    self.alignmentConstraint = [self.leftAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.leftAnchor constant:self.edgeOffset.horizontal];
                    break;
                    
                case RSTViewEdgeRight:
                    self.alignmentConstraint = [self.superview.safeAreaLayoutGuide.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:self.edgeOffset.horizontal];
                    break;
                    
                case RSTViewEdgeTop:
                case RSTViewEdgeBottom:
                case RSTViewEdgeNone:
                    self.alignmentConstraint = [self.centerXAnchor constraintEqualToAnchor:self.superview.safeAreaLayoutGuide.centerXAnchor];
                    break;
            }
            
            break;
        }
    }
    
    self.widthConstraint = [self.widthAnchor constraintLessThanOrEqualToAnchor:self.superview.safeAreaLayoutGuide.widthAnchor constant:-(self.edgeOffset.horizontal * 2)];
    self.heightConstraint = [self.heightAnchor constraintLessThanOrEqualToAnchor:self.superview.safeAreaLayoutGuide.heightAnchor constant:-(self.edgeOffset.vertical * 2)];
    
    [NSLayoutConstraint activateConstraints:@[self.hiddenAxisConstraint, self.alignmentConstraint, self.widthConstraint, self.heightConstraint]];
    
    [super updateConstraints];
}

- (void)tintColorDidChange
{
    [super tintColorDidChange];
    
    self.backgroundColor = self.tintColor;
}

#pragma mark - Showing/Dismissing -

- (void)showInView:(UIView *)view
{
    [self showInView:view duration:0];
}

- (void)showInView:(UIView *)view duration:(NSTimeInterval)duration
{
    [self.dismissTimer invalidate];
    
    if (duration > 0)
    {
        self.dismissTimer = [NSTimer scheduledTimerWithTimeInterval:duration target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
    }
    else
    {
        self.dismissTimer = nil;
    }
    
    if ([self isShown])
    {
        return;
    }
    
    self.shown = YES;
    
    // Set to a large value to ensure labels don't prematurely wrap content.
    // self.widthConstraint will ensure labels wrap to stay within superview safe area inset by self.edgeOffset.
    self.textLabel.preferredMaxLayoutWidth = CGRectGetWidth(view.bounds);
    self.detailTextLabel.preferredMaxLayoutWidth = CGRectGetWidth(view.bounds);
    
    [view addSubview:self];
    [view layoutIfNeeded];
    
    self.hiddenAxisConstraint.active = NO;
    self.axisConstraint.active = YES;
    
    CGFloat distance = 0;
    CGFloat overshoot = 10;
    
    switch (self.presentationEdge)
    {
        case RSTViewEdgeLeft:
            distance = CGRectGetWidth(self.bounds) + self.edgeOffset.horizontal + self.superview.safeAreaInsets.left;
            break;
            
        case RSTViewEdgeRight:
            distance = CGRectGetWidth(self.bounds) + self.edgeOffset.horizontal + self.superview.safeAreaInsets.right;
            break;
            
        case RSTViewEdgeTop:
            distance = CGRectGetHeight(self.bounds) + self.edgeOffset.vertical + self.superview.safeAreaInsets.top;
            break;
            
        case RSTViewEdgeBottom:
        case RSTViewEdgeNone:
            distance = CGRectGetHeight(self.bounds) + self.edgeOffset.vertical + self.superview.safeAreaInsets.bottom;
            break;
    }
    
    CGFloat percentOvershoot = overshoot / distance;
    CGFloat dampingRatio = -log(percentOvershoot) / sqrt( pow(M_PI, 2) + pow(log(percentOvershoot), 2) );
    
    UISpringTimingParameters *timingParameters = [[UISpringTimingParameters alloc] initWithStiffness:RSTSpringStiffnessDefault dampingRatio:dampingRatio];
    
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithSpringTimingParameters:timingParameters animations:^{
        [view layoutIfNeeded];
    }];
    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RSTToastViewDidShowNotification object:self];
    }];
    [animator startAnimation];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:RSTToastViewWillShowNotification object:self userInfo:@{RSTToastViewUserInfoKeyPropertyAnimator: animator}];
}

- (void)dismiss
{
    if (![self isShown])
    {
        return;
    }
    
    // Set to NO immediately to prevent potential concurrent dismissals.
    self.shown = NO;
    
    if (self.superview != nil)
    {
        self.axisConstraint.active = NO;
        self.hiddenAxisConstraint.active = YES;
    }
    
    UISpringTimingParameters *timingParameters = [[UISpringTimingParameters alloc] initWithStiffness:RSTSpringStiffnessDefault dampingRatio:1.0];
    
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithSpringTimingParameters:timingParameters animations:^{
        [self.superview layoutIfNeeded];
    }];
    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        if (finalPosition != UIViewAnimatingPositionEnd)
        {
            return;
        }
        
        [self removeFromSuperview];
        
        self.axisConstraint = nil;
        self.hiddenAxisConstraint = nil;
        self.alignmentConstraint = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:RSTToastViewDidDismissNotification object:self];
    }];
    [animator startAnimation];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:RSTToastViewWillDismissNotification object:self userInfo:@{RSTToastViewUserInfoKeyPropertyAnimator: animator}];
}

#pragma mark - KVO -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context != RSTToastViewContext)
    {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    [self invalidateIntrinsicContentSize];
    
    UILabel *label = (UILabel *)object;
    NSString *previousText = change[NSKeyValueChangeOldKey];
    
    if (self.superview != nil)
    {
        CGFloat initialAlpha = 1.0;
        CGFloat finalAlpha = 1.0;
        
        if (previousText.length == 0 && label.text.length != 0)
        {
            initialAlpha = 0.0;
            finalAlpha = 1.0;
        }
        else if (previousText.length != 0 && label.text.length == 0)
        {
            initialAlpha = 1.0;
            finalAlpha = 0.0;
        }
        
        label.alpha = initialAlpha;
        
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithSpringTimingParameters:[UISpringTimingParameters new] animations:^{
            label.alpha = finalAlpha;
            [self.superview layoutIfNeeded];
        }];
        [animator startAnimation];
    }
}

#pragma mark - Notifications -

- (void)toastViewWillShow:(NSNotification *)notification
{
    RSTToastView *toastView = notification.object;
    
    if (toastView == self)
    {
        return;
    }
    
    if (toastView.presentationEdge != self.presentationEdge)
    {
        return;
    }
    
    [self dismiss];
}

#pragma mark - Getters/Setters -

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    
    self.dimmingView.hidden = !highlighted;
}

- (void)setPresentationEdge:(RSTViewEdge)presentationEdge
{
    if (presentationEdge == RSTViewEdgeNone)
    {
        presentationEdge = RSTViewEdgeBottom;
    }
    
    _presentationEdge = presentationEdge;
}

- (void)setLayoutMargins:(UIEdgeInsets)layoutMargins
{
    [super setLayoutMargins:layoutMargins];
    
    // For some reason, setting stackView.preservesSuperviewLayoutMargins to YES might result
    // in some insets becoming zero when re-laying out (such as after updating label text).
    // We compensate by overriding setLayoutMargins: and manually updating stackView's margins.
    self.stackView.layoutMargins = layoutMargins;
}

@end
