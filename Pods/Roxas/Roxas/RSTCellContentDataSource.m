//
//  RSTCellContentDataSource.m
//  Roxas
//
//  Created by Riley Testut on 2/7/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCellContentDataSource_Subclasses.h"
#import "RSTSearchController.h"
#import "RSTOperationQueue.h"
#import "RSTBlockOperation.h"

#import "RSTHelperFile.h"

@import ObjectiveC.runtime;

typedef void (^PrefetchCompletionHandler)(_Nullable id prefetchItem, NSError *_Nullable error);

NSString *RSTCellContentGenericCellIdentifier = @"Cell";

NS_ASSUME_NONNULL_BEGIN

@interface RSTCellContentDataSource ()

@property (nonatomic, getter=isPlaceholderViewVisible) BOOL placeholderViewVisible;

@property (nonatomic, readonly) RSTOperationQueue *prefetchOperationQueue;

@property (nonatomic, readonly) NSMapTable<id, NSMutableDictionary<NSIndexPath *, PrefetchCompletionHandler> *> *prefetchCompletionHandlers;

@end

NS_ASSUME_NONNULL_END


@implementation RSTCellContentDataSource
{
    UITableViewCellSeparatorStyle _previousSeparatorStyle;
    UIView *_previousBackgroundView;
    BOOL _previousScrollEnabled;
    
    NSInteger _sectionsCount;
    NSInteger _itemsCount;
}
@synthesize searchController = _searchController;
@synthesize prefetchItemCache = _prefetchItemCache;
@synthesize prefetchHandler = _prefetchHandler;
@synthesize prefetchCompletionHandler = _prefetchCompletionHandler;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _cellIdentifierHandler = [^NSString *(NSIndexPath *indexPath) {
            return RSTCellContentGenericCellIdentifier;
        } copy];
        
        _cellConfigurationHandler = [^(id cell, id item, NSIndexPath *indexPath) {
            if ([cell isKindOfClass:[UITableViewCell class]])
            {
                [(UITableViewCell *)cell textLabel].text = [item description];
            }
        } copy];
        
        __weak RSTCellContentDataSource *weakSelf = self;
        _defaultSearchHandler = [^NSOperation *(RSTSearchValue *searchValue, RSTSearchValue *previousSearchValue) {
            weakSelf.predicate = searchValue.predicate;
            return nil;
        } copy];
        
        _rowAnimation = UITableViewRowAnimationAutomatic;
        
        _prefetchItemCache = [[NSCache alloc] init];
        
        _prefetchOperationQueue = [[RSTOperationQueue alloc] init];
        _prefetchOperationQueue.name = @"com.rileytestut.Roxas.RSTCellContentDataSource.prefetchOperationQueue";
        _prefetchOperationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        
        _prefetchCompletionHandlers = [NSMapTable strongToStrongObjectsMapTable];
    }
    
    return self;
}

#pragma mark - NSObject -

- (BOOL)dataSourceProtocolContainsSelector:(SEL)aSelector
{
    Protocol *dataSourceProtocol = self.contentView.dataSourceProtocol;
    if (dataSourceProtocol == nil)
    {
        return NO;
    }
    
    struct objc_method_description dataSourceSelector = protocol_getMethodDescription(dataSourceProtocol, aSelector, NO, YES);
    
    BOOL containsSelector = (dataSourceSelector.name != NULL);
    return containsSelector;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if ([super respondsToSelector:aSelector])
    {
        return YES;
    }
    
    if ([self dataSourceProtocolContainsSelector:aSelector])
    {
        return [self.proxy respondsToSelector:aSelector];
    }
    
    return NO;
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
    if ([self dataSourceProtocolContainsSelector:aSelector])
    {
        return self.proxy;
    }
    
    return nil;
}

#pragma mark - RSTCellContentDataSource -

#pragma mark Placeholder View

- (void)showPlaceholderView
{
    if ([self isPlaceholderViewVisible])
    {
        return;
    }
    
    if (self.placeholderView == nil || self.contentView == nil)
    {
        return;
    }
    
    self.placeholderViewVisible = YES;
    
    if ([self.contentView isKindOfClass:[UITableView class]])
    {
        UITableView *tableView = (UITableView *)self.contentView;
        
        _previousSeparatorStyle = tableView.separatorStyle;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    
    _previousScrollEnabled = self.contentView.scrollEnabled;
    self.contentView.scrollEnabled = NO;
    
    _previousBackgroundView = self.contentView.backgroundView;
    self.contentView.backgroundView = self.placeholderView;
    
}

- (void)hidePlaceholderView
{
    if (![self isPlaceholderViewVisible])
    {
        return;
    }
    
    self.placeholderViewVisible = NO;
    
    if ([self.contentView isKindOfClass:[UITableView class]])
    {
        UITableView *tableView = (UITableView *)self.contentView;
        tableView.separatorStyle = _previousSeparatorStyle;
    }
    
    self.contentView.scrollEnabled = _previousScrollEnabled;
    self.contentView.backgroundView = _previousBackgroundView;
}

#pragma mark Prefetching

- (void)prefetchItemAtIndexPath:(NSIndexPath *)indexPath completionHandler:(void (^_Nullable)(id prefetchItem, NSError *error))completionHandler
{
    if (self.prefetchHandler == nil || self.prefetchCompletionHandler == nil)
    {
        return;
    }
    
    id item = [self itemAtIndexPath:indexPath];
    
    // Disable prefetching for NSProxy items to prevent obscure crashes.
    if ([item isProxy])
    {
        return;
    }
    
    if (completionHandler)
    {
        // Each completionHandler is mapped to an item, and then to the indexPath originally requested.
        // This allows us to prevent multiple fetches for the same item, but also handle the case where the prefetch item is needed by multiple cells, or the cell has moved.
        
        NSMutableDictionary<NSIndexPath *, PrefetchCompletionHandler> *completionHandlers = [self.prefetchCompletionHandlers objectForKey:item];
        if (completionHandlers == nil)
        {
            completionHandlers = [NSMutableDictionary dictionary];
            [self.prefetchCompletionHandlers setObject:completionHandlers forKey:item];
        }
        
        completionHandlers[indexPath] = completionHandler;
    }
    
    // If prefetch operation is currently in progress, return.
    if (self.prefetchOperationQueue[item] != nil)
    {
        return;
    }
    
    void (^prefetchCompletionHandler)(id, NSError *) = ^(id prefetchItem, NSError *error) {
        if (prefetchItem)
        {
            [self.prefetchItemCache setObject:prefetchItem forKey:item];
        }
        
        NSMutableDictionary<NSIndexPath *, PrefetchCompletionHandler> *completionHandlers = [self.prefetchCompletionHandlers objectForKey:item];
        [completionHandlers enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *indexPath, PrefetchCompletionHandler completionHandler, BOOL *stop) {
            completionHandler(prefetchItem, error);
        }];
        [self.prefetchCompletionHandlers removeObjectForKey:item];
    };
    
    id cachedItem = [self.prefetchItemCache objectForKey:item];
    if (cachedItem)
    {
        // Prefetch item has been cached, so use it immediately.
        
        rst_dispatch_sync_on_main_thread(^{
            prefetchCompletionHandler(cachedItem, nil);
        });
    }
    else
    {
        // Prefetch item has not been cached, so perform operation to retrieve it.
        
        __weak __block NSOperation *weakOperation = nil;
        
        NSOperation *operation = self.prefetchHandler(item, indexPath, ^(id prefetchItem, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (![weakOperation isCancelled])
                {
                    prefetchCompletionHandler(prefetchItem, error);
                }
                
                if ([weakOperation isKindOfClass:[RSTAsyncBlockOperation class]])
                {
                    // Automatically call finish for RSTAsyncBlockOperations.
                    [(RSTAsyncBlockOperation *)weakOperation finish];
                }
            });
        });
        
        weakOperation = operation;
        
        if (operation)
        {
            [self.prefetchOperationQueue addOperation:operation forKey:item];
        }
    }
}

#pragma mark Validation

- (BOOL)isValidIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section >= [self numberOfSectionsInContentView:self.contentView])
    {
        return NO;
    }
    
    if (indexPath.item >= [self contentView:self.contentView numberOfItemsInSection:indexPath.section])
    {
        return NO;
    }
    
    return YES;
}

#pragma mark Filtering

- (void)filterContentWithPredicate:(NSPredicate *)predicate refreshContent:(BOOL)refreshContent
{
    [self filterContentWithPredicate:predicate];
    
    if (refreshContent)
    {
        rst_dispatch_sync_on_main_thread(^{
            [self.contentView reloadData];
        });
    }
}

#pragma mark Changes

- (void)addChange:(RSTCellContentChange *)change
{
    RSTCellContentChange *transformedChange = nil;
    
    if (change.sectionIndex == RSTUnknownSectionIndex)
    {
        NSIndexPath *currentIndexPath = change.currentIndexPath;
        if (currentIndexPath != nil)
        {
            currentIndexPath = [self.indexPathTranslator dataSource:self globalIndexPathForLocalIndexPath:currentIndexPath] ?: currentIndexPath;
        }
        
        NSIndexPath *destinationIndexPath = change.destinationIndexPath;
        if (destinationIndexPath != nil)
        {
            destinationIndexPath = [self.indexPathTranslator dataSource:self globalIndexPathForLocalIndexPath:destinationIndexPath] ?: destinationIndexPath;
        }
        
        transformedChange = [[RSTCellContentChange alloc] initWithType:change.type currentIndexPath:currentIndexPath destinationIndexPath:destinationIndexPath];
        
        NSIndexPath *indexPathForRemovingFromCache = nil;
        switch (change.type)
        {
            case RSTCellContentChangeUpdate:
                indexPathForRemovingFromCache = change.currentIndexPath;
                break;
                
            case RSTCellContentChangeMove:
                // At this point, the data source has already changed index paths of objects.
                // So to remove the old cached item, we need to get the item at the _new_ index path.
                indexPathForRemovingFromCache = change.destinationIndexPath;
                break;
                
            case RSTCellContentChangeDelete:
            case RSTCellContentChangeInsert:
                break;
        }
        
        if (indexPathForRemovingFromCache != nil)
        {
            // Remove cached prefetched item since the object has been changed.
            id item = [self itemAtIndexPath:indexPathForRemovingFromCache];
            [self.prefetchItemCache removeObjectForKey:item];
        }
    }
    else
    {
        NSIndexPath *sectionIndexPath = [NSIndexPath indexPathForItem:0 inSection:change.sectionIndex];
        NSIndexPath *indexPath = [self.indexPathTranslator dataSource:self globalIndexPathForLocalIndexPath:sectionIndexPath] ?: sectionIndexPath;
        
        transformedChange = [[RSTCellContentChange alloc] initWithType:change.type sectionIndex:indexPath.section];
    }
    
    [self.contentView addChange:transformedChange];
}

#pragma mark - RSTCellContentDataSource Subclass Methods -

- (NSInteger)numberOfSectionsInContentView:(__kindof UIView *)contentView
{
    [self doesNotRecognizeSelector:_cmd];
    return 0;
}

- (NSInteger)contentView:(__kindof UIView *)contentView numberOfItemsInSection:(NSInteger)section
{
    [self doesNotRecognizeSelector:_cmd];
    return 0;
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)filterContentWithPredicate:(NSPredicate *)predicate
{
    [self doesNotRecognizeSelector:_cmd];
}

#pragma mark - Data Source -

- (NSInteger)_numberOfSectionsInContentView:(UIScrollView<RSTCellContentView> *)contentView
{
    self.contentView = contentView;
    
    NSInteger sections = [self numberOfSectionsInContentView:contentView];
    
    if (sections == 0)
    {
        [self showPlaceholderView];
    }
    
    _itemsCount = 0;
    _sectionsCount = sections;
    
    return sections;
}

- (NSInteger)_contentView:(UIScrollView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section
{
    NSInteger items = [self contentView:contentView numberOfItemsInSection:section];
    _itemsCount += items;
    
    if (section == _sectionsCount - 1)
    {
        if (_itemsCount == 0)
        {
            [self showPlaceholderView];
        }
        else
        {
            [self hidePlaceholderView];
        }
        
        _itemsCount = 0;
        _sectionsCount = 0;
    }
    
    return items;
}

- (__kindof UIView<RSTCellContentCell> *)_contentView:(UIScrollView<RSTCellContentView> *)contentView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = self.cellIdentifierHandler(indexPath);
    id item = [self itemAtIndexPath:indexPath];
    
    id cell = [contentView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    self.cellConfigurationHandler(cell, item, indexPath);
    
    // We store the completionHandler, and it's not guaranteed to be nil'd out (since prefetch may take a long time), so we use a weak reference to self inside the block to prevent strong reference cycle.
    RSTCellContentDataSource *__weak weakSelf = self;
    [self prefetchItemAtIndexPath:indexPath completionHandler:^(id prefetchItem, NSError *error) {
        NSIndexPath *cellIndexPath = [contentView indexPathForCell:cell];
        
        if (cellIndexPath)
        {
            id cellItem = [weakSelf itemAtIndexPath:cellIndexPath];
            if ([item isEqual:cellItem])
            {
                // Cell is in use, but its current index path still corresponds to the same item, so update.
                weakSelf.prefetchCompletionHandler(cell, prefetchItem, cellIndexPath, error);
            }
            else
            {
                // Cell is in use, but its new index path does *not* correspond to the same item, so ignore.
            }
        }
        else
        {
            // Cell is currently being configured for use, so update.
            weakSelf.prefetchCompletionHandler(cell, prefetchItem, indexPath, error);
        }
    }];
    
    return cell;
}

#pragma mark Prefetching

- (void)_contentView:(UIScrollView<RSTCellContentView> *)contentView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    for (NSIndexPath *indexPath in indexPaths)
    {
        if (![self isValidIndexPath:indexPath])
        {
            continue;
        }
        
        [self prefetchItemAtIndexPath:indexPath completionHandler:nil];
    }
}

- (void)_contentView:(UIScrollView<RSTCellContentView> *)contentView cancelPrefetchingItemsForIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    for (NSIndexPath *indexPath in indexPaths)
    {
        if (![self isValidIndexPath:indexPath])
        {
            continue;
        }
        
        id item = [self itemAtIndexPath:indexPath];
        
        NSOperation *operation = self.prefetchOperationQueue[item];
        [operation cancel];
    }
}

#pragma mark - <UITableViewDataSource> -

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self _numberOfSectionsInContentView:tableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self _contentView:tableView numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self _contentView:tableView cellForItemAtIndexPath:indexPath];
}

#pragma mark - <UITableViewDataSourcePrefetching> -

- (void)tableView:(UITableView *)tableView prefetchRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self _contentView:tableView prefetchItemsAtIndexPaths:indexPaths];
}

- (void)tableView:(UITableView *)tableView cancelPrefetchingForRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self _contentView:tableView cancelPrefetchingItemsForIndexPaths:indexPaths];
}

#pragma mark - <UICollectionViewDataSource> -

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return [self _numberOfSectionsInContentView:collectionView];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self _contentView:collectionView numberOfItemsInSection:section];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self _contentView:collectionView cellForItemAtIndexPath:indexPath];
}

#pragma mark - <UICollectionViewDataSourcePrefetching> -

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self _contentView:collectionView prefetchItemsAtIndexPaths:indexPaths];
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self _contentView:collectionView cancelPrefetchingItemsForIndexPaths:indexPaths];
}

#pragma mark - Getters/Setters -

- (RSTSearchController *)searchController
{
    if (_searchController == nil)
    {
        _searchController = [[RSTSearchController alloc] initWithSearchResultsController:nil];
        
        __weak RSTCellContentDataSource *weakSelf = self;
        _searchController.searchHandler = ^NSOperation *(RSTSearchValue *searchValue, RSTSearchValue *previousSearchValue) {
            weakSelf.predicate = searchValue.predicate;
            return nil;
        };
    }
    
    return _searchController;
}

- (void)setContentView:(UIScrollView<RSTCellContentView> *)contentView
{
    if (contentView == _contentView)
    {
        return;
    }
    
    _contentView = contentView;
    
    if (contentView.dataSource == self)
    {
        // Must set ourselves as dataSource again to refresh respondsToSelector: cache.
        contentView.dataSource = nil;
        contentView.dataSource = self;
    }
    
    if (self.contentView != nil)
    {
        if ([self isPrefetchingDataSource])
        {
            if (self.contentView.prefetchDataSource == nil)
            {
                NSLog(@"%@ is a prefetching data source, but its content view's prefetchDataSource is nil. Did you forget to assign it?", self);
            }
        }
    }
}

- (void)setPredicate:(NSPredicate *)predicate
{
    [self setPredicate:predicate refreshContent:YES];
}

- (void)setPredicate:(NSPredicate *)predicate refreshContent:(BOOL)refreshContent
{
    _predicate = predicate;
    
    [self filterContentWithPredicate:_predicate refreshContent:refreshContent];
}

- (void)setPlaceholderView:(UIView *)placeholderView
{
    if (_placeholderView != nil && self.contentView.backgroundView == _placeholderView)
    {
        self.contentView.backgroundView = placeholderView;
    }
    
    _placeholderView = placeholderView;
    _placeholderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    if (self.contentView)
    {
        // Show placeholder only if there are no items to display.
        
        BOOL shouldShowPlaceholderView = YES;
        
        for (int i = 0; i < [self numberOfSectionsInContentView:self.contentView]; i++)
        {
            if ([self contentView:self.contentView numberOfItemsInSection:i] > 0)
            {
                shouldShowPlaceholderView = NO;
                break;
            }
        }
        
        if (shouldShowPlaceholderView)
        {
            [self showPlaceholderView];
        }
        else
        {
            [self hidePlaceholderView];
        }
    }
}

- (NSInteger)itemCount
{
    NSInteger itemCount = 0;
    
    for (int section = 0; section < [self numberOfSectionsInContentView:self.contentView]; section++)
    {
        for (int item = 0; item < [self contentView:self.contentView numberOfItemsInSection:section]; item++)
        {
            itemCount++;
        }
    }
    
    return itemCount;
}

- (BOOL)isPrefetchingDataSource
{
    return NO;
}

@end
