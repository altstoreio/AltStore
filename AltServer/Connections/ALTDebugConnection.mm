//
//  ALTDebugConnection.m
//  AltServer
//
//  Created by Riley Testut on 2/19/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#import "ALTDebugConnection+Private.h"

#import "NSError+ALTServerError.h"
#import "NSError+libimobiledevice.h"

char *bin2hex(const unsigned char *bin, size_t length)
{
    if (bin == NULL || length == 0)
    {
        return NULL;
    }

    char *hex = (char *)malloc(length * 2 + 1);
    for (size_t i = 0; i < length; i++)
    {
        hex[i * 2] = "0123456789ABCDEF"[bin[i] >> 4];
        hex[i * 2 + 1] = "0123456789ABCDEF"[bin[i] & 0x0F];
    }
    hex[length * 2] = '\0';

    return hex;
}

@implementation ALTDebugConnection

- (instancetype)initWithDevice:(ALTDevice *)device
{
    self = [super init];
    if (self)
    {
        _device = device;
        _connectionQueue = dispatch_queue_create_with_target("io.altstore.AltServer.DebugConnection",
                                                             DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL,
                                                             dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnect];
}

- (void)disconnect
{
    if (_client == nil)
    {
        return;
    }
    
    debugserver_client_free(_client);
    _client = nil;
}

- (void)connectWithCompletionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler
{
    __block idevice_t device = NULL;
    
    void (^finish)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        if (device)
        {
            idevice_free(device);
        }
        
        completionHandler(success, error);
    };
    
    dispatch_async(self.connectionQueue, ^{
        /* Find Device */
        if (idevice_new_with_options(&device, self.device.identifier.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish(NO, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
                
        /* Connect to debugserver */
        debugserver_client_t client = NULL;
        debugserver_error_t error = debugserver_client_start_service(device, &client, "AltServer");
        if (error != DEBUGSERVER_E_SUCCESS)
        {
            return finish(NO, [NSError errorWithDebugServerError:error device:self.device]);
        }
        
        self.client = client;
        
        finish(YES, nil);
    });
}

- (void)enableUnsignedCodeExecutionForProcessWithName:(NSString *)processName completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler
{
    dispatch_async(self.connectionQueue, ^{
        NSString *localizedFailure = [NSString stringWithFormat:NSLocalizedString(@"JIT could not be enabled for %@.", comment: @""), processName];
        
        NSString *encodedName = @(bin2hex((const unsigned char *)processName.UTF8String, (size_t)strlen(processName.UTF8String)));
        NSString *attachCommand = [NSString stringWithFormat:@"vAttachName;%@", encodedName];
        
        NSError *error = nil;
        if (![self sendCommand:attachCommand arguments:nil error:&error])
        {
            NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
            userInfo[ALTAppNameErrorKey] = processName;
            userInfo[ALTDeviceNameErrorKey] = self.device.name;
            userInfo[NSLocalizedFailureErrorKey] = localizedFailure;
            
            NSError *returnError = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
            return completionHandler(NO, returnError);
        }
        
        NSString *detachCommand = @"D";
        if (![self sendCommand:detachCommand arguments:nil error:&error])
        {
            NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
            userInfo[ALTAppNameErrorKey] = processName;
            userInfo[ALTDeviceNameErrorKey] = self.device.name;
            userInfo[NSLocalizedFailureErrorKey] = localizedFailure;
            
            NSError *returnError = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
            return completionHandler(NO, returnError);
        }
        
        completionHandler(YES, nil);
    });
}

#pragma mark - Private -

- (BOOL)sendCommand:(NSString *)command arguments:(nullable NSArray<NSString *> *)arguments error:(NSError **)error
{
    int argc = (int)arguments.count;
    char **argv = new char*[argc + 1];
    
    for (int i = 0; i < argc; i++)
    {
        NSString *argument = arguments[i];
        argv[i] = (char *)argument.UTF8String;
    }
    
    argv[argc] = NULL;
    
    debugserver_command_t debugCommand = NULL;
    debugserver_command_new(command.UTF8String, argc, argv, &debugCommand);
    
    delete[] argv;
    
    char *response = NULL;
    size_t responseSize = 0;
    debugserver_error_t debugServerError = debugserver_client_send_command(self.client, debugCommand, &response, &responseSize);
    debugserver_command_free(debugCommand);
    
    if (debugServerError != DEBUGSERVER_E_SUCCESS)
    {
        if (error)
        {
            *error = [NSError errorWithDebugServerError:debugServerError device:self.device];
        }
        
        return NO;
    }
        
    if (![self processResponse:@(response) error:error])
    {
        return NO;
    }
    
    return YES;
}

- (BOOL)processResponse:(NSString *)rawResponse error:(NSError **)error
{
    if (rawResponse.length == 0 || [rawResponse isEqualToString:@"OK"])
    {
        return YES;
    }
    
    char type = [rawResponse characterAtIndex:0];
    NSString *response = [rawResponse substringFromIndex:1];
    
    switch (type)
    {
        case 'O':
        {
            // stdout/stderr
            
            char *decodedResponse = NULL;
            debugserver_decode_string(response.UTF8String, response.length, &decodedResponse);
            
            NSLog(@"Response: %@", @(decodedResponse));
            
            if (decodedResponse)
            {
                free(decodedResponse);
            }
            
            return YES;
        }
            
        case 'T':
        {
            // Thread Information
            
            NSLog(@"Thread stopped. Details:\n%s", response.UTF8String + 1);
            return YES;
        }
            
        case 'E':
        {
            // Error
            
            if (error)
            {
                NSInteger errorCode = [[[response componentsSeparatedByString:@";"] firstObject] integerValue];
                
                switch (errorCode)
                {
                    case 96:
                        *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorRequestedAppNotRunning userInfo:nil];
                        break;
                        
                    default:
                        *error = [NSError errorWithDomain:AltServerConnectionErrorDomain code:ALTServerConnectionErrorUnknown userInfo:@{NSLocalizedFailureReasonErrorKey: response}];
                        break;
                }
            }
            
            return NO;
        }
            
        case 'W':
        {
            // Warning
            
            NSLog(@"WARNING: %@", response);
            return YES;
        }
    }
    
    return YES;
}

@end
