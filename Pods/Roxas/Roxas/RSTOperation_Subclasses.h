//
//  RSTOperation_Subclasses.h
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTOperation.h"

@interface RSTOperation ()
{
    @protected BOOL _isExecuting;
    @protected BOOL _isFinished;
}

- (void)finish NS_REQUIRES_SUPER;

@end
