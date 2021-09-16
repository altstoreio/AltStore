//
//  RSTLoadOperation.m
//  Roxas
//
//  Created by Riley Testut on 2/21/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTLoadOperation.h"
#import "RSTOperation_Subclasses.h"

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface RSTLoadOperation ()

@property (nullable, strong, nonatomic) id result;
@property (nullable, strong, nonatomic) id error;

@end

NS_ASSUME_NONNULL_END


@implementation RSTLoadOperation

- (instancetype)initWithCacheKey:(id)cacheKey
{
    self = [super init];
    if (self)
    {
        _cacheKey = cacheKey;
    }
    
    return self;
}

- (void)main
{
    id cachedResult = nil;
    if (self.cacheKey)
    {
        cachedResult = [self.resultsCache objectForKey:self.cacheKey];
    }
    
    if (cachedResult)
    {
        self.result = cachedResult;
        
        if ([self isAsynchronous])
        {
            [self finish];
        }
        
        return;
    }
    
    [self loadResultWithCompletion:^(id _Nullable result, NSError *_Nullable error) {
        
        if ([self isCancelled])
        {
            return;
        }
        
        self.result = result;
        self.error = error;
        
        if (self.result && self.cacheKey)
        {
            [self.resultsCache setObject:result forKey:self.cacheKey];
        }
        
        if ([self isAsynchronous])
        {
            [self finish];
        }
    }];
}

- (void)loadResultWithCompletion:(void (^)(id _Nullable, NSError *_Nullable error))completion
{
    completion(nil, nil);
}

- (void)finish
{
    [super finish];
    
    if (self.resultHandler)
    {
        self.resultHandler(self.result, self.error);
    }
}

#pragma mark - Getters/Setters -

- (void)setResultsCache:(NSCache *)resultsCache
{
    _resultsCache = resultsCache;
    
    if (self.cacheKey && [_resultsCache objectForKey:self.cacheKey])
    {
        // Ensures if an item is cached, it will be returned immediately.
        // This is useful to prevent temporary flashes of placeholder images.
        self.immediate = YES;
    }
}

@end
