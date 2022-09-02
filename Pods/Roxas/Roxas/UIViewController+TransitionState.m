//
//  UIViewController+TransitionState.m
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "UIViewController+TransitionState.h"

@implementation UIViewController (TransitionState)

- (BOOL)isAppearing
{
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = self.transitionCoordinator;
    UIViewController *toViewController = [transitionCoordinator viewControllerForKey:UITransitionContextToViewControllerKey];
    UIViewController *fromViewController = [transitionCoordinator viewControllerForKey:UITransitionContextFromViewControllerKey];
    
    BOOL isAppearing = [toViewController isEqualToViewControllerOrAncestor:self];
    return isAppearing && ![fromViewController isKindOfClass:[UIAlertController class]];
}

- (BOOL)isDisappearing
{
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = self.transitionCoordinator;
    UIViewController *fromViewController = [transitionCoordinator viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionCoordinator viewControllerForKey:UITransitionContextToViewControllerKey];
    
    BOOL isDisappearing = [fromViewController isEqualToViewControllerOrAncestor:self];
    return isDisappearing && ![toViewController isKindOfClass:[UIAlertController class]];
}

- (BOOL)isEqualToViewControllerOrAncestor:(UIViewController *)viewController
{
    BOOL isEqual = NO;
    
    while (viewController != nil)
    {
        if (self == viewController)
        {
            isEqual = YES;
            break;
        }
        
        viewController = viewController.parentViewController;
    }
    
    return isEqual;
}

@end
