//
//  RSTError.m
//  Roxas
//
//  Created by Riley Testut on 1/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "RSTError.h"

NSErrorDomain const RoxasErrorDomain = @"com.rileytestut.Roxas";

@implementation NSError (Roxas)

+ (void)load
{
    [NSError setUserInfoValueProviderForDomain:RoxasErrorDomain provider:^id _Nullable(NSError * _Nonnull error, NSErrorUserInfoKey  _Nonnull userInfoKey) {
        if ([userInfoKey isEqualToString:NSLocalizedDescriptionKey])
        {
            return [error rst_localizedDescription];
        }
        
        return nil;
    }];
}

- (nullable NSString *)rst_localizedDescription
{
    switch (self.code)
    {
        case RSTErrorMissingManagedObjectModel:
            return NSLocalizedString(@"Unable to find any managed object models.", @"");
            
        case RSTErrorMissingMappingModel:
            return NSLocalizedString(@"Unable to find a valid mapping model.", @"");
            
        case RSTErrorMissingPersistentStore:
            return NSLocalizedString(@"Unable to find a persistent store.", @"");
    }
    
    return nil;
}

@end
