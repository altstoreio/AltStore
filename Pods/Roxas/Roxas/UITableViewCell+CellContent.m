//
//  UITableViewCell+CellContent.m
//  Roxas
//
//  Created by Riley Testut on 2/20/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "UITableViewCell+CellContent.h"

@implementation UITableViewCell (CellContent)

+ (nullable instancetype)instantiateWithNib:(UINib *)nib
{
    NSArray *contents = [nib instantiateWithOwner:nil options:nil];
    
    UITableViewCell *cell = [contents firstObject];
    return cell;
}

+ (UINib *)nib
{
    NSString *className = NSStringFromClass(self);
    
    // Handle Swift names that are prefixed with module name
    NSArray<NSString *> *components = [className componentsSeparatedByString:@"."];
    
    UINib *nib = [UINib nibWithNibName:components.lastObject bundle:[NSBundle bundleForClass:self]];
    return nib;
}

@end
