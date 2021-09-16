//
//  RSTOperationQueue.m
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTOperationQueue.h"
#import "RSTOperation.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTOperationQueue ()

@property (copy, nonatomic, readonly) NSMapTable<id, NSOperation *> *operationsMapTable;

@end

NS_ASSUME_NONNULL_END

@implementation RSTOperationQueue

#pragma mark - NSOperationQueue -

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _operationsMapTable = [NSMapTable strongToWeakObjectsMapTable];
    }
    
    return self;
}

- (void)addOperation:(NSOperation *)operation
{
    [super addOperation:operation];
    
    if ([operation isKindOfClass:[RSTOperation class]] && [(RSTOperation *)operation isImmediate])
    {
        // Maintain a reference to completion block, and then nil it out so it isn't called automatically
        void (^completionBlock)(void) = operation.completionBlock;
        operation.completionBlock = nil;
        
        [operation waitUntilFinished];
        
        if (completionBlock)
        {
            // Call the completion block ourselves to ensure it gets called synchronously *after* waitUntilFinished returns, but *before* this method returns
            completionBlock();
        }
    }
}

#pragma mark - RSTOperationQueue -

- (void)addOperation:(NSOperation *)operation forKey:(id)key
{
    NSOperation *previousOperation = [self operationForKey:key];
    [previousOperation cancel];
        
    [self.operationsMapTable setObject:operation forKey:key];
    
    [self addOperation:operation];
}

- (NSOperation *)operationForKey:(id)key
{
    NSOperation *operation = [self.operationsMapTable objectForKey:key];
    return operation;
}

- (NSOperation *)objectForKeyedSubscript:(id)key
{
    return [self operationForKey:key];
}

@end
