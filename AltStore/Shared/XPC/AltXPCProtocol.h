//
//  AltXPCProtocol.h
//  AltXPC
//
//  Created by Riley Testut on 12/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ALTAnisetteData;

@protocol AltXPCProtocol

- (void)ping:(void (^_Nonnull)(void))completionHandler;
- (void)requestAnisetteDataWithCompletionHandler:(void (^_Nonnull)(ALTAnisetteData *_Nullable anisetteData, NSError *_Nullable error))completionHandler;
    
@end
