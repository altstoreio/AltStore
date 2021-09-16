//
//  RSTDynamicDataSource.m
//  Roxas
//
//  Created by Riley Testut on 1/2/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTDynamicDataSource.h"
#import "RSTCellContentDataSource_Subclasses.h"

@interface RSTPlaceholderItem : NSProxy
@end

@implementation RSTPlaceholderItem

- (instancetype)init
{
    return self;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    @throw [NSException exceptionWithName:@"Accessed placeholder item." reason:@"You cannot access the provided item in RSTDynamicDataSource's cellConfigurationHandler." userInfo:nil];
}

@end

@implementation RSTDynamicDataSource

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _numberOfSectionsHandler = [^NSInteger (void) {
            return 0;
        } copy];
        
        _numberOfItemsHandler = [^NSInteger (NSInteger section) {
            return 0;
        } copy];
    }
    
    return self;
}

#pragma mark - RSTCellContentDataSource -

- (NSInteger)numberOfSectionsInContentView:(__kindof UIScrollView<RSTCellContentView> *)contentView
{
    NSInteger numberOfSections = self.numberOfSectionsHandler();
    return numberOfSections;
}

- (NSInteger)contentView:(__kindof UIScrollView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section
{
    NSInteger numberOfItems = self.numberOfItemsHandler(section);
    return numberOfItems;
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    RSTPlaceholderItem *placeholder = [[RSTPlaceholderItem alloc] init];
    return placeholder;
}

- (void)filterContentWithPredicate:(NSPredicate *)predicate
{
}

@end

@implementation RSTDynamicTableViewDataSource
@end

@implementation RSTDynamicCollectionViewDataSource
@end

@implementation RSTDynamicPrefetchingDataSource
@dynamic prefetchItemCache;
@dynamic prefetchHandler;
@dynamic prefetchCompletionHandler;

- (BOOL)isPrefetchingDataSource
{
    return YES;
}

@end

@implementation RSTDynamicTableViewPrefetchingDataSource
@end

@implementation RSTDynamicCollectionViewPrefetchingDataSource
@end
