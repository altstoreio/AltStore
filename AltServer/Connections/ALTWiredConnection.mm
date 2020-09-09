//
//  ALTWiredConnection.m
//  AltServer
//
//  Created by Riley Testut on 1/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#import "ALTWiredConnection+Private.h"

#import "ALTConnection.h"
#import "NSError+ALTServerError.h"

@implementation ALTWiredConnection

- (instancetype)initWithDevice:(ALTDevice *)device connection:(idevice_connection_t)connection
{
    self = [super init];
    if (self)
    {
        _device = [device copy];
        _connection = connection;
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnect];
}

- (void)disconnect
{
    if (![self isConnected])
    {
        return;
    }
    
    idevice_disconnect(self.connection);
    _connection = nil;
    
    self.connected = NO;
}

- (void)sendData:(NSData *)data completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    void (^finish)(NSError *error) = ^(NSError *error) {
        if (error != nil)
        {
            NSLog(@"Send Error: %@", error);
            completionHandler(NO, error);
        }
        else
        {
            completionHandler(YES, nil);
        }
    };
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableData *mutableData = [data mutableCopy];
        while (mutableData.length > 0)
        {
            uint32_t sentBytes = 0;
            if (idevice_connection_send(self.connection, (const char *)mutableData.bytes, (int32_t)mutableData.length, &sentBytes) != IDEVICE_E_SUCCESS)
            {
                return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorLostConnection userInfo:nil]);
            }
            
            [mutableData replaceBytesInRange:NSMakeRange(0, sentBytes) withBytes:NULL length:0];
        }
        
        finish(nil);
    });
}

- (void)receiveDataWithExpectedSize:(NSInteger)expectedSize completionHandler:(void (^)(NSData * _Nullable, NSError * _Nullable))completionHandler
{
    void (^finish)(NSData *data, NSError *error) = ^(NSData *data, NSError *error) {
        if (error != nil)
        {
            NSLog(@"Receive Data Error: %@", error);
        }
        
        completionHandler(data, error);
    };
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char bytes[4096];
        NSMutableData *receivedData = [NSMutableData dataWithCapacity:expectedSize];
        
        while (receivedData.length < expectedSize)
        {
            uint32_t size = MIN(4096, (uint32_t)expectedSize - (uint32_t)receivedData.length);
            
            uint32_t receivedBytes = 0;
            if (idevice_connection_receive_timeout(self.connection, bytes, size, &receivedBytes, 10000) != IDEVICE_E_SUCCESS)
            {
                return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorLostConnection userInfo:nil]);
            }
            
            NSData *data = [NSData dataWithBytesNoCopy:bytes length:receivedBytes freeWhenDone:NO];
            [receivedData appendData:data];
        }
        
        finish(receivedData, nil);
    });
}

#pragma mark - NSObject -

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ (Wired)", self.device.name];
}

@end
