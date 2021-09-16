//
//  RSTCellContentPrefetchingDataSource.h
//  Roxas
//
//  Created by Riley Testut on 7/6/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTCellContentCell.h"

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@protocol RSTCellContentPrefetchingDataSource <NSObject>

@property (nonatomic) NSCache *prefetchItemCache;

@property (nullable, copy, nonatomic) NSOperation *_Nullable (^prefetchHandler)(id item, NSIndexPath *indexPath, void (^completionHandler)(_Nullable id item, NSError *_Nullable error));
@property (nullable, copy, nonatomic) void (^prefetchCompletionHandler)(__kindof UIView<RSTCellContentCell> *cell, _Nullable id item, NSIndexPath *indexPath, NSError *_Nullable error);

@end

NS_ASSUME_NONNULL_END
