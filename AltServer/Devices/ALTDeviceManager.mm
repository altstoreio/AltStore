//
//  ALTDeviceManager.m
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTDeviceManager.h"
#import "NSError+ALTServerError.h"

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/installation_proxy.h>
#include <libimobiledevice/notification_proxy.h>
#include <libimobiledevice/afc.h>

void ALTDeviceManagerDidFinishAppInstallation(const char *notification, void *udid);
void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *udid);

NSErrorDomain const ALTDeviceErrorDomain = @"com.rileytestut.ALTDeviceError";

@interface ALTDeviceManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(void)> *installationCompletionHandlers;
@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, NSProgress *> *installationProgress;

@end

@implementation ALTDeviceManager

+ (ALTDeviceManager *)sharedManager
{
    static ALTDeviceManager *_manager = nil;
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
        _installationCompletionHandlers = [NSMutableDictionary dictionary];
        _installationProgress = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];
    
    NSUUID *UUID = [NSUUID UUID];
    char *uuidString = (char *)malloc(UUID.UUIDString.length + 1);
    strncpy(uuidString, (const char *)UUID.UUIDString.UTF8String, UUID.UUIDString.length);
    
    idevice_t device = NULL;
    lockdownd_client_t client = NULL;
    instproxy_client_t ipc = NULL;
    np_client_t np = NULL;
    afc_client_t afc = NULL;
    lockdownd_service_descriptor_t service = NULL;
    
    void (^finish)(NSError *error) = ^(NSError *error) {
        np_client_free(np);
        instproxy_client_free(ipc);
        afc_client_free(afc);
        lockdownd_client_free(client);
        idevice_free(device);
        lockdownd_service_descriptor_free(service);
        
        free(uuidString);
        
        if (error != nil)
        {
            completionHandler(NO, error);
        }
        else
        {
            completionHandler(YES, nil);
        }
    };
    
    NSURL *appBundleURL = nil;
    NSURL *temporaryDirectoryURL = nil;
    
    if ([fileURL.pathExtension.lowercaseString isEqualToString:@"app"])
    {
        appBundleURL = fileURL;
        temporaryDirectoryURL = nil;
    }
    else if ([fileURL.pathExtension.lowercaseString isEqualToString:@"ipa"])
    {
        temporaryDirectoryURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
        
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:temporaryDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error])
        {
            finish(error);
            return progress;
        }
        
        appBundleURL = [[NSFileManager defaultManager] unzipAppBundleAtURL:fileURL toDirectory:temporaryDirectoryURL error:&error];
        if (appBundleURL == nil)
        {
            finish(error);
            return progress;
        }
    }
    else
    {
        finish([NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSURLErrorKey: fileURL}]);
        return progress;
    }
    
    /* Find Device */
    if (idevice_new(&device, udid.UTF8String) != IDEVICE_E_SUCCESS)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        return progress;
    }
    
    /* Connect to Device */
    if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    /* Connect to Notification Proxy */
    if ((lockdownd_start_service(client, "com.apple.mobile.notification_proxy", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    if (np_client_new(device, service, &np) != NP_E_SUCCESS)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    np_set_notify_callback(np, ALTDeviceManagerDidFinishAppInstallation, uuidString);
    
    const char *notifications[3] = { NP_APP_INSTALLED, NP_APP_UNINSTALLED, NULL };
    np_observe_notifications(np, notifications);
    
    if (service)
    {
        lockdownd_service_descriptor_free(service);
        service = NULL;
    }
    
    /* Connect to Installation Proxy */
    if ((lockdownd_start_service(client, "com.apple.mobile.installation_proxy", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    if (instproxy_client_new(device, service, &ipc) != INSTPROXY_E_SUCCESS)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    if (service)
    {
        lockdownd_service_descriptor_free(service);
        service = NULL;
    }
    
    lockdownd_service_descriptor_free(service);
    service = NULL;
    
    /* Connect to AFC service */
    if ((lockdownd_start_service(client, "com.apple.afc", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    lockdownd_client_free(client);
    client = NULL;
    
    if (afc_client_new(device, service, &afc) != AFC_E_SUCCESS)
    {
        finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        return progress;
    }
    
    NSURL *stagingURL = [NSURL fileURLWithPath:@"PublicStaging" isDirectory:YES];
    
    /* Prepare for installation */
    char **files = NULL;
    if (afc_get_file_info(afc, stagingURL.relativePath.fileSystemRepresentation, &files) != AFC_E_SUCCESS)
    {
        if (afc_make_directory(afc, stagingURL.relativePath.fileSystemRepresentation) != AFC_E_SUCCESS)
        {
            finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceWriteFailed userInfo:nil]);
            return progress;
        }
    }
    
    if (files)
    {
        int i = 0;
        
        while (files[i])
        {
            free(files[i]);
            i++;
        }
        
        free(files);
    }
    
    plist_t options = instproxy_client_options_new();
    instproxy_client_options_add(options, "PackageType", "Developer", NULL);
    
    NSURL *destinationURL = [stagingURL URLByAppendingPathComponent:appBundleURL.lastPathComponent];
    
    NSError *writeError = nil;
    if (![self writeDirectory:appBundleURL toDestinationURL:destinationURL client:afc error:&writeError])
    {
        finish(writeError);
        return progress;
    }
    
    self.installationProgress[UUID] = progress;
    self.installationCompletionHandlers[UUID] = ^{
        finish(nil);
        
        if (temporaryDirectoryURL != nil)
        {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:temporaryDirectoryURL error:&error])
            {
                NSLog(@"Error removing temporary directory. %@", error);
            }
        }
    };
    
    instproxy_install(ipc, destinationURL.relativePath.fileSystemRepresentation, options, ALTDeviceManagerUpdateStatus, uuidString);
    instproxy_client_options_free(options);
        
    return progress;
}

- (BOOL)writeDirectory:(NSURL *)directoryURL toDestinationURL:(NSURL *)destinationURL client:(afc_client_t)afc error:(NSError **)error
{
    afc_make_directory(afc, destinationURL.relativePath.fileSystemRepresentation);
    
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryURL
                                                             includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                                options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                           errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
                                                                               if (error) {
                                                                                   NSLog(@"[Error] %@ (%@)", error, url);
                                                                                   return NO;
                                                                               }
                                                                               
                                                                               return YES;
                                                                           }];
    
    for (NSURL *fileURL in enumerator)
    {
        NSNumber *isDirectory = nil;
        if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error])
        {
            return NO;
        }
        
        if ([isDirectory boolValue])
        {
            NSURL *destinationDirectoryURL = [destinationURL URLByAppendingPathComponent:fileURL.lastPathComponent isDirectory:YES];
            if (![self writeDirectory:fileURL toDestinationURL:destinationDirectoryURL client:afc error:error])
            {
                return NO;
            }
        }
        else
        {
            NSURL *destinationFileURL = [destinationURL URLByAppendingPathComponent:fileURL.lastPathComponent isDirectory:NO];
            if (![self writeFile:fileURL toDestinationURL:destinationFileURL client:afc error:error])
            {
                return NO;
            }
        }
    }
    
    return YES;
}

- (BOOL)writeFile:(NSURL *)fileURL toDestinationURL:(NSURL *)destinationURL client:(afc_client_t)afc error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:error];
    if (data == nil)
    {
        return NO;
    }
    
    uint64_t af = 0;
    if ((afc_file_open(afc, destinationURL.relativePath.fileSystemRepresentation, AFC_FOPEN_WRONLY, &af) != AFC_E_SUCCESS) || af == 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSURLErrorKey: destinationURL}];
        }
        
        return NO;
    }
    
    BOOL success = YES;
    uint32_t bytesWritten = 0;
    
    while (bytesWritten < data.length)
    {
        uint32_t count = 0;
        if (afc_file_write(afc, af, (const char *)data.bytes, (uint32_t)data.length, &bytesWritten) != AFC_E_SUCCESS)
        {
            if (error)
            {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSURLErrorKey: destinationURL}];
            }
            
            success = NO;
            break;
        }
        
        bytesWritten += count;
    }
    
    if (bytesWritten != data.length)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSURLErrorKey: destinationURL}];
        }
        
        success = NO;
    }
    
    afc_file_close(afc, af);
    
    return success;
}

#pragma mark - Getters -

- (NSArray<ALTDevice *> *)connectedDevices
{
    int count = 0;
    char **udids = NULL;
    
    if (idevice_get_device_list(&udids, &count) < 0)
    {
        fprintf(stderr, "ERROR: Unable to retrieve device list!\n");
        return @[];
    }
    
    NSMutableArray *connectedDevices = [NSMutableArray array];
    
    for (int i = 0; i < count; i++)
    {
        char *udid = udids[i];
        
        idevice_t device = NULL;
        idevice_new(&device, udid);
        
        if (!device)
        {
            fprintf(stderr, "ERROR: No device with UDID %s attached.\n", udid);
            continue;
        }
        
        lockdownd_client_t client = NULL;
        if (lockdownd_client_new(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            fprintf(stderr, "ERROR: Connecting to device failed!\n");
            
            idevice_free(device);
            
            continue;
        }
        
        char *device_name = NULL;
        if (lockdownd_get_device_name(client, &device_name) != LOCKDOWN_E_SUCCESS || device_name == NULL)
        {
            fprintf(stderr, "ERROR: Could not get device name!\n");
            
            lockdownd_client_free(client);
            idevice_free(device);
            
            continue;
        }
        
        lockdownd_client_free(client);
        idevice_free(device);
        
        NSString *name = [NSString stringWithCString:device_name encoding:NSUTF8StringEncoding];
        NSString *identifier = [NSString stringWithCString:udid encoding:NSUTF8StringEncoding];
        
        ALTDevice *altDevice = [[ALTDevice alloc] initWithName:name identifier:identifier];
        [connectedDevices addObject:altDevice];
        
        if (device_name != NULL)
        {
            free(device_name);
        }
    }
    
    idevice_device_list_free(udids);
    
    return connectedDevices;
}

@end

#pragma mark - Callbacks -

void ALTDeviceManagerDidFinishAppInstallation(const char *notification, void *udid)
{
    NSUUID *UUID = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:(const char *)udid]];
    
    void (^completionHandler)(void) = ALTDeviceManager.sharedManager.installationCompletionHandlers[UUID];
    if (completionHandler != nil)
    {
        completionHandler();
        ALTDeviceManager.sharedManager.installationCompletionHandlers[UUID] = nil;
        ALTDeviceManager.sharedManager.installationProgress[UUID] = nil;
    }
}

void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *udid)
{
    NSUUID *UUID = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:(const char *)udid]];
    
    NSProgress *progress = ALTDeviceManager.sharedManager.installationProgress[UUID];
    if (progress == nil)
    {
        return;
    }
    
    int percent = -1;
    instproxy_status_get_percent_complete(status, &percent);
    
    if (progress.completedUnitCount < percent)
    {
        progress.completedUnitCount = percent;
    }
    
    NSLog(@"Installation Progress: %@", @(percent));
}
