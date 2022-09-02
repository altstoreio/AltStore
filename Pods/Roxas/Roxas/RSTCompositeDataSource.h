//
//  RSTCompositeDataSource.h
//  Roxas
//
//  Created by Riley Testut on 12/19/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCellContentDataSource.h"
#import "RSTCellContentPrefetchingDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTCompositeDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType> : RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType>

@property (nonatomic, copy, readonly) NSArray<RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> *> *dataSources;

@property (nonatomic) BOOL shouldFlattenSections;

- (instancetype)initWithDataSources:(NSArray<RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> *> *)dataSources;

- (nullable RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> *)dataSourceForIndexPath:(NSIndexPath *)indexPath;

- (instancetype)init NS_UNAVAILABLE;

@end


@interface RSTCompositePrefetchingDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType, PrefetchContentType> : RSTCompositeDataSource<ContentType, CellType, ViewType, DataSourceType> <RSTCellContentPrefetchingDataSource>

@property (nonatomic) NSCache<ContentType, PrefetchContentType> *prefetchItemCache;

@property (nullable, copy, nonatomic) NSOperation *_Nullable (^prefetchHandler)(ContentType item, NSIndexPath *indexPath, void (^completionHandler)(_Nullable PrefetchContentType item, NSError *_Nullable error));
@property (nullable, copy, nonatomic) void (^prefetchCompletionHandler)(CellType cell, _Nullable PrefetchContentType item, NSIndexPath *indexPath, NSError *_Nullable error);

@end

NS_ASSUME_NONNULL_END


// Concrete Subclasses

NS_ASSUME_NONNULL_BEGIN

@interface RSTCompositeTableViewDataSource<ContentType> : RSTCompositeDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>> <UITableViewDataSource>
@end

@interface RSTCompositeCollectionViewDataSource<ContentType> : RSTCompositeDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>> <UICollectionViewDataSource>
@end


@interface RSTCompositeTableViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTCompositePrefetchingDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>, PrefetchContentType> <UITableViewDataSource, UITableViewDataSourcePrefetching>
@end

@interface RSTCompositeCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTCompositePrefetchingDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>, PrefetchContentType> <UICollectionViewDataSource, UICollectionViewDataSourcePrefetching>
@end

NS_ASSUME_NONNULL_END
