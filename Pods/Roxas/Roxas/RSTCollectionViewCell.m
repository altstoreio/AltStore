//
//  RSTCollectionViewCell.m
//  Roxas
//
//  Created by Riley Testut on 5/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTCollectionViewCell.h"
#import "RSTCollectionViewGridLayout.h"

#import "UICollectionViewCell+Nibs.h"
#import "NSLayoutConstraint+Edges.h"

static void *RSTCollectionViewCellKVOContext = &RSTCollectionViewCellKVOContext;

@interface RSTCollectionViewCell ()

@property (nonatomic, readwrite) IBOutlet UILabel *textLabel;
@property (nonatomic, readwrite) IBOutlet UILabel *detailTextLabel;
@property (nonatomic, readwrite) IBOutlet UIImageView *imageView;

@property (nonatomic, readwrite) IBOutlet UIStackView *stackView;

@end

@implementation RSTCollectionViewCell

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
    UINib *nib = [RSTCollectionViewCell nib];
    [nib instantiateWithOwner:self options:nil];
    
    [self.contentView addSubview:self.stackView pinningEdgesWithInsets:UIEdgeInsetsZero];
    
    [self.textLabel addObserver:self forKeyPath:NSStringFromSelector(@selector(text)) options:NSKeyValueObservingOptionNew context:RSTCollectionViewCellKVOContext];
    [self.detailTextLabel addObserver:self forKeyPath:NSStringFromSelector(@selector(text)) options:NSKeyValueObservingOptionNew context:RSTCollectionViewCellKVOContext];
    
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
}

- (void)dealloc
{
    [self.textLabel removeObserver:self forKeyPath:NSStringFromSelector(@selector(text)) context:RSTCollectionViewCellKVOContext];
    [self.detailTextLabel removeObserver:self forKeyPath:NSStringFromSelector(@selector(text)) context:RSTCollectionViewCellKVOContext];
}

#pragma mark - UIView -

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes
{
    if (![layoutAttributes isKindOfClass:[RSTCollectionViewGridLayoutAttributes class]])
    {
        return [super preferredLayoutAttributesFittingAttributes:layoutAttributes];
    }
    
    RSTCollectionViewGridLayoutAttributes *gridLayoutAttributes = (RSTCollectionViewGridLayoutAttributes *)layoutAttributes;
    
    NSArray<NSLayoutConstraint *> *constraints = @[[self.imageView.widthAnchor constraintEqualToConstant:gridLayoutAttributes.preferredItemSize.width],
                                                   [self.imageView.heightAnchor constraintEqualToConstant:gridLayoutAttributes.preferredItemSize.height]];
    
    for (NSLayoutConstraint *constraint in constraints)
    {
        // Prevent conflicting with potential UIView-Encapsulated-Layout-Height when activating constraints.
        // Still results in correct size when calling [super preferredLayoutAttributesFittingAttributes].
        constraint.priority = 999;
    }
    
    [NSLayoutConstraint activateConstraints:constraints];
    
    UICollectionViewLayoutAttributes *attributes = [super preferredLayoutAttributesFittingAttributes:layoutAttributes];
    
    [NSLayoutConstraint deactivateConstraints:constraints];
        
    return attributes;
}

#pragma mark - KVO -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context != RSTCollectionViewCellKVOContext)
    {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    UILabel *label = object;
    label.hidden = (label.text.length == 0);
}

@end
