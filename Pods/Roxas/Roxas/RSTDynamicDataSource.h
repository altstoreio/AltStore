//
//  RSTDynamicDataSource.h
//  Roxas
//
//  Created by Riley Testut on 1/2/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTCellContentDataSource.h"
#import "RSTCellContentPrefetchingDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTDynamicDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType> : RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType>

@property (copy, nonatomic) NSInteger (^numberOfSectionsHandler)(void);
@property (copy, nonatomic) NSInteger (^numberOfItemsHandler)(NSInteger section);

@end

@interface RSTDynamicPrefetchingDataSource<ContentType, CellType: UIView<RSTCellContentCell> *, ViewType: UIScrollView<RSTCellContentView> *, DataSourceType, PrefetchContentType> : RSTDynamicDataSource<ContentType, CellType, ViewType, DataSourceType> <RSTCellContentPrefetchingDataSource>

@property (nonatomic) NSCache<ContentType, PrefetchContentType> *prefetchItemCache;

@property (nullable, copy, nonatomic) NSOperation *_Nullable (^prefetchHandler)(ContentType item, NSIndexPath *indexPath, void (^completionHandler)(_Nullable PrefetchContentType item, NSError *_Nullable error));
@property (nullable, copy, nonatomic) void (^prefetchCompletionHandler)(CellType cell, _Nullable PrefetchContentType item, NSIndexPath *indexPath, NSError *_Nullable error);

@end

NS_ASSUME_NONNULL_END


// Concrete Subclasses

NS_ASSUME_NONNULL_BEGIN

@interface RSTDynamicTableViewDataSource<ContentType> : RSTDynamicDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>> <UITableViewDataSource>
@end

@interface RSTDynamicCollectionViewDataSource<ContentType> : RSTDynamicDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>> <UICollectionViewDataSource>
@end


@interface RSTDynamicTableViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTDynamicPrefetchingDataSource<ContentType, UITableViewCell *, UITableView *, id<UITableViewDataSource>, PrefetchContentType> <UITableViewDataSource, UITableViewDataSourcePrefetching>
@end

@interface RSTDynamicCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType> : RSTDynamicPrefetchingDataSource<ContentType, UICollectionViewCell *, UICollectionView *, id<UICollectionViewDataSource>, PrefetchContentType> <UICollectionViewDataSource, UICollectionViewDataSourcePrefetching>
@end

NS_ASSUME_NONNULL_END
