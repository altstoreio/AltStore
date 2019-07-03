//
//  ALTConnection.m
//  AltServer-Windows
//
//  Created by Riley Testut on 7/2/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTConnection.h"
#import "ALTDeviceManager.h"

static void *ALTConnectionContext = &ALTConnectionContext;

@interface ALTConnection () <NSStreamDelegate>

@property (nonatomic, nullable) NSRunLoop *backgroundRunLoop;

@property (nonatomic, strong) NSMutableData *inputData;
@property (nonatomic, strong) NSMutableData *outputData;

@property (nonatomic, strong) dispatch_queue_t receivingQueue;
@property (nonatomic, strong, nullable) dispatch_semaphore_t receivingSemaphore;

@property (nonatomic, strong) dispatch_queue_t sendingQueue;
@property (nonatomic, strong, nullable) dispatch_semaphore_t sendingSemaphore;
@property (nonatomic, getter=isSending) BOOL sending;
@property (nonatomic, strong, nullable) NSProgress *sendingProgress;

@end

@implementation ALTConnection

- (instancetype)initWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream
{
    self = [super init];
    if (self)
    {
        _inputStream = inputStream;
        _inputStream.delegate = self;
        
        _outputStream = outputStream;
        _outputStream.delegate = self;
        
        _inputData = [NSMutableData data];
        _outputData = [NSMutableData data];
        
        _receivingQueue = dispatch_queue_create("com.rileytestut.AltServer.receivingQueue", DISPATCH_QUEUE_SERIAL);
        _sendingQueue = dispatch_queue_create("com.rileytestut.AltServer.sendingQueue", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (void)dealloc
{
    [self disconnect];
}

- (void)disconnect
{
    [self.backgroundRunLoop performBlock:^{
        [self.inputStream removeFromRunLoop:self.backgroundRunLoop forMode:NSDefaultRunLoopMode];
        [self.outputStream removeFromRunLoop:self.backgroundRunLoop forMode:NSDefaultRunLoopMode];
        
        [self.inputStream close];
        [self.outputStream close];
        
        CFRunLoopStop(CFRunLoopGetCurrent());
    }];
}

- (void)processAppRequestWithCompletion:(void (^)(BOOL, NSError * _Nonnull))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        self.backgroundRunLoop = [NSRunLoop currentRunLoop];
        
        [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [self.inputStream open];
        [self.outputStream open];
        
        [self _processAppRequestWithCompletion:completion];
        
        [self.backgroundRunLoop run];
    });
}

- (void)_processAppRequestWithCompletion:(void (^)(BOOL, NSError * _Nonnull))completion
{
    [self receiveAppWithCompletion:^(NSDictionary *request, NSURL *fileURL, NSError *error) {
        if (fileURL == nil)
        {
            return [self finishWithError:error];
        }
        
        NSString *UDID = request[@"udid"];
        NSLog(@"Awaiting begin installation request for device %@...", UDID);
        
        [self receiveRequestWithCompletion:^(NSDictionary *request, NSError *error) {
            if (request == nil)
            {
                return [self finishWithError:error];
            }
            
            [self installAppAtFileURL:fileURL toDeviceWithUDID:UDID completion:^(BOOL success, NSError *error) {
                [self finishWithError:error];
            }];
        }];
    }];
}

- (void)installAppAtFileURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)UDID completion:(void (^)(BOOL success, NSError *error))completion
{
    self.sending = NO;
    
    self.sendingProgress = [[ALTDeviceManager sharedManager] installAppAtURL:fileURL toDeviceWithUDID:UDID completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success)
        {
            NSLog(@"Successfully installed app!");
            completion(YES, nil);
        }
        else
        {
            NSLog(@"Failed to install app. %@", error);
            completion(NO, error);
        }
        
        [self.sendingProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted)) context:ALTConnectionContext];
        self.sendingProgress = nil;
    }];
    
    [self.sendingProgress addObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted)) options:0 context:ALTConnectionContext];
}

- (void)finishWithError:(NSError *)error
{
    NSMutableDictionary *response = [@{@"version": @1,
                                       @"identifier": @"ServerResponse",
                                       @"progress": @1.0} mutableCopy];
    
    if (error != nil)
    {
        NSLog(@"Failed to process request from device. %@", error);
        response[@"errorCode"] = @(error.code);
    }
    else
    {
        NSLog(@"Processed request!");
    }
    
    [self sendResponse:response completion:^(BOOL success, NSError *error) {
        NSLog(@"Sent response to device with error: %@", error);
        
        [self disconnect];
    }];
}

#pragma mark - KVO -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (context != ALTConnectionContext)
    {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    NSProgress *progress = (NSProgress *)object;
    
    dispatch_async(self.sendingQueue, ^{
        if ([self isSending])
        {
            return;
        }
        
        self.sending = YES;
        
        NSLog(@"Progress: %@", @(progress.fractionCompleted));
        
        NSDictionary *response = @{@"version": @1,
                                   @"identifier": @"ServerResponse",
                                   @"progress": @(progress.fractionCompleted)};
        
        [self sendResponse:response completion:^(BOOL success, NSError *error) {
            dispatch_async(self.sendingQueue, ^{
                self.sending = NO;
            });
        }];
    });
}

#pragma mark - Sending & Receiving -

- (void)receiveAppWithCompletion:(void (^)(NSDictionary *request, NSURL *fileURL, NSError *error))completion
{
    [self receiveDataWithSize:-1 completion:^(NSData *data, NSError *error) {
        if (error != nil)
        {
            completion(nil, nil, error);
            return;
        }
        
        NSError *parseError = nil;
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (request == nil)
        {
            completion(nil, nil, parseError);
            return;
        }
        
        NSNumber *appSize = request[@"contentSize"]; //TODO: Errors
        NSLog(@"Receiving app (%@ bytes)...", appSize);
        
        [self receiveDataWithSize:[appSize integerValue] completion:^(NSData *data, NSError *error) {
            if (error != nil)
            {
                completion(nil, nil, error);
                return;
            }
            
            NSString *filename = [NSString stringWithFormat:@"%@.ipa", [NSUUID UUID]];
            NSURL *temporaryURL = [[[NSFileManager defaultManager] temporaryDirectory] URLByAppendingPathComponent:filename];
            
            NSError *writeError = nil;
            if (![data writeToURL:temporaryURL options:NSDataWritingAtomic error:&writeError])
            {
                completion(nil, nil, writeError);
                return;
            }
            
            completion(request, temporaryURL, nil);
        }];
    }];
}

- (void)receiveRequestWithCompletion:(void (^)(NSDictionary *request, NSError *error))completion
{
    [self receiveDataWithSize:-1 completion:^(NSData *data, NSError *error) {
        if (error != nil)
        {
            completion(nil, error);
            return;
        }
        
        NSError *parseError = nil;
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (request == nil)
        {
            completion(nil, parseError);
            return;
        }
        
        completion(request, nil);
    }];
}

- (void)receiveDataWithSize:(NSInteger)size completion:(void (^)(NSData *data, NSError *error))completion
{
    if (size == -1)
    {
        // Unknown size, so retrieve size first.
        NSInteger size = sizeof(uint32_t);
        
        NSLog(@"Receiving request size...");
        [self receiveDataWithSize:size completion:^(NSData *data, NSError *error) {
            if (error != nil)
            {
                completion(nil, error);
                return;
            }
            
            NSInteger expectedBytes = *((int32_t *)data.bytes);
            NSLog(@"Receiving %@ bytes...", @(expectedBytes));
            
            [self receiveDataWithSize:expectedBytes completion:completion];
        }];
    }
    else
    {
        dispatch_async(self.receivingQueue, ^{
            if (self.inputStream.streamError != nil)
            {
                completion(nil, self.inputStream.streamError);
                return;
            }
            
            if (self.inputData.length >= size)
            {
                NSData *data = [self.inputData subdataWithRange:NSMakeRange(0, size)];
                completion(data, nil);
                
                [self.inputData replaceBytesInRange:NSMakeRange(0, size) withBytes:NULL length:0];
            }
            else
            {
                self.receivingSemaphore = dispatch_semaphore_create(0);
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    dispatch_semaphore_wait(self.receivingSemaphore, DISPATCH_TIME_FOREVER);
                    self.receivingSemaphore = nil;
                    
                    [self receiveDataWithSize:size completion:completion];
                });
            }
        });
    }
}

- (void)sendResponse:(NSDictionary *)response completion:(void (^)(BOOL success, NSError *error))completion
{
    NSError *serializationError = nil;
    NSData *responseData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&serializationError];
    if (responseData == nil)
    {
        completion(NO, serializationError);
        return;
    }
    
    int32_t size = (int32_t)responseData.length;
    NSData *responseSizeData = [NSData dataWithBytes:&size length:sizeof(int32_t)];
    [self sendData:responseSizeData completion:^(BOOL success, NSError *error) {
        if (!success)
        {
            completion(NO, error);
            return;
        }
        
        [self sendData:responseData completion:^(BOOL success, NSError *error) {
            if (!success)
            {
                completion(NO, error);
                return;
            }
            
            completion(YES, nil);
        }];
    }];
}

- (void)sendData:(NSData *)data completion:(void (^)(BOOL success, NSError *error))completion
{
    if (self.outputStream.hasSpaceAvailable)
    {
        self.sendingSemaphore = dispatch_semaphore_create(0);
        
        NSInteger writtenBytes = [self.outputStream write:[data bytes] maxLength:data.length];
        
        if (self.outputStream.streamError != nil)
        {
            completion(NO, self.outputStream.streamError);
            return;
        }
        
        if (writtenBytes == data.length)
        {
            completion(YES, nil);
        }
        else
        {
            NSData *subdata = [data subdataWithRange:NSMakeRange(writtenBytes, data.length - writtenBytes)];
            data = nil;
            
            [self sendData:subdata completion:completion];
        }
    }
    else
    {
        dispatch_semaphore_wait(self.sendingSemaphore, DISPATCH_TIME_FOREVER);
    }
}

#pragma mark - <NSStreamDelegate> -

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode)
    {
    case NSStreamEventHasBytesAvailable:
        {
            dispatch_async(self.receivingQueue, ^{
                uint8_t buffer[1024];
                NSInteger length = [(NSInputStream *)stream read:buffer maxLength:1024];
                [self.inputData appendBytes:(const void *)buffer length:length];
                
                if (self.receivingSemaphore)
                {
                    dispatch_semaphore_signal(self.receivingSemaphore);
                }
            });
            
            break;
        }
            
    case NSStreamEventNone: break;
    case NSStreamEventOpenCompleted: break;
    case NSStreamEventHasSpaceAvailable:
        {
            if (self.sendingSemaphore)
            {
                dispatch_semaphore_signal(self.sendingSemaphore);
            }
            
            break;
        }
    case NSStreamEventErrorOccurred:
        {
            if (stream == self.inputStream)
            {
                if (self.receivingSemaphore)
                {
                    dispatch_semaphore_signal(self.receivingSemaphore);
                }
            }
            else if (stream == self.outputStream)
            {
                if (self.sendingSemaphore)
                {
                    dispatch_semaphore_signal(self.sendingSemaphore);
                }
            }
            
            break;
        }
            
    case NSStreamEventEndEncountered: break;
    }
}

@end
