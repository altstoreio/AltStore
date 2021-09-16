//
//  UISpringTimingParameters+Conveniences.h
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

typedef CGFloat RSTSpringStiffness NS_TYPED_EXTENSIBLE_ENUM;

RST_EXTERN const RSTSpringStiffness RSTSpringStiffnessDefault NS_SWIFT_NAME(RSTSpringStiffness.default);
RST_EXTERN const RSTSpringStiffness RSTSpringStiffnessSystem NS_SWIFT_NAME(RSTSpringStiffness.system);

@interface UISpringTimingParameters (Conveniences)

- (instancetype)initWithMass:(CGFloat)mass stiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio;
- (instancetype)initWithMass:(CGFloat)mass stiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio initialVelocity:(CGVector)initialVelocity;

- (instancetype)initWithStiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio;
- (instancetype)initWithStiffness:(RSTSpringStiffness)stiffness dampingRatio:(CGFloat)dampingRatio initialVelocity:(CGVector)initialVelocity;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface UIViewPropertyAnimator (SpringConveniences)

- (instancetype)initWithSpringTimingParameters:(UISpringTimingParameters *)timingParameters animations:(void (^ __nullable)(void))animations;

@end

NS_ASSUME_NONNULL_END
