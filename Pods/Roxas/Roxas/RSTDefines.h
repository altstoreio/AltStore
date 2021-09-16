//
//  RSTDefines.h
//  Roxas
//
//  Created by Riley Testut on 12/6/14.
//  Copyright (c) 2014 Riley Testut. All rights reserved.
//

#ifndef Roxas_RSTDefines_h
#define Roxas_RSTDefines_h

#if defined(__cplusplus)
#define RST_EXTERN extern "C"
#else
#define RST_EXTERN extern
#endif

/*** Logging ***/

// http://stackoverflow.com/questions/969130/how-to-print-out-the-method-name-and-line-number-and-conditionally-disable-nslog
#ifdef DEBUG
#   define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#   define DLog(...)
#endif

// ALog always displays output regardless of the DEBUG setting
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

#ifdef DEBUG
#   define ULog(fmt, ...)  { UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%s\n [Line %d] ", __PRETTY_FUNCTION__, __LINE__] message:[NSString stringWithFormat:fmt, ##__VA_ARGS__]  delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]; [alert show]; }
#else
#   define ULog(...)
#endif

#define ELog(error) NSLog(@"%s [Line %d] Error:\n%@\n%@\n%@", __PRETTY_FUNCTION__, __LINE__, [error localizedDescription], [error localizedRecoverySuggestion], [error userInfo])

#endif
