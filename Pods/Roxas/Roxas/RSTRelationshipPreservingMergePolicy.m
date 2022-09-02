//
//  RSTRelationshipPreservingMergePolicy.m
//  Roxas
//
//  Created by Riley Testut on 7/16/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTRelationshipPreservingMergePolicy.h"

#import "NSConstraintConflict+Conveniences.h"

@implementation RSTRelationshipPreservingMergePolicy

- (instancetype)init
{
    self = [super initWithMergeType:NSMergeByPropertyObjectTrumpMergePolicyType];
    return self;
}

- (BOOL)resolveConstraintConflicts:(NSArray<NSConstraintConflict *> *)conflicts error:(NSError * _Nullable __autoreleasing *)error
{
    [NSConstraintConflict cacheSnapshotsForConflicts:conflicts];
    
    BOOL success = [super resolveConstraintConflicts:conflicts error:error];
    
    for (NSConstraintConflict *conflict in conflicts)
    {
        if (conflict.databaseObject == nil)
        {
            // Only handle database-level conflicts.
            continue;
        }
        
        NSManagedObject *databaseObject = conflict.databaseObject;
        NSManagedObject *updatedObject = conflict.conflictingObjects.firstObject;
        
        NSDictionary<NSString *, id> *databaseSnapshot = [conflict.snapshots objectForKey:databaseObject];
        NSDictionary<NSString *, id> *updatedSnapshot = [conflict.snapshots objectForKey:updatedObject];

        if (databaseObject == nil || updatedObject == nil || databaseSnapshot == nil || updatedSnapshot == nil)
        {
            continue;
        }
        
        [databaseObject.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *relationship, BOOL *stop) {
            if ([relationship isToMany])
            {
                // Superclass already handles to-many relationships correctly, so ignore this relationship.
                return;
            }
            
            NSManagedObject *relationshipObject = nil;
            
            NSManagedObject *previousRelationshipObject = databaseSnapshot[name];
            NSManagedObject *updatedRelationshipObject = updatedSnapshot[name];
            
            if (previousRelationshipObject != nil)
            {                
                if (updatedRelationshipObject == nil)
                {
                    if (updatedObject.changedValues[name] == nil)
                    {
                        // Previously non-nil, updated to nil, but was _not_ explicitly set to nil, so restore previous relationship.
                        relationshipObject = previousRelationshipObject;
                    }
                    else
                    {
                        // Same as above, but _was_ explicitly set to nil, so should remain nil.
                        relationshipObject = nil;
                    }
                }
                else
                {
                    if ([databaseObject valueForKey:name] == nil)
                    {
                        // Previously non-nil, updated to non-nil, but resulted in nil, so restore previous relationship (since the new relationship has been deleted).
                        relationshipObject = previousRelationshipObject;
                    }
                    else if (updatedRelationshipObject.managedObjectContext == nil)
                    {
                        // Previously non-nil, updated to non-nil, but the updated snapshot points to an outdated relationship object, so restore previous relationship.
                        relationshipObject = previousRelationshipObject;
                    }
                    else
                    {
                        // Previously non-nil, updated to non-nil, so ensure relationship object is the updated relationship object.
                        relationshipObject = updatedRelationshipObject;
                    }
                }
            }
            else
            {
                if (updatedRelationshipObject != nil)
                {
                    // Previously nil, updated to non-nil, so restore updated relationship.
                    relationshipObject = updatedRelationshipObject;
                }
                else
                {
                    // Previously nil, remained nil, so no need to fix anything.
                    relationshipObject = nil;
                }
            }
            
            if ([databaseObject valueForKey:name] == relationshipObject)
            {
                return;
            }
            
            if (relationshipObject.managedObjectContext == nil)
            {
                return;
            }
            
            [databaseObject setValue:relationshipObject forKey:name];
            
            NSRelationshipDescription *inverseRelationship = relationship.inverseRelationship;
            if (inverseRelationship != nil && ![inverseRelationship isToMany])
            {
                // We need to also update to-one inverse relationships.
                
                if (relationshipObject != nil)
                {
                    [relationshipObject setValue:databaseObject forKey:inverseRelationship.name];
                }
                else
                {
                    [previousRelationshipObject setValue:nil forKey:inverseRelationship.name];
                    [updatedRelationshipObject setValue:nil forKey:inverseRelationship.name];
                }
            }
        }];
    }
    
    return success;
}

@end
