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
#include <libimobiledevice/misagent.h>

void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *udid);

NSErrorDomain const ALTDeviceErrorDomain = @"com.rileytestut.ALTDeviceError";

@interface ALTDeviceManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(NSError *)> *installationCompletionHandlers;
@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, NSProgress *> *installationProgress;
@property (nonatomic, readonly) dispatch_queue_t installationQueue;

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
        
        _installationQueue = dispatch_queue_create("com.rileytestut.AltServer.InstallationQueue", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:4];
    
    dispatch_async(self.installationQueue, ^{
        NSUUID *UUID = [NSUUID UUID];
        __block char *uuidString = (char *)malloc(UUID.UUIDString.length + 1);
        strncpy(uuidString, (const char *)UUID.UUIDString.UTF8String, UUID.UUIDString.length);
        uuidString[UUID.UUIDString.length] = '\0';
        
        __block idevice_t device = NULL;
        __block lockdownd_client_t client = NULL;
        __block instproxy_client_t ipc = NULL;
        __block afc_client_t afc = NULL;
        __block misagent_client_t mis = NULL;
        __block lockdownd_service_descriptor_t service = NULL;
        
        NSURL *removedProfilesDirectoryURL = [[[NSFileManager defaultManager] temporaryDirectory] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        
        void (^finish)(NSError *error) = ^(NSError *error) {
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:removedProfilesDirectoryURL.path isDirectory:nil])
            {
                // Reinstall all provisioning profiles we removed before installation.
                
                NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:removedProfilesDirectoryURL.path error:nil];
                for (NSString *filename in contents)
                {
                    NSURL *fileURL = [removedProfilesDirectoryURL URLByAppendingPathComponent:filename];
                    
                    ALTProvisioningProfile *provisioningProfile = [[ALTProvisioningProfile alloc] initWithURL:fileURL];
                    if (provisioningProfile == nil)
                    {
                        continue;
                    }
                    
                    plist_t pdata = plist_new_data((const char *)provisioningProfile.data.bytes, provisioningProfile.data.length);
                    
                    if (misagent_install(mis, pdata) == MISAGENT_E_SUCCESS)
                    {
                        NSLog(@"Reinstalled profile: %@", provisioningProfile.identifier);
                    }
                    else
                    {
                        int code = misagent_get_status_code(mis);
                        NSLog(@"Failed to reinstall provisioning profile %@. (%@)", provisioningProfile.identifier, @(code));
                    }
                }
                
                [[NSFileManager defaultManager] removeItemAtURL:removedProfilesDirectoryURL error:nil];
            }
            
            instproxy_client_free(ipc);
            afc_client_free(afc);
            lockdownd_client_free(client);
            misagent_client_free(mis);
            idevice_free(device);
            lockdownd_service_descriptor_free(service);
            
            free(uuidString);
            uuidString = NULL;
            
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
            NSLog(@"Unzipping .ipa...");
            
            temporaryDirectoryURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
            
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:temporaryDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error])
            {
                return finish(error);
            }
            
            appBundleURL = [[NSFileManager defaultManager] unzipAppBundleAtURL:fileURL toDirectory:temporaryDirectoryURL error:&error];
            if (appBundleURL == nil)
            {
                return finish(error);
            }
        }
        else
        {
            return finish([NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSURLErrorKey: fileURL}]);
        }
        
        /* Find Device */
        if (idevice_new(&device, udid.UTF8String) != IDEVICE_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        /* Connect to Device */
        if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        /* Connect to Installation Proxy */
        if ((lockdownd_start_service(client, "com.apple.mobile.installation_proxy", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (instproxy_client_new(device, service, &ipc) != INSTPROXY_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (service)
        {
            lockdownd_service_descriptor_free(service);
            service = NULL;
        }
        
        /* Connect to AFC service */
        if ((lockdownd_start_service(client, "com.apple.afc", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (afc_client_new(device, service, &afc) != AFC_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        NSURL *stagingURL = [NSURL fileURLWithPath:@"PublicStaging" isDirectory:YES];
        
        /* Prepare for installation */
        char **files = NULL;
        if (afc_get_file_info(afc, stagingURL.relativePath.fileSystemRepresentation, &files) != AFC_E_SUCCESS)
        {
            if (afc_make_directory(afc, stagingURL.relativePath.fileSystemRepresentation) != AFC_E_SUCCESS)
            {
                return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceWriteFailed userInfo:nil]);
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
        
        NSLog(@"Writing to device...");
        
        plist_t options = instproxy_client_options_new();
        instproxy_client_options_add(options, "PackageType", "Developer", NULL);
        
        NSURL *destinationURL = [stagingURL URLByAppendingPathComponent:appBundleURL.lastPathComponent];
        
        // Writing files to device should be worth 3/4 of total work.
        [progress becomeCurrentWithPendingUnitCount:3];
        
        NSError *writeError = nil;
        if (![self writeDirectory:appBundleURL toDestinationURL:destinationURL client:afc progress:nil error:&writeError])
        {
            return finish(writeError);
        }
        
        NSLog(@"Finished writing to device.");
        
        /* Provisioning Profiles */
        NSURL *provisioningProfileURL = [appBundleURL URLByAppendingPathComponent:@"embedded.mobileprovision"];
        ALTProvisioningProfile *installationProvisioningProfile = [[ALTProvisioningProfile alloc] initWithURL:provisioningProfileURL];
        if (installationProvisioningProfile != nil)
        {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:removedProfilesDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error])
            {
                return finish(error);
            }

            if ((lockdownd_start_service(client, "com.apple.misagent", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
            {
                return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
            }

            if (misagent_client_new(device, service, &mis) != MISAGENT_E_SUCCESS)
            {
                return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
            }

            plist_t profiles = NULL;
            if (misagent_copy_all(mis, &profiles) != MISAGENT_E_SUCCESS)
            {
                return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
            }

            uint32_t profileCount = plist_array_get_size(profiles);
            for (int i = 0; i < profileCount; i++)
            {
                plist_t profile = plist_array_get_item(profiles, i);
                if (plist_get_node_type(profile) != PLIST_DATA)
                {
                    continue;
                }

                char *bytes = NULL;
                uint64_t length = 0;

                plist_get_data_val(profile, &bytes, &length);
                if (bytes == NULL)
                {
                    continue;
                }

                NSData *data = [NSData dataWithBytes:(const void *)bytes length:length];
                ALTProvisioningProfile *provisioningProfile = [[ALTProvisioningProfile alloc] initWithData:data];

                if (![provisioningProfile.teamIdentifier isEqualToString:installationProvisioningProfile.teamIdentifier])
                {
                    continue;
                }

                NSString *filename = [NSString stringWithFormat:@"%@.mobileprovision", [[NSUUID UUID] UUIDString]];
                NSURL *fileURL = [removedProfilesDirectoryURL URLByAppendingPathComponent:filename];

                NSError *copyError = nil;
                if (![provisioningProfile.data writeToURL:fileURL options:NSDataWritingAtomic error:&copyError])
                {
                    NSLog(@"Failed to copy profile to temporary URL. %@", copyError);
                    continue;
                }

                if (misagent_remove(mis, provisioningProfile.identifier.UTF8String) == MISAGENT_E_SUCCESS)
                {
                    NSLog(@"Removed provisioning profile: %@", provisioningProfile.identifier);
                }
                else
                {
                    int code = misagent_get_status_code(mis);
                    NSLog(@"Failed to remove provisioning profile %@. Error Code: %@", provisioningProfile.identifier, @(code));
                }
            }

            lockdownd_client_free(client);
            client = NULL;
        }
        
        NSProgress *installationProgress = [NSProgress progressWithTotalUnitCount:100 parent:progress pendingUnitCount:1];
        
        self.installationProgress[UUID] = installationProgress;
        self.installationCompletionHandlers[UUID] = ^(NSError *error) {
            finish(error);
            
            if (temporaryDirectoryURL != nil)
            {
                NSError *error = nil;
                if (![[NSFileManager defaultManager] removeItemAtURL:temporaryDirectoryURL error:&error])
                {
                    NSLog(@"Error removing temporary directory. %@", error);
                }
            }
        };
        
        NSLog(@"Installing to device %@...", udid);
        
        instproxy_install(ipc, destinationURL.relativePath.fileSystemRepresentation, options, ALTDeviceManagerUpdateStatus, uuidString);
        instproxy_client_options_free(options);
    });
        
    return progress;
}

- (BOOL)writeDirectory:(NSURL *)directoryURL toDestinationURL:(NSURL *)destinationURL client:(afc_client_t)afc progress:(NSProgress *)progress error:(NSError **)error
{
    afc_make_directory(afc, destinationURL.relativePath.fileSystemRepresentation);
    
    if (progress == nil)
    {
        NSDirectoryEnumerator *countEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryURL
                                                                      includingPropertiesForKeys:@[]
                                                                                         options:0
                                                                                    errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
                                                                                        if (error) {
                                                                                            NSLog(@"[Error] %@ (%@)", error, url);
                                                                                            return NO;
                                                                                        }
                                                                                        
                                                                                        return YES;
                                                                                    }];
        
        NSInteger totalCount = 0;
        for (NSURL *__unused fileURL in countEnumerator)
        {
            totalCount++;
        }
        
        progress = [NSProgress progressWithTotalUnitCount:totalCount];
    }
    
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
            if (![self writeDirectory:fileURL toDestinationURL:destinationDirectoryURL client:afc progress:progress error:error])
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
        
        progress.completedUnitCount += 1;
    }
    
    return YES;
}

- (BOOL)writeFile:(NSURL *)fileURL toDestinationURL:(NSURL *)destinationURL client:(afc_client_t)afc error:(NSError **)error
{
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:fileURL.path];
    if (fileHandle == nil)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{NSURLErrorKey: fileURL}];
        }
        
        return NO;
    }
    
    NSData *data = [fileHandle readDataToEndOfFile];

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
        
        if (afc_file_write(afc, af, (const char *)data.bytes + bytesWritten, (uint32_t)data.length - bytesWritten, &count) != AFC_E_SUCCESS)
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
    NSMutableArray *connectedDevices = [NSMutableArray array];
    
    int count = 0;
    char **udids = NULL;
    if (idevice_get_device_list(&udids, &count) < 0)
    {
        fprintf(stderr, "ERROR: Unable to retrieve device list!\n");
        return @[];
    }
    
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
        int result = lockdownd_client_new(device, &client, "altserver");
        if (result != LOCKDOWN_E_SUCCESS)
        {
            fprintf(stderr, "ERROR: Connecting to device %s failed! (%d)\n", udid, result);
            
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

void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *uuid)
{
    NSUUID *UUID = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:(const char *)uuid]];
    
    NSProgress *progress = ALTDeviceManager.sharedManager.installationProgress[UUID];
    if (progress == nil)
    {
        return;
    }
    
    int percent = -1;
    instproxy_status_get_percent_complete(status, &percent);
    
    char *name = NULL;
    char *description = NULL;
    uint64_t code = 0;
    instproxy_status_get_error(status, &name, &description, &code);
    
    if ((percent == -1 && progress.completedUnitCount > 0) || code != 0)
    {
        void (^completionHandler)(NSError *) = ALTDeviceManager.sharedManager.installationCompletionHandlers[UUID];
        if (completionHandler != nil)
        {
            if (code != 0)
            {
                NSLog(@"Error installing app. %@ (%@). %@", @(code), @(name), @(description));
                
                NSError *error = nil;
                
                if (code == 3892346913)
                {
                    error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorMaximumFreeAppLimitReached userInfo:nil];
                }
                else
                {
                    NSError *underlyingError = [NSError errorWithDomain:AltServerInstallationErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: @(description)}];
                    
                    error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorInstallationFailed userInfo:@{NSUnderlyingErrorKey: underlyingError}];
                }
                
                completionHandler(error);
            }
            else
            {
                NSLog(@"Finished installing app!");
                completionHandler(nil);
            }
            
            ALTDeviceManager.sharedManager.installationCompletionHandlers[UUID] = nil;
            ALTDeviceManager.sharedManager.installationProgress[UUID] = nil;
        }
    }
    else if (progress.completedUnitCount < percent)
    {
        progress.completedUnitCount = percent;
        
        NSLog(@"Installation Progress: %@", @(percent));
    }
}
