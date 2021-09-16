//
//  RSTCellContentDataSource_Subclasses.h
//  Roxas
//
//  Created by Riley Testut on 2/7/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCellContentDataSource.h"
#import "RSTCellContentPrefetchingDataSource.h"

@class RSTSearchValue;

NS_ASSUME_NONNULL_BEGIN

@protocol RSTCellContentIndexPathTranslating <NSObject>

- (nullable NSIndexPath *)dataSource:(RSTCellContentDataSource *)dataSource globalIndexPathForLocalIndexPath:(NSIndexPath *)indexPath;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

// Privately declare conformance to DataSource protocols so clients must use a concrete subclass (which provides correct generic parameters to superclass).
@interface RSTCellContentDataSource () <RSTCellContentPrefetchingDataSource, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching>

@property (nullable, weak, readwrite) UIScrollView<RSTCellContentView> *contentView;

// Defaults to synchronously setting RSTCellContentDataSource's predicate to searchValue.predicate.
// Subclasses can customize if needed, such as by returning an NSOperation inside handler to enable asynchronous RSTSearchController search results.
@property (copy, nonatomic) NSOperation *_Nullable (^defaultSearchHandler)(RSTSearchValue *searchValue, RSTSearchValue *_Nullable previousSearchValue);

@property (nullable, weak, nonatomic) id<RSTCellContentIndexPathTranslating> indexPathTranslator;

@property (nonatomic, readonly, getter=isPrefetchingDataSource) BOOL prefetchingDataSource;

- (NSInteger)numberOfSectionsInContentView:(__kindof UIScrollView<RSTCellContentView> *)contentView;
- (NSInteger)contentView:(__kindof UIScrollView<RSTCellContentView> *)contentView numberOfItemsInSection:(NSInteger)section;

- (void)prefetchItemAtIndexPath:(NSIndexPath *)indexPath completionHandler:(void (^_Nullable)(id prefetchItem, NSError *error))completionHandler;
- (void)filterContentWithPredicate:(nullable NSPredicate *)predicate;

- (void)addChange:(RSTCellContentChange *)change;

@end

NS_ASSUME_NONNULL_END
