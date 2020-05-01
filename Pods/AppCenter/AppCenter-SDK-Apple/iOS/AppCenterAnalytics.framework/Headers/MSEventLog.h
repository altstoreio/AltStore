// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSLogWithNameAndProperties.h"

@class MSEventProperties;
@class MSMetadataExtension;

@interface MSEventLog : MSLogWithNameAndProperties

/**
 * Unique identifier for this event.
 */
@property(nonatomic, copy) NSString *eventId;

/**
 * Event properties.
 */
@property(nonatomic, strong) MSEventProperties *typedProperties;

@end
