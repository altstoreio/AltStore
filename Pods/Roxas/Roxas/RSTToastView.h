//
//  RSTToastView.h
//  Roxas
//
//  Created by Riley Testut on 5/2/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

typedef NS_ENUM(NSInteger, RSTViewEdge) {
    RSTViewEdgeNone,
    RSTViewEdgeTop,
    RSTViewEdgeBottom,
    RSTViewEdgeLeft,
    RSTViewEdgeRight
};

NS_ASSUME_NONNULL_BEGIN

RST_EXTERN NSNotificationName const RSTToastViewWillShowNotification NS_SWIFT_NAME(RSTToastView.willShowNotification);
RST_EXTERN NSNotificationName const RSTToastViewDidShowNotification NS_SWIFT_NAME(RSTToastView.didShowNotification);
RST_EXTERN NSNotificationName const RSTToastViewWillDismissNotification NS_SWIFT_NAME(RSTToastView.willDismissNotification);
RST_EXTERN NSNotificationName const RSTToastViewDidDismissNotification NS_SWIFT_NAME(RSTToastView.didDismissNotification);

typedef NSString *RSTToastViewUserInfoKey NS_TYPED_EXTENSIBLE_ENUM;

RST_EXTERN RSTToastViewUserInfoKey const RSTToastViewUserInfoKeyPropertyAnimator;

NS_CLASS_AVAILABLE_IOS(11_0)
@interface RSTToastView : UIControl

@property (null_resettable, nonatomic) UIColor *tintColor UI_APPEARANCE_SELECTOR;

@property (nonatomic, readonly) UILabel *textLabel;
@property (nonatomic, readonly) UILabel *detailTextLabel;
@property (nonatomic, readonly) UIActivityIndicatorView *activityIndicatorView;

@property (nonatomic) RSTViewEdge presentationEdge UI_APPEARANCE_SELECTOR;
@property (nonatomic) RSTViewEdge alignmentEdge UI_APPEARANCE_SELECTOR;

@property (nonatomic) UIOffset edgeOffset;

@property (nonatomic, readonly, getter=isShown) BOOL shown;

- (instancetype)initWithText:(NSString *)text detailText:(nullable NSString *)detailedText NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithError:(NSError *)error;

- (void)showInView:(UIView *)view;
- (void)showInView:(UIView *)view duration:(NSTimeInterval)duration;

- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
