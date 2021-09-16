//
//  RSTHelperFile.m
//  Hoot
//
//  Created by Riley Testut on 3/16/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import "RSTHelperFile.h"

#ifdef DEBUG

uint64_t dispatch_benchmark(size_t count, void (^block)(void));

uint64_t rst_benchmark(size_t count, void (^block)(void))
{
    return dispatch_benchmark(count, block);;
}

#else

uint64_t rst_benchmark(size_t count, void (^block)(void))
{
    return 0;
}

#endif

void rst_dispatch_sync_on_main_thread(dispatch_block_t block)
{
    if ([NSThread isMainThread])
    {
        if (block)
        {
            block();
        }
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

UIBackgroundTaskIdentifier RSTBeginBackgroundTask(NSString *name)
{
    __block UIBackgroundTaskIdentifier backgroundTask = [[[UIApplication class] sharedApplication] beginBackgroundTaskWithName:name expirationHandler:^{
        RSTEndBackgroundTask(backgroundTask);
    }];
    
    return backgroundTask;
};

void RSTEndBackgroundTask(UIBackgroundTaskIdentifier backgroundTask)
{
    [[[UIApplication class] sharedApplication] endBackgroundTask:backgroundTask];
    backgroundTask = UIBackgroundTaskInvalid;
}