//
//  NSConstraintConflict+Conveniences.m
//  Roxas
//
//  Created by Riley Testut on 10/4/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "NSConstraintConflict+Conveniences.h"

@import ObjectiveC.runtime;

@interface NSManagedObject (ConstraintConflict)
@end

@implementation NSManagedObject (ConstraintConflict)

- (NSDictionary<NSString *, id> *)rst_snapshot
{
    NSArray<NSString *> *keys = self.entity.propertiesByName.allKeys;
    
    NSDictionary *snapshot = [self dictionaryWithValuesForKeys:keys];
    return snapshot;
}

@end

@implementation NSConstraintConflict (Conveniences)

- (NSSet<NSManagedObject *> *)allObjects
{
    NSMutableSet<NSManagedObject *> *allObjects = [NSMutableSet setWithArray:self.conflictingObjects];
    if (self.databaseObject != nil)
    {
        [allObjects addObject:self.databaseObject];
    }
    
    return allObjects;
}

- (NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *)snapshots
{
    NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *snapshots = objc_getAssociatedObject(self, @selector(snapshots));
    if (snapshots != nil)
    {
        return snapshots;
    }
    
    snapshots = [NSMapTable strongToStrongObjectsMapTable];
    
    for (NSManagedObject *managedObject in self.allObjects)
    {
        NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
        
        for (NSPropertyDescription *property in managedObject.entity.properties)
        {
            if ([property isTransient] || [property isKindOfClass:[NSFetchedPropertyDescription class]])
            {
                continue;
            }
            
            id value = [managedObject valueForKey:property.name];
            
            if ([property isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)property isToMany])
            {
                // Must create a mutable set then add objects to it to prevent rare crash when relationship is still a fault.
                NSMutableSet *relationshipObjects = [[NSMutableSet alloc] init];
                
                NSSet *set = (NSSet *)value;
                for (id value in set)
                {
                    [relationshipObjects addObject:value];
                }
                
                snapshot[property.name] = relationshipObjects;
            }
            else
            {
                snapshot[property.name] = value;
            }
        }
        
        [snapshots setObject:snapshot forKey:managedObject];
    }
    
    objc_setAssociatedObject(self, @selector(snapshots), snapshots, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    return snapshots;
}

+ (NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *)cacheSnapshotsForConflicts:(NSArray<NSConstraintConflict *> *)conflicts
{
    NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *snapshots = [NSMapTable strongToStrongObjectsMapTable];
    
    for (NSConstraintConflict *conflict in conflicts)
    {
        NSMapTable<NSManagedObject *, NSDictionary<NSString *, id> *> *conflictSnapshots = conflict.snapshots;
        for (NSManagedObject *managedObject in conflictSnapshots)
        {
            NSDictionary<NSString *, id> *snapshot = [conflictSnapshots objectForKey:managedObject];
            [snapshots setObject:snapshot forKey:managedObject];
        }
    }
    
    return snapshots;
}

@end
