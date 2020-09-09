//
//  ALTNotificationConnection.m
//  AltServer
//
//  Created by Riley Testut on 1/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#import "ALTNotificationConnection+Private.h"

#import "NSError+ALTServerError.h"

void ALTDeviceReceivedNotification(const char *notification, void *user_data);

@implementation ALTNotificationConnection

- (instancetype)initWithDevice:(ALTDevice *)device client:(np_client_t)client
{
    self = [super init];
    if (self)
    {
        _device = [device copy];
        _client = client;
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnect];
}

- (void)disconnect
{
    np_client_free(self.client);
    _client = nil;
}

- (void)startListeningForNotifications:(NSArray<NSString *> *)notifications completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const char **notificationNames = (const char **)malloc((notifications.count + 1) * sizeof(char *));
        for (int i = 0; i < notifications.count; i++)
        {
            NSString *name = notifications[i];
            notificationNames[i] = name.UTF8String;
        }
        notificationNames[notifications.count] = NULL; // Must have terminating NULL entry.
        
        np_error_t result = np_observe_notifications(self.client, notificationNames);
        if (result != NP_E_SUCCESS)
        {
            return completionHandler(NO, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorLostConnection userInfo:nil]);
        }
        
        result = np_set_notify_callback(self.client, ALTDeviceReceivedNotification, (__bridge void *)self);
        if (result != NP_E_SUCCESS)
        {
            return completionHandler(NO, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorLostConnection userInfo:nil]);
        }
        
        completionHandler(YES, nil);
        
        free(notificationNames);
    });
}

- (void)sendNotification:(CFNotificationName)notification completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        np_error_t result = np_post_notification(self.client, [(__bridge NSString *)notification UTF8String]);
        if (result == NP_E_SUCCESS)
        {
            completionHandler(YES, nil);
        }
        else
        {
            completionHandler(NO, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorLostConnection userInfo:nil]);
        }
    });
}

@end

void ALTDeviceReceivedNotification(const char *notification, void *user_data)
{
    ALTNotificationConnection *connection = (__bridge ALTNotificationConnection *)user_data;
    
    if (connection.receivedNotificationHandler)
    {
        connection.receivedNotificationHandler((__bridge CFNotificationName)@(notification));
    }
}
