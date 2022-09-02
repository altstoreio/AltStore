//
//  RSTError.h
//  Roxas
//
//  Created by Riley Testut on 1/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@import Foundation;

extern NSErrorDomain const RoxasErrorDomain;

typedef NS_ERROR_ENUM(RoxasErrorDomain, RSTError)
{
    RSTErrorMissingManagedObjectModel = -23,
    RSTErrorMissingMappingModel = -24,
    RSTErrorMissingPersistentStore = -25,
};

NS_ASSUME_NONNULL_BEGIN

@interface NSError (Roxas)
@end

NS_ASSUME_NONNULL_END
