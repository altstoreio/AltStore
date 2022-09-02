//
//  UICollectionViewCell+Nibs.m
//  Roxas
//
//  Created by Riley Testut on 8/3/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "UICollectionViewCell+Nibs.h"

@implementation UICollectionViewCell (Nibs)

+ (instancetype)instantiateWithNib:(UINib *)nib;
{
    NSArray *contents = [nib instantiateWithOwner:nil options:nil];
    
    UICollectionViewCell *cell = [contents firstObject];
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
