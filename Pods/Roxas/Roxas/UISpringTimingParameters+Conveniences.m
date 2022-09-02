//
//  UISpringTimingParameters+Conveniences.m
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "UISpringTimingParameters+Conveniences.h"

const RSTSpringStiffness RSTSpringStiffnessDefault = 750.0;

// Retrieved via private APIs. https://twitter.com/rileytestut/statuses/754924747046080512
const RSTSpringStiffness RSTSpringStiffnessSystem = 1000.0;

@implementation UISpringTimingParameters (Conveniences)

- (instancetype)initWithMass:(CGFloat)mass stiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio
{
    return [self initWithMass:mass stiffness:stiffness dampingRatio:dampingRatio initialVelocity:CGVectorMake(0, 0)];
}

- (instancetype)initWithMass:(CGFloat)mass stiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio initialVelocity:(CGVector)initialVelocity
{
    // The damping coefficient necessary to prevent oscillations and return to equilibrium in the minimum amount of time.
    CGFloat criticalDamping = 2 * sqrt((double)mass * (double)stiffness);
    
    // The damping coefficient necessary to achieve the requested dampingRatio.
    // The damping ratio is simply the ratio between the system's damping and its critical damping.
    CGFloat damping = dampingRatio * criticalDamping;
    
    self = [self initWithMass:mass stiffness:stiffness damping:damping initialVelocity:CGVectorMake(0, 0)];
    return self;
}

- (instancetype)initWithStiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio
{
    return [self initWithStiffness:stiffness dampingRatio:dampingRatio initialVelocity:CGVectorMake(0, 0)];
}

- (instancetype)initWithStiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio initialVelocity:(CGVector)initialVelocity
{
    CGFloat mass = 3.0;
    
    return [self initWithMass:mass stiffness:stiffness dampingRatio:dampingRatio initialVelocity:initialVelocity];
}

@end


@implementation UIViewPropertyAnimator (SpringConveniences)

- (instancetype)initWithSpringTimingParameters:(UISpringTimingParameters *)timingParameters animations:(void (^)(void))animations
{    
    self = [self initWithDuration:0 timingParameters:timingParameters];
    if (self)
    {
        if (animations)
        {
            [self addAnimations:animations];
        }
    }
    
    return self;
}

@end
