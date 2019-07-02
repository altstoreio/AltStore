//
//  ViewController.m
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ViewController.h"
#import "ALTConnectionManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (IBAction)start
{
    [[ALTConnectionManager sharedManager] start];
}


@end
