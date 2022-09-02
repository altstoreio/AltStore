//
//  RSTCollectionViewGridLayout.m
//  Roxas
//
//  Created by Riley Testut on 5/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTCollectionViewGridLayout.h"

@implementation RSTCollectionViewGridLayoutAttributes

- (id)copyWithZone:(NSZone *)zone
{
    RSTCollectionViewGridLayoutAttributes *copy = [super copyWithZone:zone];
    copy.preferredItemSize = self.preferredItemSize;
    return copy;
}

@end

@interface RSTCollectionViewGridLayout ()

@property (nonatomic, readonly) CGFloat contentWidth;
@property (nonatomic, readonly) NSUInteger maximumItemsPerRow;
@property (nonatomic, readonly) CGFloat interitemSpacing;

@property (nonatomic, readonly) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *cachedLayoutAttributes;
@property (nonatomic, readonly) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *initialLayoutAttributes;

@end

@implementation RSTCollectionViewGridLayout

+ (Class)layoutAttributesClass
{
    return [RSTCollectionViewGridLayoutAttributes class];
}

- (instancetype)init
{
    self = [super init];
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
    _distribution = RSTCollectionViewGridLayoutDistributionFlow;
    _automaticallyAdjustsSectionInsets = YES;
    
    _cachedLayoutAttributes = [NSMutableDictionary dictionary];
    _initialLayoutAttributes = [NSMutableDictionary dictionary];
    
    if (@available(iOS 11.0, *))
    {
        self.sectionInsetReference = UICollectionViewFlowLayoutSectionInsetFromSafeArea;
    }

    self.estimatedItemSize = self.itemSize;
}

#pragma mark - Preparations -

- (void)prepareLayout
{
    [super prepareLayout];
    
    if (self.automaticallyAdjustsSectionInsets)
    {
        UIEdgeInsets inset = self.sectionInset;
        inset.left = self.interitemSpacing;
        inset.right = self.interitemSpacing;
        self.sectionInset = inset;
    }
}

- (void)finalizeCollectionViewUpdates
{
    [super finalizeCollectionViewUpdates];
    
    [self.initialLayoutAttributes removeAllObjects];
}

#pragma mark - Invalidation -

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForPreferredLayoutAttributes:(UICollectionViewLayoutAttributes *)preferredAttributes withOriginalAttributes:(UICollectionViewLayoutAttributes *)originalAttributes
{
    UICollectionViewLayoutInvalidationContext *context = [super invalidationContextForPreferredLayoutAttributes:preferredAttributes withOriginalAttributes:originalAttributes];
    
    // Update the initial attributes because the size may have changed since returning from initialLayoutAttributesForAppearingItemAtIndexPath.
    UICollectionViewLayoutAttributes *initialAttributes = self.initialLayoutAttributes[preferredAttributes.indexPath];
    if (initialAttributes != nil)
    {
        CGRect rect = CGRectMake(0, 0, self.collectionViewContentSize.width, self.collectionViewContentSize.height);

        // Must call layoutAttributesForElementsInRect for the layout to recalculate the correct frames.
        NSArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [self layoutAttributesForElementsInRect:rect];
        for (UICollectionViewLayoutAttributes *attributes in layoutAttributes)
        {
            if ([attributes.indexPath isEqual:initialAttributes.indexPath])
            {
                initialAttributes.frame = attributes.frame;
                break;
            }
        }
    }
    
    return context;
}

#pragma mark - Returning Layout Attributes -

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes *attributes = self.cachedLayoutAttributes[indexPath];
    if (attributes != nil)
    {
        return attributes;
    }
    
    return [super layoutAttributesForItemAtIndexPath:indexPath];
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [NSMutableArray array];
    
    for (UICollectionViewLayoutAttributes *attributes in [super layoutAttributesForElementsInRect:rect])
    {
        UICollectionViewLayoutAttributes *updatedAttributes = [self transformedLayoutAttributesFromLayoutAttributes:attributes];
        [layoutAttributes addObject:updatedAttributes];
    }
    
    [self alignLayoutAttributes:layoutAttributes];
    
    for (UICollectionViewLayoutAttributes *attributes in layoutAttributes)
    {
        // Cache layout attributes to ensure layoutAttributesForItemAtIndexPath returns correct attributes.
        self.cachedLayoutAttributes[attributes.indexPath] = attributes;
    }
    
    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath *)itemIndexPath
{
    UICollectionViewLayoutAttributes *attributes = [[super initialLayoutAttributesForAppearingItemAtIndexPath:itemIndexPath] copy];
    self.initialLayoutAttributes[itemIndexPath] = attributes;
    return attributes;
}

#pragma mark - Transforming Layout Attributes -

- (UICollectionViewLayoutAttributes *)transformedLayoutAttributesFromLayoutAttributes:(UICollectionViewLayoutAttributes *)attributes
{
    RSTCollectionViewGridLayoutAttributes *transformedLayoutAttributes = [attributes copy];
    transformedLayoutAttributes.preferredItemSize = self.itemSize;
    
    if (attributes.representedElementCategory == UICollectionElementCategoryCell)
    {
        if (attributes.indexPath.item == 0)
        {
            // When using self-sizing cells, a bug in UICollectionViewFlowLayout causes cells in sections with only one (currently visible) item to be centered horizontally.
            // To compensate, we manually set the correct horizontal offset.
            
            CGRect frame = transformedLayoutAttributes.frame;
            frame.origin.x = self.sectionInset.left;
            transformedLayoutAttributes.frame = frame;
        }
    }

    return transformedLayoutAttributes;
}

- (void)alignLayoutAttributes:(NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributes
{
    NSNumber *minimumY = nil;
    NSNumber *maximumY = nil;
    
    NSMutableArray<UICollectionViewLayoutAttributes *> *currentRowLayoutAttributes = [NSMutableArray array];
    
    BOOL isSingleRow = YES;
    
    for (UICollectionViewLayoutAttributes *attributes in layoutAttributes)
    {
        if (attributes.representedElementCategory != UICollectionElementCategoryCell)
        {
            continue;
        }
        
        if (minimumY != nil && maximumY != nil)
        {
            if (CGRectGetMinY(attributes.frame) > [maximumY doubleValue])
            {
                // attributes.frame.minY is greater than maximumY, so this is a new row.
                // As a result, we need to align all current row frame origins to the same Y-value (minimumY).
                [self alignLayoutAttributes:currentRowLayoutAttributes toOriginY:[minimumY doubleValue]];
                
                // Reset variables for new row.
                [currentRowLayoutAttributes removeAllObjects];
                minimumY = nil;
                maximumY = nil;
                
                isSingleRow = NO;
            }
        }
        
        // Update minimumY if needed.
        if (minimumY == nil || CGRectGetMinY(attributes.frame) < [minimumY doubleValue])
        {
            minimumY = @(CGRectGetMinY(attributes.frame));
        }
        
        // Update maximumY if needed.
        if (maximumY == nil || CGRectGetMaxY(attributes.frame) > [maximumY doubleValue])
        {
            maximumY = @(CGRectGetMaxY(attributes.frame));
        }
        
        [currentRowLayoutAttributes addObject:attributes];
    }
    
    // Handle remaining currentRowLayoutAttributes.
    if (minimumY != nil)
    {
        [self alignLayoutAttributes:currentRowLayoutAttributes toOriginY:[minimumY doubleValue]];
        
        if (isSingleRow && self.distribution == RSTCollectionViewGridLayoutDistributionFill)
        {
            CGFloat spacing = (self.contentWidth - (self.itemSize.width * currentRowLayoutAttributes.count)) / (currentRowLayoutAttributes.count + 1.0);
            
            [currentRowLayoutAttributes enumerateObjectsUsingBlock:^(UICollectionViewLayoutAttributes * _Nonnull attributes, NSUInteger index, BOOL * _Nonnull stop) {
                CGRect frame = attributes.frame;
                frame.origin.x = spacing + (spacing + self.itemSize.width) * index;
                attributes.frame = frame;
            }];
        }
    }
}

- (void)alignLayoutAttributes:(NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributes toOriginY:(CGFloat)originY
{
    for (UICollectionViewLayoutAttributes *attributes in layoutAttributes)
    {
        CGRect frame = attributes.frame;
        frame.origin.y = originY;
        attributes.frame = frame;
    }
}

#pragma mark - Getters/Setters -

- (CGFloat)contentWidth
{
    if (self.collectionView == nil)
    {
        return 0.0;
    }

    CGFloat contentWidth = CGRectGetWidth(self.collectionView.bounds);

    if (!self.automaticallyAdjustsSectionInsets)
    {
        UIEdgeInsets insets = self.collectionView.contentInset;
        if (@available(iOS 11, *))
        {
            insets = self.collectionView.adjustedContentInset;
        }

        contentWidth -= (insets.left + insets.right);
    }

    return contentWidth;
}

- (NSUInteger)maximumItemsPerRow
{
    NSUInteger maximumItemsPerRow = (self.contentWidth - self.minimumInteritemSpacing) / (self.itemSize.width + self.minimumInteritemSpacing);
    return maximumItemsPerRow;
}

- (CGFloat)interitemSpacing
{
    CGFloat interitemSpacing = (self.contentWidth - self.maximumItemsPerRow * self.itemSize.width) / (self.maximumItemsPerRow + 1.0);
    return interitemSpacing;
}

- (void)setDistribution:(RSTCollectionViewGridLayoutDistribution)distribution
{
    _distribution = distribution;
    
    [self invalidateLayout];
}

- (void)setAutomaticallyAdjustsSectionInsets:(BOOL)automaticallyAdjustsSectionInsets
{
    _automaticallyAdjustsSectionInsets = automaticallyAdjustsSectionInsets;
    
    [self invalidateLayout];
}

- (void)setItemSize:(CGSize)itemSize
{
    [super setItemSize:itemSize];
    
    self.estimatedItemSize = itemSize;
    
    [self invalidateLayout];
}

@end
