//
//  RSTCellContentChangeOperation.h
//  Roxas
//
//  Created by Riley Testut on 8/2/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTOperation.h"

@import UIKit;

@class RSTCellContentChange;

NS_ASSUME_NONNULL_BEGIN

@interface RSTCellContentChangeOperation : RSTOperation

@property (copy, nonatomic, readonly) RSTCellContentChange *change;

- (instancetype)init NS_UNAVAILABLE;

@end


@interface RSTTableViewChangeOperation : RSTCellContentChangeOperation

@property (nullable, weak, nonatomic, readonly) UITableView *tableView;

- (instancetype)initWithChange:(RSTCellContentChange *)change tableView:(nullable UITableView *)tableView NS_DESIGNATED_INITIALIZER;

@end


@interface RSTCollectionViewChangeOperation : RSTCellContentChangeOperation

@property (nullable, weak, nonatomic, readonly) UICollectionView *collectionView;

- (instancetype)initWithChange:(RSTCellContentChange *)change collectionView:(nullable UICollectionView *)collectionView NS_DESIGNATED_INITIALIZER;

@end


NS_ASSUME_NONNULL_END
