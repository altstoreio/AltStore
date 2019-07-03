//
//  ALTConnectionManager.m
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTConnectionManager.h"
#import "ALTConnection.h"

#include <CoreFoundation/CoreFoundation.h>

#include <dns_sd.h>
#include <sys/socket.h>
#include <netinet/in.h>

@interface ALTConnectionManager ()

@property (nonatomic) CFSocketRef mDNSResponderSocket;
@property (nonatomic, readonly) NSMutableSet<ALTConnection *> *connections;

@end

void ALTConnectionManagerBonjourRegistrationFinished(DNSServiceRef service, DNSServiceFlags flags, DNSServiceErrorType errorCode, const char *name, const char *regtype, const char *domain, void *context)
{
    NSLog(@"Registered service: %s (Error: %@)", name, @(errorCode));
}

void ALTConnectionManagerSocketCallback(CFSocketRef cfs, CFSocketCallBackType callbackType, CFDataRef address, const void *data, void *context)
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

void ALTConnectionManagerListeningSocketCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *context)
{
    if (type != kCFSocketAcceptCallBack)
    {
        return;
    }
    
    CFSocketNativeHandle nativeSocket = *((CFSocketNativeHandle *)data);
    
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocket, &readStream, &writeStream);
    if (readStream == NULL || writeStream == NULL)
    {
        NSLog(@"Failed to create NSStream pair with socket %@.", @(nativeSocket));
        return;
    }
    
    NSInputStream *inputStream = (NSInputStream *)CFBridgingRelease(readStream);
    [inputStream setProperty:(NSNumber *)kCFBooleanTrue forKey:(NSStreamPropertyKey)kCFStreamPropertyShouldCloseNativeSocket];
    
    NSOutputStream *outputStream = (NSOutputStream *)CFBridgingRelease(writeStream);
    [outputStream setProperty:(NSNumber *)kCFBooleanTrue forKey:(NSStreamPropertyKey)kCFStreamPropertyShouldCloseNativeSocket];
    
    ALTConnection *connection = [[ALTConnection alloc] initWithInputStream:inputStream outputStream:outputStream];
//    [connection connect];
    [[ALTConnectionManager sharedManager].connections addObject:connection];
}

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
        _connections = [NSMutableSet set];
    }
    
    return self;
}

- (void)start
{
    /* IPv4 */
    CFSocketRef socket4 = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, ALTConnectionManagerListeningSocketCallback, NULL);
    
    struct sockaddr_in sin4;
    memset(&sin4, 0, sizeof(sin4));
    sin4.sin_len = sizeof(sin4);
    sin4.sin_family = AF_INET;
    sin4.sin_port = 0; // Choose for us.
    sin4.sin_addr.s_addr = INADDR_ANY;
    
    CFDataRef sin4Data = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&sin4, sizeof(sin4));
    CFSocketSetAddress(socket4, sin4Data);
    CFRelease(sin4Data);
    
    NSData *address4 = (NSData *)CFBridgingRelease(CFSocketCopyAddress(socket4));
    memcpy(&sin4, [address4 bytes], [address4 length]);
    int port4 = ntohs(sin4.sin_port);
    
    CFRunLoopSourceRef source4 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket4, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source4, kCFRunLoopDefaultMode);
//
//    /* IPv6 */
//    CFSocketRef socket6 = CFSocketCreate(kCFAllocatorDefault, PF_INET6, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, ALTConnectionManagerListeningSocketCallback, NULL);
//
//    struct sockaddr_in6 sin6;
//    memset(&sin6, 0, sizeof(sin6));
//    sin6.sin6_len = sizeof(sin6);
//    sin6.sin6_family = AF_INET6;
//    sin6.sin6_port = 0;
//    sin6.sin6_addr = in6addr_any;
//
//    CFDataRef sin6Data = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&sin6, sizeof(sin6));
//    CFSocketSetAddress(socket6, sin6Data);
//    CFRelease(sin6Data);
//
//    NSData *address6 = (NSData *)CFBridgingRelease(CFSocketCopyAddress(socket6));
//    memcpy(&sin6, [address6 bytes], [address6 length]);
//    int port6 = ntohs(sin6.sin6_port);
//
//    CFRunLoopSourceRef source6 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket6, 0);
//    CFRunLoopAddSource(CFRunLoopGetCurrent(), source6, kCFRunLoopDefaultMode);
//
    [self startAdvertisingServiceWithPort:port4];
}

- (void)startAdvertisingServiceWithPort:(int)socketPort
{
    DNSServiceRef service = NULL;
    uint16_t port = htons(socketPort);
    
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
