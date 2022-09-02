//
//  RSTCellContentChange.h
//  Roxas
//
//  Created by Riley Testut on 8/2/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTDefines.h"

@import UIKit;
@import CoreData;

@class RSTCellContentChange;

NS_ASSUME_NONNULL_BEGIN

extern NSInteger RSTUnknownSectionIndex;

typedef NS_ENUM(NSInteger, RSTCellContentChangeType)
{
    RSTCellContentChangeInsert = NSFetchedResultsChangeInsert,
    RSTCellContentChangeDelete = NSFetchedResultsChangeDelete,
    RSTCellContentChangeMove   = NSFetchedResultsChangeMove,
    RSTCellContentChangeUpdate = NSFetchedResultsChangeUpdate,
};

RST_EXTERN RSTCellContentChangeType RSTCellContentChangeTypeFromFetchedResultsChangeType(NSFetchedResultsChangeType type);
RST_EXTERN NSFetchedResultsChangeType NSFetchedResultsChangeTypeFromCellContentChangeType(RSTCellContentChangeType type);

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface RSTCellContentChange : NSObject <NSCopying>

@property (nonatomic, readonly) RSTCellContentChangeType type;

@property (nullable, copy, nonatomic, readonly) NSIndexPath *currentIndexPath;
@property (nullable, copy, nonatomic, readonly) NSIndexPath *destinationIndexPath;

// Defaults to RSTUnknownSectionIndex if not representing a section.
@property (nonatomic, readonly) NSInteger sectionIndex;

// Animation to use when applied to a UITableView.
@property (nonatomic) UITableViewRowAnimation rowAnimation;

- (instancetype)initWithType:(RSTCellContentChangeType)type currentIndexPath:(nullable NSIndexPath *)currentIndexPath destinationIndexPath:(nullable NSIndexPath *)destinationIndexPath NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithType:(RSTCellContentChangeType)type sectionIndex:(NSInteger)sectionIndex NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
