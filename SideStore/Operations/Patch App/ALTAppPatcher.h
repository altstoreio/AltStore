//
//  ALTAppPatcher.h
//  AltStore
//
//  Created by Riley Testut on 10/18/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTAppPatcher : NSObject

- (BOOL)patchAppBinaryAtURL:(NSURL *)appFileURL withBinaryAtURL:(NSURL *)patchFileURL error:(NSError *_Nullable *)error;

@end

NS_ASSUME_NONNULL_END
