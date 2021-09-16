//
//  RSTHelperFile.h
//  Hoot
//
//  Created by Riley Testut on 3/16/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import "RSTNavigationController.h"

@import UIKit;

/*** Math ***/

static inline CGFloat RSTDegreesFromRadians(CGFloat radians)
{
    return radians * (180.0 / M_PI);
}

static inline CGFloat RSTRadiansFromDegrees(CGFloat degrees)
{
    return (degrees * M_PI) / 180.0;
}

static inline BOOL CGFloatEqualToFloat(CGFloat float1, CGFloat float2)
{
    if (float1 == float2)
    {
        return YES;
    }
    
    if (ABS(float1 - float2) < FLT_EPSILON)
    {
        return YES;
    }
    
    return NO;
}

/*** Private Debugging ***/

// Daniel Eggert, http://www.objc.io/issue-2/low-level-concurrency-apis.html
// Returns average number of nanoseconds needed to perform task
RST_EXTERN uint64_t rst_benchmark(size_t count, void (^block)(void));


/*** Concurrency ***/

RST_EXTERN void rst_dispatch_sync_on_main_thread(dispatch_block_t block);
RST_EXTERN UIBackgroundTaskIdentifier RSTBeginBackgroundTask(NSString *name);
RST_EXTERN void RSTEndBackgroundTask(UIBackgroundTaskIdentifier backgroundTask);
