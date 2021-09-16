//
//  RSTRelationshipPreservingMergePolicy.h
//  Roxas
//
//  Created by Riley Testut on 7/16/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

@import CoreData;

NS_ASSUME_NONNULL_BEGIN

@interface RSTRelationshipPreservingMergePolicy : NSMergePolicy

- (instancetype)init;

- (instancetype)initWithMergeType:(NSMergePolicyType)mergeType NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
