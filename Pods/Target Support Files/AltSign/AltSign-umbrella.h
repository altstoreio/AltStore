#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "AltSign.h"
#import "ALTAppleAPI.h"
#import "ALTAppleAPISession.h"
#import "ALTAppleAPI_Private.h"
#import "ALTCapabilities.h"
#import "NSError+ALTErrors.h"
#import "NSFileManager+Apps.h"
#import "ALTApplication.h"
#import "ALTAccount.h"
#import "ALTAnisetteData.h"
#import "ALTAppGroup.h"
#import "ALTAppID.h"
#import "ALTCertificate.h"
#import "ALTCertificateRequest.h"
#import "ALTDevice.h"
#import "ALTModel+Internal.h"
#import "ALTProvisioningProfile.h"
#import "ALTTeam.h"
#import "ALTSigner.h"

FOUNDATION_EXPORT double AltSignVersionNumber;
FOUNDATION_EXPORT const unsigned char AltSignVersionString[];

