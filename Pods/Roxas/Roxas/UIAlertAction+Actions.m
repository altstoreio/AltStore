//
//  UIAlertAction+Actions.m
//  Roxas
//
//  Created by Riley Testut on 5/9/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "UIAlertAction+Actions.h"
#import "NSString+Localization.h"

@implementation UIAlertAction (Actions)

+ (UIAlertAction *)okAction
{
    return [UIAlertAction actionWithTitle:RSTSystemLocalizedString(@"OK") style:UIAlertActionStyleDefault handler:nil];
}

+ (UIAlertAction *)cancelAction
{
    return [UIAlertAction actionWithTitle:RSTSystemLocalizedString(@"Cancel") style:UIAlertActionStyleCancel handler:nil];
}

@end
