//
//  UIViewController+TransitionState.h
//  Roxas
//
//  Created by Riley Testut on 3/14/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

@import UIKit;

@interface UIViewController (TransitionState)

// Unlike isBeingPresented and isBeingDismissed, these actually work ಠ_ಠ
@property (nonatomic, readonly, getter=isAppearing) BOOL appearing;
@property (nonatomic, readonly, getter=isDisappearing) BOOL disappearing;

@end
