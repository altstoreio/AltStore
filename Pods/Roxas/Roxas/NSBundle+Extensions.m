//
//  NSBundle+Extensions.m
//  Roxas
//
//  Created by Riley Testut on 12/14/14.
//  Copyright (c) 2014 Riley Testut. All rights reserved.
//

#import "NSBundle+Extensions.h"

@implementation NSBundle (Extensions)

+ (BOOL)isAppExtension
{
    return [[[self mainBundle] executablePath] containsString:@".appex/"];
}

@end
