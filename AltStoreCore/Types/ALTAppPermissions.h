//
//  ALTAppPermissions.h
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NSString *ALTAppPermissionType NS_TYPED_EXTENSIBLE_ENUM;
extern ALTAppPermissionType const ALTAppPermissionTypeUnknown;
extern ALTAppPermissionType const ALTAppPermissionTypeEntitlement;
extern ALTAppPermissionType const ALTAppPermissionTypePrivacy;
typedef NSString *ALTAppPrivacyPermission NS_TYPED_EXTENSIBLE_ENUM;
