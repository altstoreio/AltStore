//
//  RSTLoadOperation.h
//  Roxas
//
//  Created by Riley Testut on 2/21/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTOperation.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTLoadOperation<ResultType, CacheKeyType> : RSTOperation

@property (nullable, nonatomic) CacheKeyType cacheKey;

@property (copy, nonatomic) void (^resultHandler)(_Nullable ResultType, NSError *_Nullable);
@property (nullable, nonatomic) NSCache<CacheKeyType, ResultType> *resultsCache;

- (instancetype)initWithCacheKey:(nullable CacheKeyType)cacheKey NS_DESIGNATED_INITIALIZER;

// Overridden by subclasses to return result.
- (void)loadResultWithCompletion:(void (^)(_Nullable ResultType, NSError *_Nullable))completion;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
