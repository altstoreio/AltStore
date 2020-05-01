// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSAnalyticsAuthenticationProvider;

/**
 * Completion handler that returns the authentication token and the expiry date.
 */
typedef void (^MSAnalyticsAuthenticationProviderCompletionBlock)(NSString *token, NSDate *expiryDate);

@protocol MSAnalyticsAuthenticationProviderDelegate <NSObject>

/**
 * Required method that needs to be called from within your authentication flow to provide the authentication token and expiry date.
 *
 * @param authenticationProvider The authentication provider.
 * @param completionHandler The completion handler.
 */
- (void)authenticationProvider:(MSAnalyticsAuthenticationProvider *)authenticationProvider
    acquireTokenWithCompletionHandler:(MSAnalyticsAuthenticationProviderCompletionBlock)completionHandler;

@end
