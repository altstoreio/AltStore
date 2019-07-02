//
//  ALTConnectionManager.m
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTConnectionManager.h"
#include <dns_sd.h>

void ALTConnectionManagerBonjourRegistrationFinished(DNSServiceRef service, DNSServiceFlags flags, DNSServiceErrorType errorCode, const char *name, const char *regtype, const char *domain, void *context)
{
    NSLog(@"Registered service: %s (Error: %@)", name, @(errorCode));
}

static void ALTConnectionManagerSocketCallback(CFSocketRef cfs, CFSocketCallBackType callbackType, CFDataRef address, const void *data, void *context)
{
    DNSServiceRef service = (DNSServiceRef)context;
    DNSServiceErrorType processResult = DNSServiceProcessResult(service);
    
    if (processResult != kDNSServiceErr_NoError)
    {
        NSLog(@"Bonjour Registration Processing Error: %@", @(processResult));
        return;
    }
    else
    {
        NSLog(@"Recevied callback!");
    }
}

@interface ALTConnectionManager ()

@property (nonatomic) CFSocketRef mDNSResponderSocket;

@end

@implementation ALTConnectionManager

+ (ALTConnectionManager *)sharedManager
{
    static ALTConnectionManager *_manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _manager = [[self alloc] init];
    });
    
    return _manager;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
    }
    
    return self;
}

- (void)start
{
    DNSServiceRef service = NULL;
    uint16_t port = htons(13112);
    
    DNSServiceErrorType registrationResult = DNSServiceRegister(&service, 0, 0, NULL, "_altserver._tcp", NULL, NULL, port, 0, NULL, ALTConnectionManagerBonjourRegistrationFinished, NULL);
    if (registrationResult != kDNSServiceErr_NoError)
    {
        NSLog(@"Bonjour Registration Error: %@", @(registrationResult));
        return;
    }
    
    dnssd_sock_t dnssd_socket = DNSServiceRefSockFD(service);
    if (dnssd_socket == -1)
    {
        NSLog(@"Failed to retrieve mDNSResponder socket.");
        return;
    }
    
    CFSocketContext socketContext = { 0, service, NULL, NULL, NULL };
    self.mDNSResponderSocket = CFSocketCreateWithNative(kCFAllocatorDefault, dnssd_socket, kCFSocketReadCallBack, ALTConnectionManagerSocketCallback, &socketContext);
    CFRunLoopSourceRef runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.mDNSResponderSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(runLoopSource);
}

@end
