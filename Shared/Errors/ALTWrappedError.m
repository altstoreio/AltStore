//
//  ALTWrappedError.m
//  AltStoreCore
//
//  Created by Riley Testut on 11/28/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

#import "ALTWrappedError.h"

@implementation ALTWrappedError

+ (BOOL)supportsSecureCoding
{
    // Required in order to serialize errors for legacy AltServer communication.
    return YES;
}

- (instancetype)initWithError:(NSError *)error userInfo:(NSDictionary<NSString *,id> *)userInfo
{
    self = [super initWithDomain:error.domain code:error.code userInfo:userInfo];
    if (self)
    {
        if ([error isKindOfClass:[ALTWrappedError class]])
        {
            _wrappedError = [(ALTWrappedError *)error wrappedError];
        }
        else
        {
            _wrappedError = [error copy];
        }
    }
    
    return self;
}

- (NSString *)localizedDescription
{
    NSString *localizedFailureReason = self.wrappedError.localizedFailureReason ?: self.wrappedError.localizedDescription;
    
    NSString *wrappedLocalizedDescription = self.wrappedError.userInfo[NSLocalizedDescriptionKey];
    if (wrappedLocalizedDescription != nil)
    {
        NSString *localizedFailure = self.wrappedError.userInfo[NSLocalizedFailureErrorKey];
        
        NSString *fallbackDescription = localizedFailure != nil ? [NSString stringWithFormat:@"%@ %@", localizedFailure, localizedFailureReason] : localizedFailureReason;
        if (![wrappedLocalizedDescription isEqualToString:fallbackDescription])
        {
            return wrappedLocalizedDescription;
        }
    }
    
    NSString *localizedFailure = self.userInfo[NSLocalizedFailureErrorKey];
    if (localizedFailure != nil)
    {
        NSString *localizedDescription = [NSString stringWithFormat:@"%@ %@", localizedFailure, localizedFailureReason];
        return localizedDescription;
    }
    
    // localizedFailure is nil, so return wrappedError's localizedDescription.
    return self.wrappedError.localizedDescription;
}

- (NSString *)localizedFailureReason
{
    return self.wrappedError.localizedFailureReason;
}

- (NSString *)localizedRecoverySuggestion
{
    return self.wrappedError.localizedRecoverySuggestion;
}

- (NSString *)debugDescription
{
    return self.wrappedError.debugDescription;
}

- (NSString *)helpAnchor
{
    return self.wrappedError.helpAnchor;
}

@end
