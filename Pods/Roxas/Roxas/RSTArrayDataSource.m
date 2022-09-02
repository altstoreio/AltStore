//
//  RSTArrayDataSource.m
//  Roxas
//
//  Created by Riley Testut on 2/13/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTArrayDataSource.h"
#import "RSTCellContentDataSource_Subclasses.h"

#import "RSTHelperFile.h"


NS_ASSUME_NONNULL_BEGIN

@interface RSTArrayDataSource ()

@property (nullable, copy, nonatomic) NSArray *filteredItems;

@end

NS_ASSUME_NONNULL_END


@implementation RSTArrayDataSource

- (instancetype)initWithItems:(NSArray *)items
{
    self = [super init];
    if (self)
    {
        _items = [items copy];
    }
    
    return self;
}

#pragma mark - RSTCellContentDataSource -

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *items = self.filteredItems ?: self.items;
    return items[indexPath.row];
}

- (NSInteger)numberOfSectionsInContentView:(__kindof UIView<RSTCellContentView> *)contentView
{
    return 1;
}

- (NSInteger)contentView:(__kindof UIView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section
{
    NSArray *items = self.filteredItems ?: self.items;
    return items.count;
}

- (void)filterContentWithPredicate:(nullable NSPredicate *)predicate
{
    if (predicate == nil)
    {
        self.filteredItems = nil;
    }
    else
    {
        self.filteredItems = [self.items filteredArrayUsingPredicate:predicate];
    }
}

#pragma mark - Getters/Setters -

- (void)setItems:(NSArray *)items
{
    [self setItems:items withChanges:nil];
}

- (void)setItems:(NSArray *)items withChanges:(NSArray<RSTCellContentChange *> *)changes
{
    _items = [items copy];
    
    if (self.filteredItems)
    {
        [self filterContentWithPredicate:self.predicate];
        
        rst_dispatch_sync_on_main_thread(^{
            [self.contentView reloadData];
        });
    }
    else
    {
        if (changes)
        {
            [self.contentView beginUpdates];
            
            for (RSTCellContentChange *change in changes)
            {
                [self addChange:change];
            }
            
            [self.contentView endUpdates];
        }
        else
        {
            rst_dispatch_sync_on_main_thread(^{
                [self.contentView reloadData];
            });
        }
    }
}

@end

@implementation RSTArrayTableViewDataSource
@end

@implementation RSTArrayCollectionViewDataSource
@end

@implementation RSTArrayPrefetchingDataSource
@dynamic prefetchItemCache;
@dynamic prefetchHandler;
@dynamic prefetchCompletionHandler;

- (BOOL)isPrefetchingDataSource
{
    return YES;
}

@end

@implementation RSTArrayTableViewPrefetchingDataSource
@end

@implementation RSTArrayCollectionViewPrefetchingDataSource
@end
