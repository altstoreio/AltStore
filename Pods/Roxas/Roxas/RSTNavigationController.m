//
//  RSTNavigationController.m
//  Roxas
//
//  Created by Riley Testut on 11/5/14.
//  Copyright (c) 2014 Riley Testut. All rights reserved.
//

#import "RSTNavigationController.h"

@interface RSTNavigationController ()

@end

@implementation RSTNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Rotation -

- (BOOL)shouldAutorotate
{
    return [self.topViewController shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return [self.topViewController preferredInterfaceOrientationForPresentation];
}

@end


RSTNavigationController *RSTContainInNavigationController(UIViewController *viewController)
{
    RSTNavigationController *navigationController = [[RSTNavigationController alloc] initWithRootViewController:viewController];
    return navigationController;
}