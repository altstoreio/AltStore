//
//  RSTLaunchViewController.m
//  Roxas
//
//  Created by Riley Testut on 3/24/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTLaunchViewController.h"
#import "RSTHelperFile.h"
#import "NSLayoutConstraint+Edges.h"

@implementation RSTLaunchCondition

- (instancetype)initWithCondition:(BOOL (^)(void))condition action:(void (^)(void (^completionHandler)(NSError *_Nullable error)))action
{
    self = [super init];
    if (self)
    {
        _condition = [condition copy];
        _action = [action copy];
    }
    
    return self;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface RSTLaunchViewController ()

@property (nonatomic, nullable) UIView *launchView;

@end

NS_ASSUME_NONNULL_END


@implementation RSTLaunchViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSString *storyboardName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UILaunchStoryboardName"];
    if (storyboardName == nil)
    {
        return;
    }
    
    if ([[NSBundle mainBundle] URLForResource:storyboardName withExtension:@"nib"] != nil)
    {
        UINib *launchNib = [UINib nibWithNibName:storyboardName bundle:[NSBundle mainBundle]];
        
        NSArray *objects = [launchNib instantiateWithOwner:nil options:nil];
        
        for (UIView *view in objects)
        {
            if ([view isKindOfClass:[UIView class]])
            {
                self.launchView = view;
                break;
            }
        }
    }
    else
    {
        UIStoryboard *launchStoryboard = [UIStoryboard storyboardWithName:storyboardName bundle:[NSBundle mainBundle]];
        
        UIViewController *initialViewController = [launchStoryboard instantiateInitialViewController];
        self.launchView = initialViewController.view;
    }
    
    if (self.launchView == nil)
    {
        return;
    }
    
    [self.view addSubview:self.launchView pinningEdgesWithInsets:UIEdgeInsetsZero];
    [self.view sendSubviewToBack:self.launchView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self handleLaunchConditions];
}

#pragma mark - RSTLaunchViewController -

- (void)handleLaunchConditions
{
    [self handleLaunchConditionAtIndex:0];
}

- (void)handleLaunchConditionAtIndex:(NSInteger)index
{
    if (![NSThread isMainThread])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleLaunchConditionAtIndex:index];
        });
        
        return;
    }
    
    if (index >= self.launchConditions.count)
    {
        [self finishLaunching];
        
        return;
    }
        
    RSTLaunchCondition *condition = self.launchConditions[index];
    
    if (condition.condition())
    {
        [self handleLaunchConditionAtIndex:index + 1];
    }
    else
    {
        condition.action(^(NSError *_Nullable error) {
            if (error != nil)
            {
                rst_dispatch_sync_on_main_thread(^{
                    [self handleLaunchError:error];
                });
                
                return;
            }
            
            [self handleLaunchConditionAtIndex:index + 1];
        });
    }
}

- (void)handleLaunchError:(NSError *)error
{
    DLog(@"Launch Error: %@", [error localizedDescription]);
}

- (void)finishLaunching
{
}

@end
