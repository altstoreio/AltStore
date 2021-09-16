//
//  UIView+AnimatedHide.m
//  Roxas
//
//  Created by Riley Testut on 8/27/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "UIView+AnimatedHide.h"

@implementation UIView (AnimatedHide)

- (void)setHidden:(BOOL)hidden animated:(BOOL)animated
{
    if (!animated)
    {
        [self setHidden:hidden];
        return;
    }
    
    if (self.hidden == hidden)
    {
        return;
    }
    
    CGFloat alpha = self.alpha;
    
    if (hidden)
    {
        [UIView animateWithDuration:0.4 animations:^{
            self.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.alpha = alpha;
            self.hidden = YES;
        }];
    }
    else
    {
        self.alpha = 0.0;
        self.hidden = NO;
        
        [UIView animateWithDuration:0.4 animations:^{
            self.alpha = alpha;
        }];
    }
}

@end
