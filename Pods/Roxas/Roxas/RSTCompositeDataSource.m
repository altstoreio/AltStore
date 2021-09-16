//
//  RSTCompositeDataSource.m
//  Roxas
//
//  Created by Riley Testut on 12/19/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCompositeDataSource.h"
#import "RSTCellContentDataSource_Subclasses.h"

#import "RSTHelperFile.h"

// Allow NSValue-boxing literals for NSRange.
typedef struct __attribute__((objc_boxable)) _NSRange NSRange;

NS_ASSUME_NONNULL_BEGIN

@interface RSTCompositeDataSource () <RSTCellContentIndexPathTranslating>

@property (nonatomic, readonly) NSMapTable<RSTCellContentDataSource *, NSValue *> *dataSourceRanges;

@end

NS_ASSUME_NONNULL_END

@implementation RSTCompositeDataSource

- (instancetype)initWithDataSources:(NSArray *)dataSources
{
    self = [super init];
    if (self)
    {
        _dataSources = [dataSources copy];
        _dataSourceRanges = [NSMapTable strongToStrongObjectsMapTable];
        
        for (RSTCellContentDataSource *dataSource in _dataSources)
        {
            dataSource.indexPathTranslator = self;
        }
        
        __weak RSTCompositeDataSource *weakSelf = self;
        
        self.cellIdentifierHandler = ^NSString * _Nonnull(NSIndexPath *_Nonnull indexPath) {
            RSTCellContentDataSource *dataSource = [weakSelf dataSourceForIndexPath:indexPath];
            if (dataSource == nil)
            {
                return RSTCellContentGenericCellIdentifier;
            }
            
            NSIndexPath *localIndexPath = [weakSelf dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
            
            NSString *identifier = dataSource.cellIdentifierHandler(localIndexPath);
            return identifier;
        };
        
        self.cellConfigurationHandler = ^(id _Nonnull cell, id _Nonnull item, NSIndexPath *_Nonnull indexPath) {
            RSTCellContentDataSource *dataSource = [weakSelf dataSourceForIndexPath:indexPath];
            if (dataSource == nil)
            {
                return;
            }
            
            NSIndexPath *localIndexPath = [weakSelf dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
            dataSource.cellConfigurationHandler(cell, item, localIndexPath);
        };
        
        self.prefetchCompletionHandler = ^(__kindof UIView<RSTCellContentCell> * _Nonnull cell, id  _Nullable item, NSIndexPath * _Nonnull indexPath, NSError * _Nullable error) {
            RSTCellContentDataSource *dataSource = [weakSelf dataSourceForIndexPath:indexPath];
            if (dataSource == nil || dataSource.prefetchCompletionHandler == nil)
            {
                return;
            }
            
            NSIndexPath *localIndexPath = [weakSelf dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
            dataSource.prefetchCompletionHandler(cell, item, localIndexPath, error);
        };
    }
    
    return self;
}

#pragma mark - RSTCompositeDataSource -

- (RSTCellContentDataSource *)dataSourceForIndexPath:(NSIndexPath *)indexPath
{
    for (RSTCellContentDataSource *key in self.dataSourceRanges.copy)
    {
        NSRange range = [[self.dataSourceRanges objectForKey:key] rangeValue];
        
        NSInteger index = [self shouldFlattenSections] ? indexPath.item : indexPath.section;
        if (NSLocationInRange(index, range))
        {
            return key;
        }
    }
    
    return nil;
}

- (NSInteger)sectionForItem:(NSInteger)item dataSource:(RSTCellContentDataSource *)dataSource
{
    NSInteger section = 0;
    
    NSInteger itemCount = 0;
    
    for (int i = 0; i < [dataSource numberOfSectionsInContentView:self.contentView]; i++)
    {
        NSInteger count = [dataSource contentView:self.contentView numberOfItemsInSection:i];
        itemCount += count;
        
        if (itemCount > item)
        {
            section = i;
            break;
        }
    }
    
    return section;
}

#pragma mark - RSTCellContentDataSource -

- (NSInteger)numberOfSectionsInContentView:(__kindof UIView<RSTCellContentView> *)contentView
{
    if ([self shouldFlattenSections])
    {
        return 1;
    }
    
    NSInteger numberOfSections = 0;
    for (RSTCellContentDataSource *dataSource in self.dataSources)
    {
        NSInteger sections = [dataSource numberOfSectionsInContentView:contentView];
        
        NSRange range = NSMakeRange(numberOfSections, sections);
        [self.dataSourceRanges setObject:@(range) forKey:dataSource];
        
        numberOfSections += sections;
    }
    
    return numberOfSections;
}

- (NSInteger)contentView:(__kindof UIView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section
{
    if ([self shouldFlattenSections])
    {
        NSInteger itemCount = 0;
        
        for (RSTCellContentDataSource *dataSource in self.dataSources)
        {
            NSRange range = NSMakeRange(itemCount, dataSource.itemCount);
            [self.dataSourceRanges setObject:@(range) forKey:dataSource];
            
            itemCount += range.length;
        }
        
        return itemCount;
    }
    else
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:section];
        
        RSTCellContentDataSource *dataSource = [self dataSourceForIndexPath:indexPath];
        if (dataSource == nil)
        {
            return 0;
        }
        
        NSIndexPath *localIndexPath = [self dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
        
        NSInteger numberOfItems = [dataSource contentView:contentView numberOfItemsInSection:localIndexPath.section];
        return numberOfItems;
    }
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    RSTCellContentDataSource *dataSource = [self dataSourceForIndexPath:indexPath];
    if (dataSource == nil)
    {
        @throw [NSException exceptionWithName:NSRangeException reason:nil userInfo:nil];
    }
    
    NSIndexPath *localIndexPath = [self dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
    
    id item = [dataSource itemAtIndexPath:localIndexPath];
    return item;
}

- (void)prefetchItemAtIndexPath:(NSIndexPath *)indexPath completionHandler:(void (^_Nullable)(id prefetchItem, NSError *error))completionHandler
{
    if (self.prefetchHandler != nil)
    {
        return [super prefetchItemAtIndexPath:indexPath completionHandler:completionHandler];
    }
    
    RSTCellContentDataSource *dataSource = [self dataSourceForIndexPath:indexPath];
    if (dataSource == nil)
    {
        @throw [NSException exceptionWithName:NSRangeException reason:nil userInfo:nil];
    }
    
    NSIndexPath *localIndexPath = [self dataSource:dataSource localIndexPathForGlobalIndexPath:indexPath];
    [dataSource prefetchItemAtIndexPath:localIndexPath completionHandler:completionHandler];
}

- (void)filterContentWithPredicate:(nullable NSPredicate *)predicate
{
    for (RSTCellContentDataSource *dataSource in self.dataSources)
    {
        [dataSource filterContentWithPredicate:predicate];
    }
}

#pragma mark - <RSTCellContentIndexPathTranslating> -

- (nullable NSIndexPath *)dataSource:(RSTCellContentDataSource *)dataSource localIndexPathForGlobalIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSValue *rangeValue = [self.dataSourceRanges objectForKey:dataSource];
    if (rangeValue == nil)
    {
        return nil;
    }
    
    NSRange range = [rangeValue rangeValue];
    
    NSIndexPath *localIndexPath = nil;
    
    if ([self shouldFlattenSections])
    {
        NSInteger item = indexPath.item - range.location;
        NSInteger section = [self sectionForItem:item dataSource:dataSource];
        
        for (int i = 0; i < section; i++)
        {
            NSInteger count = [dataSource contentView:self.contentView numberOfItemsInSection:i];
            item -= count;
        }
        
        localIndexPath = [NSIndexPath indexPathForItem:item inSection:section];
    }
    else
    {
        localIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:indexPath.section - range.location];
    }
    
    return localIndexPath;
}

- (nullable NSIndexPath *)dataSource:(RSTCellContentDataSource *)dataSource globalIndexPathForLocalIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSValue *rangeValue = [self.dataSourceRanges objectForKey:dataSource];
    if (rangeValue == nil)
    {
        return nil;
    }
    
    NSRange range = [rangeValue rangeValue];
    
    NSIndexPath *globalIndexPath = nil;
    
    if ([self shouldFlattenSections])
    {
        NSInteger item = indexPath.item;
        
        for (int i = 0; i < indexPath.section; i++)
        {
            NSInteger count = [dataSource contentView:self.contentView numberOfItemsInSection:i];
            item += count;
        }
        
        globalIndexPath = [NSIndexPath indexPathForItem:item inSection:0];
    }
    else
    {
        globalIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:indexPath.section + range.location];
    }
    
    if (self.indexPathTranslator != nil)
    {
        globalIndexPath = [self.indexPathTranslator dataSource:self globalIndexPathForLocalIndexPath:globalIndexPath];
    }
    
    return globalIndexPath;
}

#pragma mark - Getters/Setters -

- (void)setContentView:(UIScrollView<RSTCellContentView> *)contentView
{
    [super setContentView:contentView];
    
    for (RSTCellContentDataSource *dataSource in self.dataSources)
    {
        dataSource.contentView = contentView;
    }
}

- (void)setShouldFlattenSections:(BOOL)shouldFlattenSections
{
    if (shouldFlattenSections == _shouldFlattenSections)
    {
        return;
    }
    
    _shouldFlattenSections = shouldFlattenSections;
    
    [self.contentView reloadData];
}

@end

@implementation RSTCompositeTableViewDataSource
@end

@implementation RSTCompositeCollectionViewDataSource
@end

@implementation RSTCompositePrefetchingDataSource
@dynamic prefetchItemCache;
@dynamic prefetchHandler;
@dynamic prefetchCompletionHandler;

- (BOOL)isPrefetchingDataSource
{
    return YES;
}

@end

@implementation RSTCompositeTableViewPrefetchingDataSource
@end

@implementation RSTCompositeCollectionViewPrefetchingDataSource
@end
