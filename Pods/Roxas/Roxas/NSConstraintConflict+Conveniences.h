//
//  NSConstraintConflict+Conveniences.h
//  Roxas
//
//  Created by Riley Testut on 10/4/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import CoreData;

NS_ASSUME_NONNULL_BEGIN

@interface NSConstraintConflict (Conveniences)

@property (nonatomic, readonly) NSSet<NSManagedObject *> *allObjects;

@property (nonatomic, readonly) NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *snapshots;

+ (NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *)cacheSnapshotsForConflicts:(NSArray<NSConstraintConflict *> *)conflicts;

@end

NS_ASSUME_NONNULL_END
