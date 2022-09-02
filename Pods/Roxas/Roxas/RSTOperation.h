//
//  RSTOperation.h
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

@import Foundation;

@interface RSTOperation : NSOperation

// Immediate operations, when added to an RSTOperationQueue, are performed immediately and synchronously.
// Essentially, immediate operations act the same as if they were synchronous operations started outside of an operation queue.
// Because of this, they block whatever thread they were added to the operation queue on, so be careful!
@property (nonatomic, getter=isImmediate) BOOL immediate;

@end
