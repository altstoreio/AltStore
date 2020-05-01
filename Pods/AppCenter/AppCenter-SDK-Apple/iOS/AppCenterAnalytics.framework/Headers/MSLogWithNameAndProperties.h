// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSLogWithProperties.h"

@interface MSLogWithNameAndProperties : MSLogWithProperties

/**
 * Name of the event.
 */
@property(nonatomic, copy) NSString *name;

@end
