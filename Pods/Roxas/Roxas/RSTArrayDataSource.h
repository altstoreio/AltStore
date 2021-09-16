//
//  RSTArrayDataSource.h
//  Roxas
//
//  Created by Riley Testut on 2/13/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCellContentDataSource.h"
#import "RSTCellContentPrefetchingDataSource.h"

@class RSTCellContentChange;

NS_ASSUME_NONNULL_BEGIN

@interface RSTArrayDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType> : RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType>

@property (copy, nonatomic) NSArray<ContentType> *items;

- (instancetype)initWithItems:(NSArray<ContentType> *)items NS_DESIGNATED_INITIALIZER;

- (void)setItems:(NSArray<ContentType> *)items withChanges:(nullable NSArray<RSTCellContentChange *> *)changes;

- (instancetype)init NS_UNAVAILABLE;

@end


@interface RSTArrayPrefetchingDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType, PrefetchContentType> : RSTArrayDataSource<ContentType, CellType, ViewType, DataSourceType> <RSTCellContentPrefetchingDataSource>

@property (nonatomic) NSCache<ContentType, PrefetchContentType> *prefetchItemCache;

@property (nullable, copy, nonatomic) NSOperation *_Nullable (^prefetchHandler)(ContentType item, NSIndexPath *indexPath, void (^completionHandler)(_Nullable PrefetchContentType item, NSError *_Nullable error));
@property (nullable, copy, nonatomic) void (^prefetchCompletionHandler)(CellType cell, _Nullable PrefetchContentType item, NSIndexPath *indexPath, NSError *_Nullable error);

@end

NS_ASSUME_NONNULL_END


// Concrete Subclasses

NS_ASSUME_NONNULL_BEGIN

@interface RSTArrayTableViewDataSource<ContentType> : RSTArrayDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>> <UITableViewDataSource>
@end

@interface RSTArrayCollectionViewDataSource<ContentType> : RSTArrayDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>> <UICollectionViewDataSource>
@end


@interface RSTArrayTableViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTArrayPrefetchingDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>, PrefetchContentType> <UITableViewDataSource, UITableViewDataSourcePrefetching>
@end

@interface RSTArrayCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTArrayPrefetchingDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>, PrefetchContentType> <UICollectionViewDataSource, UICollectionViewDataSourcePrefetching>
@end

NS_ASSUME_NONNULL_END
