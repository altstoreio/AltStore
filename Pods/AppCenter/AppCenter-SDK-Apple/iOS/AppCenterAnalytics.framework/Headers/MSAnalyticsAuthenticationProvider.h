// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSAnalyticsAuthenticationProviderDelegate.h"

/**
 * Different authentication types, e.g. MSA Compact, MSA Delegate, AAD,... .
 */
typedef NS_ENUM(NSUInteger, MSAnalyticsAuthenticationType) {

  /**
   * AuthenticationType MSA Compact.
   */
  MSAnalyticsAuthenticationTypeMsaCompact,

  /**
   * AuthenticationType MSA Delegate.
   */
  MSAnalyticsAuthenticationTypeMsaDelegate
};

NS_ASSUME_NONNULL_BEGIN

@interface MSAnalyticsAuthenticationProvider : NSObject

/**
 * The type.
 */
@property(nonatomic, readonly, assign) MSAnalyticsAuthenticationType type;

/**
 * The ticket key for this authentication provider.
 */
@property(nonatomic, readonly, copy) NSString *ticketKey;

/**
 * The ticket key as hash.
 */
@property(nonatomic, readonly, copy) NSString *ticketKeyHash;

@property(nonatomic, readonly, weak) id<MSAnalyticsAuthenticationProviderDelegate> delegate;

/**
 * Create a new authentication provider.
 *
 * @param type The type for the provider, e.g. MSA.
 * @param ticketKey The ticket key for the provider.
 * @param delegate The delegate.
 *
 * @return A new authentication provider.
 */
- (instancetype)initWithAuthenticationType:(MSAnalyticsAuthenticationType)type
                                 ticketKey:(NSString *)ticketKey
                                  delegate:(id<MSAnalyticsAuthenticationProviderDelegate>)delegate;

/**
 * Check expiration.
 */
- (void)checkTokenExpiry;

@end

NS_ASSUME_NONNULL_END
