//
//  NSString+Localization.m
//  Roxas
//
//  Created by Riley Testut on 1/13/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "NSString+Localization.h"

@import UIKit;

NSString *RSTSystemLocalizedStringNotFound = @"com.rileytestut.RSTSystemLocalizedStringNotFound";

@implementation NSString (Localization)

NSString *RSTSystemLocalizedString(NSString *string)
{
    NSBundle *bundle = [NSBundle bundleForClass:UIApplication.class];
    
    NSString *localizedString = [bundle localizedStringForKey:string value:RSTSystemLocalizedStringNotFound table:nil];
    
    if ([localizedString isEqualToString:RSTSystemLocalizedStringNotFound])
    {
        NSString *assertMessage = [NSString stringWithFormat:@"'%@' is not a system localized string.", string];
        
        // Throw exception in debug builds if string is not a system localized string.
        NSCAssert(NO, assertMessage);
        
        // Assign localizedString to string so release builds simply return the input string.
        localizedString = string;
    }
    
    return localizedString;
}

@end
