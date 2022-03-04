//
//  ALTPluginService.h
//  AltPlugin
//
//  Created by Riley Testut on 11/14/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ALTAnisetteData;

NS_ASSUME_NONNULL_BEGIN

@interface ALTPluginService : NSObject

@property (class, nonatomic, readonly) ALTPluginService *sharedService;

- (ALTAnisetteData *)requestAnisetteData;

@end

NS_ASSUME_NONNULL_END
