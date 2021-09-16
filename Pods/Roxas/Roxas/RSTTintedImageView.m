//
//  RSTTintedImageView.m
//  Roxas
//
//  Created by Riley Testut on 8/29/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTTintedImageView.h"

@implementation RSTTintedImageView

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // When loading from nib, the image is not tinted with the tint color.
    // To fix this, we set the tint color to nil, then back to the original tint color.
    
    UIColor *tintColor = self.tintColor;
    self.tintColor = nil;
    self.tintColor = tintColor;
}

@end
