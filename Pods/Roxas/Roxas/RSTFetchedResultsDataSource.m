//
//  RSTFetchedResultsDataSource.m
//  Roxas
//
//  Created by Riley Testut on 8/12/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTFetchedResultsDataSource.h"
#import "RSTCellContentDataSource_Subclasses.h"

#import "RSTBlockOperation.h"
#import "RSTSearchController.h"

#import "RSTHelperFile.h"

static void *RSTFetchedResultsDataSourceContext = &RSTFetchedResultsDataSourceContext;


NS_ASSUME_NONNULL_BEGIN

// Declare custom NSPredicate subclass so we can detect whether NSFetchedResultsController's predicate was changed externally or by us.
@interface RSTProxyPredicate : NSCompoundPredicate

- (instancetype)initWithPredicate:(nullable NSPredicate *)predicate externalPredicate:(nullable NSPredicate *)externalPredicate;

@end

NS_ASSUME_NONNULL_END


@implementation RSTProxyPredicate

- (instancetype)initWithPredicate:(nullable NSPredicate *)predicate externalPredicate:(nullable NSPredicate *)externalPredicate
{
    NSMutableArray *subpredicates = [NSMutableArray array];
    
    if (externalPredicate != nil)
    {
        [subpredicates addObject:externalPredicate];
    }
    
    if (predicate != nil)
    {
        [subpredicates addObject:predicate];
    }
    
    self = [super initWithType:NSAndPredicateType subpredicates:subpredicates];
    return self;
}

@end


NS_ASSUME_NONNULL_BEGIN

@interface RSTFetchedResultsDataSource ()

@property (nonatomic, copy, nullable) NSPredicate *externalPredicate;

@end

NS_ASSUME_NONNULL_END


@implementation RSTFetchedResultsDataSource

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest managedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    NSFetchedResultsController *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:managedObjectContext sectionNameKeyPath:nil cacheName:nil];
    
    self = [self initWithFetchedResultsController:fetchedResultsController];
    return self;
}

- (instancetype)initWithFetchedResultsController:(NSFetchedResultsController *)fetchedResultsController
{
    self = [super init];
    if (self)
    {
        [self setFetchedResultsController:fetchedResultsController];
        
        __weak RSTFetchedResultsDataSource *weakSelf = self;
        self.defaultSearchHandler = ^NSOperation *(RSTSearchValue *searchValue, RSTSearchValue *previousSearchValue) {
            return [RSTBlockOperation blockOperationWithExecutionBlock:^(RSTBlockOperation * _Nonnull __weak operation) {
                [weakSelf setPredicate:searchValue.predicate refreshContent:NO];
                
                // Only refresh content if search operation has not been cancelled, such as when the search text changes.
                if (operation != nil && ![operation isCancelled])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.contentView reloadData];
                    });
                }
            }];
        };
    }
    
    return self;
}

- (void)dealloc
{
    [_fetchedResultsController removeObserver:self forKeyPath:@"fetchRequest.predicate" context:RSTFetchedResultsDataSourceContext];
}

#pragma mark - RSTCellContentViewDataSource -

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    id item = [self.fetchedResultsController objectAtIndexPath:indexPath];
    return item;
}

- (NSInteger)numberOfSectionsInContentView:(__kindof UIView<RSTCellContentView> *)contentView
{
    if (self.fetchedResultsController.sections == nil)
    {
        NSError *error = nil;
        if (![self.fetchedResultsController performFetch:&error])
        {
            ELog(error);
        }
    }
    
    NSInteger numberOfSections = self.fetchedResultsController.sections.count;
    return numberOfSections;
}

- (NSInteger)contentView:(__kindof UIView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section
{
    id<NSFetchedResultsSectionInfo> sectionInfo = self.fetchedResultsController.sections[section];
    
    if (self.liveFetchLimit == 0)
    {
        return sectionInfo.numberOfObjects;
    }
    else
    {
        return MIN(sectionInfo.numberOfObjects, self.liveFetchLimit);
    }
}

- (void)filterContentWithPredicate:(nullable NSPredicate *)predicate
{
    RSTProxyPredicate *proxyPredicate = [[RSTProxyPredicate alloc] initWithPredicate:predicate externalPredicate:self.externalPredicate];
    self.fetchedResultsController.fetchRequest.predicate = proxyPredicate;
    
    NSError *error = nil;
    if (![self.fetchedResultsController performFetch:&error])
    {
        ELog(error);
    }
}

#pragma mark - KVO -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context != RSTFetchedResultsDataSourceContext)
    {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    NSPredicate *predicate = change[NSKeyValueChangeNewKey];
    if (![predicate isKindOfClass:[RSTProxyPredicate class]])
    {
        self.externalPredicate = predicate;
        
        RSTProxyPredicate *proxyPredicate = [[RSTProxyPredicate alloc] initWithPredicate:self.predicate externalPredicate:self.externalPredicate];
        [[(NSFetchedResultsController *)object fetchRequest] setPredicate:proxyPredicate];
    }
}

#pragma mark - <NSFetchedResultsControllerDelegate> -

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    if (self.contentView.window == nil)
    {
        // Don't update content view if it's not in window hierarchy.
        return;
    }
    
    [self.contentView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    if (self.contentView.window == nil)
    {
        return;
    }
    
    RSTCellContentChangeType changeType = RSTCellContentChangeTypeFromFetchedResultsChangeType(type);
    
    RSTCellContentChange *change = [[RSTCellContentChange alloc] initWithType:changeType sectionIndex:sectionIndex];
    change.rowAnimation = self.rowAnimation;
    [self addChange:change];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath
{
    if (self.contentView.window == nil)
    {
        return;
    }
    
    RSTCellContentChangeType changeType = RSTCellContentChangeTypeFromFetchedResultsChangeType(type);
    
    RSTCellContentChange *change = nil;
    
    if (type == NSFetchedResultsChangeUpdate && ![indexPath isEqual:newIndexPath])
    {
        // Sometimes NSFetchedResultsController incorrectly reports moves as updates with different index paths.
        // This can cause assertion failures and strange UI issues.
        // To compensate, we manually check for these "updates" and turn them into moves.
        change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeMove currentIndexPath:indexPath destinationIndexPath:newIndexPath];
    }
    else
    {
        change = [[RSTCellContentChange alloc] initWithType:changeType currentIndexPath:indexPath destinationIndexPath:newIndexPath];
    }

    change.rowAnimation = self.rowAnimation;
    
    if (self.liveFetchLimit > 0)
    {
        NSInteger itemCount = self.itemCount;
        
        switch (change.type)
        {
            case RSTCellContentChangeInsert:
                if (newIndexPath.item >= self.liveFetchLimit)
                {
                    return;
                }
                
                break;
                
            case RSTCellContentChangeDelete:
                if (indexPath.item >= self.liveFetchLimit)
                {
                    return;
                }
                
                if (itemCount >= self.liveFetchLimit)
                {
                    // Unlike insertions, deletions don't also report the items that moved.
                    // To ensure consistency, we manually insert an item previously hidden by fetch limit.
                    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.liveFetchLimit - 1 inSection:0];

                    RSTCellContentChange *change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeInsert currentIndexPath:nil destinationIndexPath:indexPath];
                    [self.contentView addChange:change];
                }
                
                break;
                
            case RSTCellContentChangeUpdate:
                if (indexPath.item >= self.liveFetchLimit)
                {
                    return;
                }
                
                break;
                
            case RSTCellContentChangeMove:
                if (indexPath.item >= self.liveFetchLimit && newIndexPath.item >= self.liveFetchLimit)
                {
                    return;
                }
                else if (indexPath.item >= self.liveFetchLimit && newIndexPath.item < self.liveFetchLimit)
                {
                    change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeInsert currentIndexPath:nil destinationIndexPath:newIndexPath];
                }
                else if (indexPath.item < self.liveFetchLimit && newIndexPath.item >= self.liveFetchLimit)
                {
                    change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeDelete currentIndexPath:indexPath destinationIndexPath:nil];
                }
                
                break;
        }
    }
    
    [self addChange:change];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    if (self.contentView.window == nil)
    {
        // Don't update content view if it's not in window hierarchy.
        return;
    }
    
    [self.contentView endUpdates];
}

#pragma mark - Getters/Setters -

- (void)setFetchedResultsController:(NSFetchedResultsController *)fetchedResultsController
{
    if (fetchedResultsController == _fetchedResultsController)
    {
        return;
    }
    
    // Clean up previous _fetchedResultsController.
    [_fetchedResultsController removeObserver:self forKeyPath:@"fetchRequest.predicate" context:RSTFetchedResultsDataSourceContext];
    
    _fetchedResultsController.fetchRequest.predicate = self.externalPredicate;
    self.externalPredicate = nil;
    
    
    // Prepare new _fetchedResultsController.
    _fetchedResultsController = fetchedResultsController;
    
    if (_fetchedResultsController.delegate == nil)
    {
        _fetchedResultsController.delegate = self;
    }
    
    self.externalPredicate = _fetchedResultsController.fetchRequest.predicate;
    
    RSTProxyPredicate *proxyPredicate = [[RSTProxyPredicate alloc] initWithPredicate:self.predicate externalPredicate:self.externalPredicate];
    _fetchedResultsController.fetchRequest.predicate = proxyPredicate;
    
    [_fetchedResultsController addObserver:self forKeyPath:@"fetchRequest.predicate" options:NSKeyValueObservingOptionNew context:RSTFetchedResultsDataSourceContext];
    
    rst_dispatch_sync_on_main_thread(^{
        [self.contentView reloadData];
    });
}

- (void)setLiveFetchLimit:(NSInteger)liveFetchLimit
{
    if (liveFetchLimit == _liveFetchLimit)
    {
        return;
    }
    
    NSInteger previousLiveFetchLimit = _liveFetchLimit;
    _liveFetchLimit = liveFetchLimit;
    
    // Turn 0 -> NSIntegerMax to simplify calculations.
    if (liveFetchLimit == 0)
    {
        liveFetchLimit = NSIntegerMax;
    }
    
    if (previousLiveFetchLimit == 0)
    {
        previousLiveFetchLimit = NSIntegerMax;
    }
    
    [self.contentView beginUpdates];
    
    id<NSFetchedResultsSectionInfo> sectionInfo = self.fetchedResultsController.sections.firstObject;
    NSInteger itemCount = sectionInfo.numberOfObjects;
    
    if (liveFetchLimit > previousLiveFetchLimit)
    {
        for (NSInteger i = previousLiveFetchLimit; i < itemCount; i++)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
                        
            RSTCellContentChange *change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeInsert currentIndexPath:nil destinationIndexPath:indexPath];
            [self addChange:change];
        }
    }
    else
    {
        for (NSInteger i = liveFetchLimit; i < itemCount && i < previousLiveFetchLimit; i++)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
            
            RSTCellContentChange *change = [[RSTCellContentChange alloc] initWithType:RSTCellContentChangeDelete currentIndexPath:indexPath destinationIndexPath:nil];
            [self addChange:change];
        }
    }
    
    [self.contentView endUpdates];
}

- (NSInteger)itemCount
{
    if (self.fetchedResultsController.fetchedObjects == nil)
    {
        return [super itemCount];
    }
    
    NSUInteger itemCount = self.fetchedResultsController.fetchedObjects.count;
    return itemCount;
}

@end

@implementation RSTFetchedResultsTableViewDataSource
@end

@implementation RSTFetchedResultsCollectionViewDataSource
@end

@implementation RSTFetchedResultsPrefetchingDataSource
@dynamic prefetchItemCache;
@dynamic prefetchHandler;
@dynamic prefetchCompletionHandler;

- (BOOL)isPrefetchingDataSource
{
    return YES;
}

@end

@implementation RSTFetchedResultsTableViewPrefetchingDataSource
@end

@implementation RSTFetchedResultsCollectionViewPrefetchingDataSource
@end
