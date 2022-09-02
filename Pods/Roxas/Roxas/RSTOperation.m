//
//  RSTOperation.m
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTOperation.h"
#import "RSTOperation_Subclasses.h"

static void *RSTOperationKVOContext = &RSTOperationKVOContext;

@implementation RSTOperation

- (void)start
{
    if (![self isAsynchronous])
    {
        [self addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:NSKeyValueObservingOptionNew context:RSTOperationKVOContext];
        
        [super start];
        
        return;
    }
    
    if ([self isFinished])
    {
        return;
    }
    
    if ([self isCancelled])
    {
        [self finish];
    }
    else
    {
        [self willChangeValueForKey:@"isExecuting"];
        _isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
        
        [self main];
    }
}

- (void)finish
{
    if (![self isAsynchronous])
    {
        return;
    }
    
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    
    _isExecuting = NO;
    _isFinished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (BOOL)isExecuting
{
    if (![self isAsynchronous])
    {
        return [super isExecuting];
    }
    
    return _isExecuting;
}

- (BOOL)isFinished
{
    if (![self isAsynchronous])
    {
        return [super isFinished];
    }
    
    return _isFinished;
}

#pragma mark - KVO -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context != RSTOperationKVOContext)
    {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    if ([change[NSKeyValueChangeNewKey] boolValue])
    {
        // Manually call finish for synchronous subclasses that override it to know when operation is finished.
        [self finish];
        
        [self removeObserver:self forKeyPath:keyPath context:RSTOperationKVOContext];
    }
}

#pragma mark - Getters/Setters -

- (void)setImmediate:(BOOL)immediate
{
    if (immediate == _immediate)
    {
        return;
    }
    
    _immediate = immediate;
    
    if (immediate)
    {
        self.qualityOfService = NSQualityOfServiceUserInitiated;
        self.queuePriority = NSOperationQueuePriorityHigh;
    }
    else
    {
        self.qualityOfService = NSQualityOfServiceDefault;
        self.queuePriority = NSOperationQueuePriorityNormal;
    }
}

@end
