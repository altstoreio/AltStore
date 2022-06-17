//
//  ALTDeviceManager.m
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTDeviceManager.h"

#import "ALTWiredConnection+Private.h"
#import "ALTNotificationConnection+Private.h"
#import "ALTDebugConnection+Private.h"

#import "ALTConstants.h"
#import "NSError+ALTServerError.h"
#import "NSError+libimobiledevice.h"

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import "AltServer-Swift.h"

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/installation_proxy.h>
#include <libimobiledevice/notification_proxy.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/misagent.h>
#include <libimobiledevice/mobile_image_mounter.h>

void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *udid);
void ALTDeviceManagerUpdateAppDeletionStatus(plist_t command, plist_t status, void *uuid);
void ALTDeviceDidChangeConnectionStatus(const idevice_event_t *event, void *user_data);
ssize_t ALTDeviceManagerUploadFile(void *buffer, size_t size, void *user_data);

NSNotificationName const ALTDeviceManagerDeviceDidConnectNotification = @"ALTDeviceManagerDeviceDidConnectNotification";
NSNotificationName const ALTDeviceManagerDeviceDidDisconnectNotification = @"ALTDeviceManagerDeviceDidDisconnectNotification";

@interface ALTDeviceManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(NSError *)> *installationCompletionHandlers;
@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(NSError *)> *deletionCompletionHandlers;

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, NSProgress *> *installationProgress;

@property (nonatomic, readonly) dispatch_queue_t installationQueue;
@property (nonatomic, readonly) dispatch_queue_t devicesQueue;

@property (nonatomic, readonly) NSMutableSet<ALTDevice *> *cachedDevices;

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
        _deletionCompletionHandlers = [NSMutableDictionary dictionary];
        
        _installationProgress = [NSMutableDictionary dictionary];
        
        _installationQueue = dispatch_queue_create("com.rileytestut.AltServer.Installation", DISPATCH_QUEUE_SERIAL);
        _devicesQueue = dispatch_queue_create("com.rileytestut.AltServer.Devices", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        
        _cachedDevices = [NSMutableSet set];
    }
    
    return self;
}

- (void)start
{
    idevice_event_subscribe(ALTDeviceDidChangeConnectionStatus, nil);
}

#pragma mark - App Installation -

- (NSProgress *)installAppAtURL:(NSURL *)fileURL toDeviceWithUDID:(NSString *)udid activeProvisioningProfiles:(nullable NSSet<NSString *> *)activeProvisioningProfiles completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
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
        
        NSMutableDictionary<NSString *, ALTProvisioningProfile *> *cachedProfiles = [NSMutableDictionary dictionary];
        NSMutableSet<ALTProvisioningProfile *> *installedProfiles = [NSMutableSet set];
        
        void (^finish)(NSError *error) = ^(NSError *e) {
            __block NSError *error = e;
            
            if (activeProvisioningProfiles != nil)
            {
                // Remove installed provisioning profiles if they're not active.
                
                for (ALTProvisioningProfile *installedProfile in installedProfiles)
                {
                    if (![activeProvisioningProfiles containsObject:installedProfile.bundleIdentifier])
                    {
                        NSError *removeError = nil;
                        if (![self removeProvisioningProfile:installedProfile misagent:mis error:&removeError])
                        {
                            if (error == nil)
                            {
                                error = removeError;
                            }
                        }
                    }
                }
            }
            
            [cachedProfiles enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, ALTProvisioningProfile *profile, BOOL * _Nonnull stop) {
                for (ALTProvisioningProfile *installedProfile in installedProfiles)
                {
                    if ([installedProfile.bundleIdentifier isEqualToString:profile.bundleIdentifier])
                    {
                        // Don't reinstall cached profile because it was installed with the app.
                        return;
                    }
                }
                
                NSError *installError = nil;
                if (![self installProvisioningProfile:profile misagent:mis error:&installError])
                {
                    if (error == nil)
                    {
                        error = installError;
                    }
                }
            }];
            
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
        
        ALTApplication *application = [[ALTApplication alloc] initWithFileURL:appBundleURL];
        if (application.provisioningProfile)
        {
            [installedProfiles addObject:application.provisioningProfile];
        }
        
        for (ALTApplication *appExtension in application.appExtensions)
        {
            if (appExtension.provisioningProfile)
            {
                [installedProfiles addObject:appExtension.provisioningProfile];
            }
        }
        
        /* Find Device */
        if (idevice_new_with_options(&device, udid.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
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
        
        
        /* Connect to Misagent */
        // Must connect now, since if we take too long writing files to device, connecting may fail later when managing profiles.
        if (lockdownd_start_service(client, "com.apple.misagent", &service) != LOCKDOWN_E_SUCCESS || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (misagent_client_new(device, service, &mis) != MISAGENT_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
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
            int removeResult = afc_remove_path_and_contents(afc, stagingURL.relativePath.fileSystemRepresentation);
            NSLog(@"Remove staging app result: %@", @(removeResult));
            
            return finish(writeError);
        }
        
        NSLog(@"Finished writing to device.");
        
        if (service)
        {
            lockdownd_service_descriptor_free(service);
            service = NULL;
        }
        
        BOOL shouldManageProfiles = (activeProvisioningProfiles != nil || [application.provisioningProfile isFreeProvisioningProfile]);
        if (shouldManageProfiles)
        {
            // Free developer account was used to sign this app, so we need to remove all
            // provisioning profiles in order to remain under sideloaded app limit.
            
            NSError *error = nil;
            NSDictionary<NSString *, ALTProvisioningProfile *> *removedProfiles = [self removeAllFreeProfilesExcludingBundleIdentifiers:nil misagent:mis error:&error];
            if (removedProfiles == nil)
            {
                return finish(error);
            }
            
            [removedProfiles enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, ALTProvisioningProfile *profile, BOOL * _Nonnull stop) {
                if (activeProvisioningProfiles != nil)
                {
                    if ([activeProvisioningProfiles containsObject:bundleID])
                    {
                        // Only cache active profiles to reinstall afterwards.
                        cachedProfiles[bundleID] = profile;
                    }
                }
                else
                {
                    // Cache all profiles to reinstall afterwards if we didn't provide activeProvisioningProfiles.
                    cachedProfiles[bundleID] = profile;
                }
            }];
        }
        
        lockdownd_client_free(client);
        client = NULL;
        
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
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
            
            dispatch_semaphore_signal(semaphore);
        };
        
        NSLog(@"Installing to device %@...", udid);
        
        instproxy_install(ipc, destinationURL.relativePath.fileSystemRepresentation, options, ALTDeviceManagerUpdateStatus, uuidString);
        instproxy_client_options_free(options);
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
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
            if (![self writeFile:fileURL toDestinationURL:destinationFileURL progress:progress client:afc error:error])
            {
                return NO;
            }
        }
        
        progress.completedUnitCount += 1;
    }
    
    return YES;
}

- (BOOL)writeFile:(NSURL *)fileURL toDestinationURL:(NSURL *)destinationURL progress:(NSProgress *)progress client:(afc_client_t)afc error:(NSError **)error
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
    
    int openResult = afc_file_open(afc, destinationURL.relativePath.fileSystemRepresentation, AFC_FOPEN_WRONLY, &af);
    if (openResult != AFC_E_SUCCESS || af == 0)
    {
        if (openResult == AFC_E_OBJECT_IS_DIR)
        {
            NSLog(@"Treating file as directory: %@ %@", fileURL, destinationURL);
            return [self writeDirectory:fileURL toDestinationURL:destinationURL client:afc progress:progress error:error];
        }
        
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
        
        int writeResult = afc_file_write(afc, af, (const char *)data.bytes + bytesWritten, (uint32_t)data.length - bytesWritten, &count);
        if (writeResult != AFC_E_SUCCESS)
        {
            if (error)
            {
                NSLog(@"Failed writing file with error: %@ (%@ %@)", @(writeResult), fileURL, destinationURL);
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
            NSLog(@"Failed writing file due to mismatched sizes: %@ vs %@ (%@ %@)", @(bytesWritten), @(data.length), fileURL, destinationURL);
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSURLErrorKey: destinationURL}];
        }
        
        success = NO;
    }
    
    afc_file_close(afc, af);
    
    return success;
}

- (void)removeAppForBundleIdentifier:(NSString *)bundleIdentifier fromDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler
{
    __block idevice_t device = NULL;
    __block lockdownd_client_t client = NULL;
    __block instproxy_client_t ipc = NULL;
    __block lockdownd_service_descriptor_t service = NULL;
    
    void (^finish)(NSError *error) = ^(NSError *e) {
        __block NSError *error = e;
        
        lockdownd_service_descriptor_free(service);
        instproxy_client_free(ipc);
        lockdownd_client_free(client);
        idevice_free(device);
        
        if (error != nil)
        {
            completionHandler(NO, error);
        }
        else
        {
            completionHandler(YES, nil);
        }
    };
    
    /* Find Device */
    if (idevice_new_with_options(&device, udid.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
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
    
    NSUUID *UUID = [NSUUID UUID];
    __block char *uuidString = (char *)malloc(UUID.UUIDString.length + 1);
    strncpy(uuidString, (const char *)UUID.UUIDString.UTF8String, UUID.UUIDString.length);
    uuidString[UUID.UUIDString.length] = '\0';
    
    self.deletionCompletionHandlers[UUID] = ^(NSError *error) {
        if (error != nil)
        {
            NSString *localizedFailure = [NSString stringWithFormat:NSLocalizedString(@"Could not remove “%@”.", @""), bundleIdentifier];
            
            NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
            userInfo[NSLocalizedFailureErrorKey] = localizedFailure;
            
            NSError *localizedError = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
            finish(localizedError);
        }
        else
        {
            finish(nil);
        }
        
        free(uuidString);
    };
    
    instproxy_uninstall(ipc, bundleIdentifier.UTF8String, NULL, ALTDeviceManagerUpdateAppDeletionStatus, uuidString);
}

#pragma mark - Provisioning Profiles -

- (void)installProvisioningProfiles:(NSSet<ALTProvisioningProfile *> *)provisioningProfiles toDeviceWithUDID:(NSString *)udid activeProvisioningProfiles:(nullable NSSet<NSString *> *)activeProvisioningProfiles completionHandler:(void (^)(BOOL success, NSError *error))completionHandler
{
    dispatch_async(self.installationQueue, ^{
        __block idevice_t device = NULL;
        __block lockdownd_client_t client = NULL;
        __block afc_client_t afc = NULL;
        __block misagent_client_t mis = NULL;
        __block lockdownd_service_descriptor_t service = NULL;
        
        void (^finish)(NSError *_Nullable) = ^(NSError *error) {
            lockdownd_service_descriptor_free(service);
            misagent_client_free(mis);
            afc_client_free(afc);
            lockdownd_client_free(client);
            idevice_free(device);
            
            completionHandler(error == nil, error);
        };
        
        /* Find Device */
        if (idevice_new_with_options(&device, udid.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        /* Connect to Device */
        if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        /* Connect to Misagent */
        if (lockdownd_start_service(client, "com.apple.misagent", &service) != LOCKDOWN_E_SUCCESS || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (misagent_client_new(device, service, &mis) != MISAGENT_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        NSError *error = nil;
        
        if (activeProvisioningProfiles != nil)
        {
            // Remove all non-active free provisioning profiles.
            
            NSMutableSet *excludedBundleIdentifiers = [activeProvisioningProfiles mutableCopy];
            for (ALTProvisioningProfile *provisioningProfile in provisioningProfiles)
            {
                // Ensure we DO remove old versions of profiles we're about to install, even if they are active.
                [excludedBundleIdentifiers removeObject:provisioningProfile.bundleIdentifier];
            }
            
            if (![self removeAllFreeProfilesExcludingBundleIdentifiers:excludedBundleIdentifiers misagent:mis error:&error])
            {
                return finish(error);
            }
        }
        else
        {
            // Remove only older versions of provisioning profiles we're about to install.
            
            NSMutableSet *bundleIdentifiers = [NSMutableSet set];
            for (ALTProvisioningProfile *provisioningProfile in provisioningProfiles)
            {
                [bundleIdentifiers addObject:provisioningProfile.bundleIdentifier];
            }
            
            if (![self removeProvisioningProfilesForBundleIdentifiers:bundleIdentifiers misagent:mis error:&error])
            {
                return finish(error);
            }
        }
                
        for (ALTProvisioningProfile *provisioningProfile in provisioningProfiles)
        {
            if (![self installProvisioningProfile:provisioningProfile misagent:mis error:&error])
            {
                return finish(error);
            }
        }
        
        finish(nil);
    });
}

- (void)removeProvisioningProfilesForBundleIdentifiers:(NSSet<NSString *> *)bundleIdentifiers fromDeviceWithUDID:(NSString *)udid completionHandler:(void (^)(BOOL success, NSError *error))completionHandler
{
    dispatch_async(self.installationQueue, ^{
        __block idevice_t device = NULL;
        __block lockdownd_client_t client = NULL;
        __block afc_client_t afc = NULL;
        __block misagent_client_t mis = NULL;
        __block lockdownd_service_descriptor_t service = NULL;
        
        void (^finish)(NSError *_Nullable) = ^(NSError *error) {
            lockdownd_service_descriptor_free(service);
            misagent_client_free(mis);
            afc_client_free(afc);
            lockdownd_client_free(client);
            idevice_free(device);
            
            completionHandler(error == nil, error);
        };
        
        /* Find Device */
        if (idevice_new_with_options(&device, udid.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        /* Connect to Device */
        if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        /* Connect to Misagent */
        if (lockdownd_start_service(client, "com.apple.misagent", &service) != LOCKDOWN_E_SUCCESS || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if (misagent_client_new(device, service, &mis) != MISAGENT_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        NSError *error = nil;
        if (![self removeProvisioningProfilesForBundleIdentifiers:bundleIdentifiers misagent:mis error:&error])
        {
            return finish(error);
        }
        
        finish(nil);
    });
}

- (NSDictionary<NSString *, ALTProvisioningProfile *> *)removeProvisioningProfilesForBundleIdentifiers:(NSSet<NSString *> *)bundleIdentifiers misagent:(misagent_client_t)mis error:(NSError **)error
{
    return [self removeAllProfilesForBundleIdentifiers:bundleIdentifiers excludingBundleIdentifiers:nil limitedToFreeProfiles:NO misagent:mis error:error];
}

- (NSDictionary<NSString *, ALTProvisioningProfile *> *)removeAllFreeProfilesExcludingBundleIdentifiers:(nullable NSSet<NSString *> *)bundleIdentifiers misagent:(misagent_client_t)mis error:(NSError **)error
{
    return [self removeAllProfilesForBundleIdentifiers:nil excludingBundleIdentifiers:bundleIdentifiers limitedToFreeProfiles:YES misagent:mis error:error];
}

- (NSDictionary<NSString *, ALTProvisioningProfile *> *)removeAllProfilesForBundleIdentifiers:(nullable NSSet<NSString *> *)includedBundleIdentifiers
                                                                   excludingBundleIdentifiers:(nullable NSSet<NSString *> *)excludedBundleIdentifiers
                                                                        limitedToFreeProfiles:(BOOL)limitedToFreeProfiles
                                                                                     misagent:(misagent_client_t)mis
                                                                                        error:(NSError **)error
{
    NSMutableDictionary<NSString *, ALTProvisioningProfile *> *ignoredProfiles = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, ALTProvisioningProfile *> *removedProfiles = [NSMutableDictionary dictionary];
    
    NSArray<ALTProvisioningProfile *> *provisioningProfiles = [self copyProvisioningProfilesWithClient:mis error:error];
    if (provisioningProfiles == nil)
    {
        return nil;
    }
    
    for (ALTProvisioningProfile *provisioningProfile in provisioningProfiles)
    {
        if (limitedToFreeProfiles && ![provisioningProfile isFreeProvisioningProfile])
        {
            continue;
        }
        
        if (includedBundleIdentifiers != nil && ![includedBundleIdentifiers containsObject:provisioningProfile.bundleIdentifier])
        {
            continue;
        }
        
        if (excludedBundleIdentifiers != nil && [excludedBundleIdentifiers containsObject:provisioningProfile.bundleIdentifier])
        {
            // This provisioning profile has an excluded bundle identifier.
            // Ignore it, unless we've already ignored one with the same bundle identifier,
            // in which case remove whichever profile is the oldest.
            
            ALTProvisioningProfile *previousProfile = ignoredProfiles[provisioningProfile.bundleIdentifier];
            if (previousProfile != nil)
            {
                // We've already ignored a profile with this bundle identifier,
                // so make sure we only ignore the newest one and remove the oldest one.
                BOOL isNewerThanPreviousProfile = ([provisioningProfile.expirationDate compare:previousProfile.expirationDate] == NSOrderedDescending);
                ALTProvisioningProfile *oldestProfile = isNewerThanPreviousProfile ? previousProfile : provisioningProfile;
                ALTProvisioningProfile *newestProfile = isNewerThanPreviousProfile ? provisioningProfile : previousProfile;
                
                ignoredProfiles[provisioningProfile.bundleIdentifier] = newestProfile;
                
                // Don't cache this profile or else it will be reinstalled, so just remove it without caching.
                if (![self removeProvisioningProfile:oldestProfile misagent:mis error:error])
                {
                    return nil;
                }
            }
            else
            {
                ignoredProfiles[provisioningProfile.bundleIdentifier] = provisioningProfile;
            }
            
            continue;
        }
        
        ALTProvisioningProfile *preferredProfile = removedProfiles[provisioningProfile.bundleIdentifier];
        if (preferredProfile != nil)
        {
            if ([provisioningProfile.expirationDate compare:preferredProfile.expirationDate] == NSOrderedDescending)
            {
                removedProfiles[provisioningProfile.bundleIdentifier] = provisioningProfile;
            }
        }
        else
        {
            removedProfiles[provisioningProfile.bundleIdentifier] = provisioningProfile;
        }
        
        if (![self removeProvisioningProfile:provisioningProfile misagent:mis error:error])
        {
            return nil;
        }
    }
    
    return removedProfiles;
}

- (BOOL)installProvisioningProfile:(ALTProvisioningProfile *)provisioningProfile misagent:(misagent_client_t)mis error:(NSError **)error
{
    plist_t pdata = plist_new_data((const char *)provisioningProfile.data.bytes, provisioningProfile.data.length);
    
    misagent_error_t result = misagent_install(mis, pdata);
    plist_free(pdata);
    
    if (result == MISAGENT_E_SUCCESS)
    {
        NSLog(@"Installed profile: %@ (%@)", provisioningProfile.bundleIdentifier, provisioningProfile.UUID);
        return YES;
    }
    else
    {
        int statusCode = misagent_get_status_code(mis);
        NSLog(@"Failed to install provisioning profile %@ (%@). Error Code: %@", provisioningProfile.bundleIdentifier, provisioningProfile.UUID, @(statusCode));
        
        if (error)
        {
            switch (statusCode)
            {
                case -402620383:
                    *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorMaximumFreeAppLimitReached userInfo:nil];
                    break;
                    
                default:
                    NSString *localizedFailure = [NSString stringWithFormat:NSLocalizedString(@"Could not install profile “%@”", @""), provisioningProfile.bundleIdentifier];
                    
                    *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorUnderlyingError userInfo:@{
                        NSLocalizedFailureErrorKey: localizedFailure,
                        ALTUnderlyingErrorCodeErrorKey: [@(statusCode) description],
                        ALTProvisioningProfileBundleIDErrorKey: provisioningProfile.bundleIdentifier
                    }];
            }
        }
        
        return NO;
    }
}

- (BOOL)removeProvisioningProfile:(ALTProvisioningProfile *)provisioningProfile misagent:(misagent_client_t)mis error:(NSError **)error
{
    misagent_error_t result = misagent_remove(mis, provisioningProfile.UUID.UUIDString.lowercaseString.UTF8String);
    if (result == MISAGENT_E_SUCCESS)
    {
        NSLog(@"Removed provisioning profile: %@ (%@)", provisioningProfile.bundleIdentifier, provisioningProfile.UUID);
        return YES;
    }
    else
    {
        int statusCode = misagent_get_status_code(mis);
        NSLog(@"Failed to remove provisioning profile %@ (%@). Error Code: %@", provisioningProfile.bundleIdentifier, provisioningProfile.UUID, @(statusCode));
        
        if (error)
        {
            switch (statusCode)
            {
                case -402620405:
                    *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorProfileNotFound userInfo:nil];
                    break;
                    
                default:
                {
                    NSString *localizedFailure = [NSString stringWithFormat:NSLocalizedString(@"Could not remove profile “%@”", @""), provisioningProfile.bundleIdentifier];
                    
                    *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorUnderlyingError userInfo:@{
                        NSLocalizedFailureErrorKey: localizedFailure,
                        ALTUnderlyingErrorCodeErrorKey: [@(statusCode) description],
                        ALTProvisioningProfileBundleIDErrorKey: provisioningProfile.bundleIdentifier
                    }];
                }
            }
        }
        
        return NO;
    }
}

- (nullable NSArray<ALTProvisioningProfile *> *)copyProvisioningProfilesWithClient:(misagent_client_t)mis error:(NSError **)error
{
    plist_t rawProfiles = NULL;
    misagent_error_t result = misagent_copy_all(mis, &rawProfiles);
    if (result != MISAGENT_E_SUCCESS)
    {
        int statusCode = misagent_get_status_code(mis);
        
        if (error)
        {
            *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorUnderlyingError userInfo:@{
                NSLocalizedFailureErrorKey: NSLocalizedString(@"Could not copy provisioning profiles.", @""),
                ALTUnderlyingErrorCodeErrorKey: [@(statusCode) description]
            }];
        }
        
        return nil;
    }
    
    /* Copy all provisioning profiles */
    
    // For some reason, libplist now fails to parse `rawProfiles` correctly.
    // Specifically, it no longer recognizes the nodes in the plist array as "data" nodes.
    // However, if we encode it as XML then decode it again, it'll work ¯\_(ツ)_/¯
    char *plistXML = nullptr;
    uint32_t plistLength = 0;
    plist_to_xml(rawProfiles, &plistXML, &plistLength);
    
    plist_t profiles = NULL;
    plist_from_xml(plistXML, plistLength, &profiles);
    
    free(plistXML);
    
    NSMutableArray<ALTProvisioningProfile *> *provisioningProfiles = [NSMutableArray array];
        
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

        NSData *data = [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES];
        ALTProvisioningProfile *provisioningProfile = [[ALTProvisioningProfile alloc] initWithData:data];
        if (provisioningProfile == nil)
        {
            continue;
        }
        
        [provisioningProfiles addObject:provisioningProfile];
    }
    
    plist_free(rawProfiles);
    plist_free(profiles);
    
    return provisioningProfiles;
}

#pragma mark - Developer Disk Image -

- (void)isDeveloperDiskImageMountedForDevice:(ALTDevice *)altDevice completionHandler:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    __block idevice_t device = NULL;
    __block instproxy_client_t ipc = NULL;
    __block lockdownd_client_t client = NULL;
    __block lockdownd_service_descriptor_t service = NULL;
    __block mobile_image_mounter_client_t mim = NULL;
    
    __block BOOL isMounted = NO;
        
    void (^finish)(NSError *) = ^(NSError *error) {
        if (mim) {
            mobile_image_mounter_hangup(mim);
            mobile_image_mounter_free(mim);
        }
        
        if (service) {
            lockdownd_service_descriptor_free(service);
        }
        
        if (client) {
            lockdownd_client_free(client);
        }
        
        if (ipc) {
            instproxy_client_free(ipc);
        }
        
        if (device) {
            idevice_free(device);
        }
        
        completionHandler(isMounted, error);
    };
    
    dispatch_async(self.installationQueue, ^{
        
        /* Find Device */
        if (idevice_new_with_options(&device, altDevice.identifier.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        /* Connect to Device */
        if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
                        
        /* Connect to Mobile Image Mounter Proxy */
        if ((lockdownd_start_service(client, "com.apple.mobile.mobile_image_mounter", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        mobile_image_mounter_error_t err = mobile_image_mounter_new(device, service, &mim);
        if (err != MOBILE_IMAGE_MOUNTER_E_SUCCESS)
        {
            return finish([NSError errorWithMobileImageMounterError:err device:altDevice]);
        }
        
        plist_t result = NULL;
        err = mobile_image_mounter_lookup_image(mim, "Developer", &result);
        if (err != MOBILE_IMAGE_MOUNTER_E_SUCCESS)
        {
            return finish([NSError errorWithMobileImageMounterError:err device:altDevice]);
        }
        
        plist_dict_iter it = NULL;
        plist_dict_new_iter(result, &it);
        
        char* key = NULL;
        plist_t subnode = NULL;
        plist_dict_next_item(result, it, &key, &subnode);
        
        while (subnode)
        {
            // If the ImageSignature key in the returned plist contains a subentry the disk image is already uploaded.
            // Hopefully this works for older iOS versions as well.
            // (via https://github.com/Schlaubischlump/LocationSimulator/blob/fdbd93ad16be5f69111b571d71ed6151e850144b/LocationSimulator/MobileDevice/devicemount/deviceimagemounter.c)
            plist_type type = plist_get_node_type(subnode);
            if (strcmp(key, "ImageSignature") == 0 && PLIST_ARRAY == type)
            {
                isMounted = (plist_array_get_size(subnode) != 0);
            }

            free(key);
            key = NULL;
            
            if (isMounted)
            {
                break;
            }
            
            plist_dict_next_item(result, it, &key, &subnode);
        }
        
        free(it);
        
        finish(nil);
    });
}

- (void)installDeveloperDiskImageAtURL:(NSURL *)diskURL signatureURL:(NSURL *)signatureURL toDevice:(ALTDevice *)altDevice
                     completionHandler:(void (^)(BOOL success, NSError *_Nullable error))completionHandler
{
    __block idevice_t device = NULL;
    __block instproxy_client_t ipc = NULL;
    __block lockdownd_client_t client = NULL;
    __block lockdownd_service_descriptor_t service = NULL;
    __block mobile_image_mounter_client_t mim = NULL;
        
    void (^finish)(NSError *) = ^(NSError *error) {
        if (mim) {
            mobile_image_mounter_hangup(mim);
            mobile_image_mounter_free(mim);
        }
        
        if (service) {
            lockdownd_service_descriptor_free(service);
        }
        
        if (client) {
            lockdownd_client_free(client);
        }
        
        if (ipc) {
            instproxy_client_free(ipc);
        }
        
        if (device) {
            idevice_free(device);
        }
        
        if (error)
        {
            error = [error alt_errorWithLocalizedFailure:[NSString stringWithFormat:NSLocalizedString(@"The Developer disk image could not be installed onto %@.", @""), altDevice.name]];
        }
        
        completionHandler(error == nil, error);
    };
    
    dispatch_async(self.installationQueue, ^{
        
        /* Find Device */
        if (idevice_new_with_options(&device, altDevice.identifier.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        /* Connect to Device */
        if (lockdownd_client_new_with_handshake(device, &client, "altserver") != LOCKDOWN_E_SUCCESS)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
                
        /* Connect to Mobile Image Mounter Proxy */
        if ((lockdownd_start_service(client, "com.apple.mobile.mobile_image_mounter", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
        {
            return finish([NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
                
        mobile_image_mounter_error_t err = mobile_image_mounter_new(device, service, &mim);
        if (err != MOBILE_IMAGE_MOUNTER_E_SUCCESS)
        {
            return finish([NSError errorWithMobileImageMounterError:err device:altDevice]);
        }
                
        NSError *error = nil;
        NSDictionary *diskAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:diskURL.path error:&error];
        if (diskAttributes == nil)
        {
            return finish(error);
        }
        
        NSDictionary *signatureAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:signatureURL.path error:&error];
        if (signatureAttributes == nil)
        {
            return finish(error);
        }
        
        size_t diskSize = [diskAttributes fileSize];
        
        NSData *signature = [[NSData alloc] initWithContentsOfURL:signatureURL options:0 error:&error];
        if (signature == nil)
        {
            return finish(error);
        }
        
        FILE *file = fopen(diskURL.fileSystemRepresentation, "rb");
        err = mobile_image_mounter_upload_image(mim, "Developer", diskSize, (const char *)signature.bytes, (size_t)signature.length, ALTDeviceManagerUploadFile, file);
        fclose(file);
        
        if (err != MOBILE_IMAGE_MOUNTER_E_SUCCESS)
        {
            return finish([NSError errorWithMobileImageMounterError:err device:altDevice]);
        }
        
        NSString *diskPath = @"/private/var/mobile/Media/PublicStaging/staging.dimage";

        plist_t result = NULL;
        err = mobile_image_mounter_mount_image(mim, diskPath.UTF8String, (const char *)signature.bytes, (size_t)signature.length, "Developer", &result);
        if (err != MOBILE_IMAGE_MOUNTER_E_SUCCESS)
        {
            return finish([NSError errorWithMobileImageMounterError:err device:altDevice]);
        }

        if (result)
        {
            plist_free(result);
        }
        
        // Verify the installed developer disk is compatible with altDevice's operating system version.
        ALTDebugConnection *testConnection = [[ALTDebugConnection alloc] initWithDevice:altDevice];
        [testConnection connectWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
            [testConnection disconnect];
            
            if (success)
            {
                // Connection succeeded, so we assume the developer disk is compatible.
                finish(nil);
            }
            else if ([error.domain isEqualToString:AltServerConnectionErrorDomain] && error.code == ALTServerConnectionErrorUnknown)
            {
                // Connection failed with .unknown error code, so we assume the developer disk is NOT compatible.
                NSMutableDictionary *userInfo = [@{
                    ALTOperatingSystemVersionErrorKey: NSStringFromOperatingSystemVersion(altDevice.osVersion),
                    NSFilePathErrorKey: diskURL.path,
                    NSUnderlyingErrorKey: error,
                } mutableCopy];
                
                NSString *osName = ALTOperatingSystemNameForDeviceType(altDevice.type);
                if (osName != nil)
                {
                    userInfo[ALTOperatingSystemNameErrorKey] = osName;
                }
                
                NSError *returnError = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorIncompatibleDeveloperDisk userInfo:userInfo];
                finish(returnError);
            }
            else
            {
                finish(error);
            }
        }];
    });
}

#pragma mark - Apps -

- (void)fetchInstalledAppsOnDevice:(ALTDevice *)altDevice completionHandler:(void (^)(NSSet<ALTInstalledApp *> *_Nullable installedApps, NSError *_Nullable error))completionHandler
{
    __block idevice_t device = NULL;
    __block instproxy_client_t ipc = NULL;
    __block lockdownd_client_t client = NULL;
    __block lockdownd_service_descriptor_t service = NULL;
    __block plist_t options = NULL;
        
    void (^finish)(NSSet<ALTInstalledApp *> *, NSError *) = ^(NSSet<ALTInstalledApp *> *installedApps, NSError *error) {
        if (error != nil) {
            NSLog(@"Notification Connection Error: %@", error);
        }
        
        if (options) {
            instproxy_client_options_free(options);
        }
        
        if (service) {
            lockdownd_service_descriptor_free(service);
        }
        
        if (client) {
            lockdownd_client_free(client);
        }
                
        if (ipc) {
            instproxy_client_free(ipc);
        }
        
        if (device) {
            idevice_free(device);
        }
        
        completionHandler(installedApps, error);
    };
    
    // Don't use installationQueue since this operation can potentially take a very long time and will block other operations.
    // dispatch_async(self.installationQueue, ^{
    dispatch_async(self.devicesQueue, ^{
        /* Find Device */
        if (idevice_new_with_options(&device, altDevice.identifier.UTF8String, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX)) != IDEVICE_E_SUCCESS)
        {
            return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
        }
        
        if (LOCKDOWN_E_SUCCESS != lockdownd_client_new_with_handshake(device, &client, "AltServer"))
        {
            return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        if ((lockdownd_start_service(client, "com.apple.mobile.installation_proxy", &service) != LOCKDOWN_E_SUCCESS) || !service)
        {
            return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
        }
        
        instproxy_error_t err = instproxy_client_new(device, service, &ipc);
        if (err != INSTPROXY_E_SUCCESS)
        {
            return finish(nil, [NSError errorWithInstallationProxyError:err device:altDevice]);
        }
        
        options = instproxy_client_options_new();
        instproxy_client_options_add(options, "ApplicationType", "User", NULL);
        
        plist_t plist = NULL;
        err = instproxy_browse(ipc, options, &plist);
        if (err != INSTPROXY_E_SUCCESS)
        {
            return finish(nil, [NSError errorWithInstallationProxyError:err device:altDevice]);
        }
        
        char *plistXML = NULL;
        uint32_t length = 0;
        plist_to_xml(plist, &plistXML, &length);
        
        NSData *plistData = [@(plistXML) dataUsingEncoding:NSUTF8StringEncoding];
        free(plistXML);
        plist_free(plist);
        
        NSError *error = nil;
        NSArray *appDictionaries = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:nil error:&error];
        if (appDictionaries == nil)
        {
            return finish(nil, error);
        }
        
        NSMutableSet *installedApps = [NSMutableSet set];
        for (NSDictionary *appInfo in appDictionaries)
        {
            if (appInfo[@"ALTBundleIdentifier"] != nil)
            {
                // Only return apps installed with AltStore.
                
                ALTInstalledApp *installedApp = [[ALTInstalledApp alloc] initWithDictionary:appInfo];
                if (installedApp)
                {
                    [installedApps addObject:installedApp];
                }
            }
        }
        
        finish(installedApps, nil);
    });
}

#pragma mark - Connections -

- (void)startWiredConnectionToDevice:(ALTDevice *)altDevice completionHandler:(void (^)(ALTWiredConnection * _Nullable, NSError * _Nullable))completionHandler
{
    void (^finish)(ALTWiredConnection *connection, NSError *error) = ^(ALTWiredConnection *connection, NSError *error) {
        if (error != nil)
        {
            NSLog(@"Wired Connection Error: %@", error);
        }
        
        completionHandler(connection, error);
    };
    
    idevice_t device = NULL;
    idevice_connection_t connection = NULL;
    
    /* Find Device */
    if (idevice_new_with_options(&device, altDevice.identifier.UTF8String, IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
    }
    
    /* Connect to Listening Socket */
    if (idevice_connect(device, ALTDeviceListeningSocket, &connection) != IDEVICE_E_SUCCESS)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
    }
    
    idevice_free(device);
    
    ALTWiredConnection *wiredConnection = [[ALTWiredConnection alloc] initWithDevice:altDevice connection:connection];
    finish(wiredConnection, nil);
}

- (void)startNotificationConnectionToDevice:(ALTDevice *)altDevice completionHandler:(void (^)(ALTNotificationConnection * _Nullable, NSError * _Nullable))completionHandler
{
    void (^finish)(ALTNotificationConnection *, NSError *) = ^(ALTNotificationConnection *connection, NSError *error) {
        if (error != nil)
        {
            NSLog(@"Notification Connection Error: %@", error);
        }
        
        completionHandler(connection, error);
    };
    
    idevice_t device = NULL;
    lockdownd_client_t lockdownClient = NULL;
    lockdownd_service_descriptor_t service = NULL;
    
    np_client_t client = NULL;
    
    /* Find Device */
    if (idevice_new_with_options(&device, altDevice.identifier.UTF8String, IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorDeviceNotFound userInfo:nil]);
    }
    
    /* Connect to Device */
    if (lockdownd_client_new_with_handshake(device, &lockdownClient, "altserver") != LOCKDOWN_E_SUCCESS)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
    }

    /* Connect to Notification Proxy */
    if ((lockdownd_start_service(lockdownClient, "com.apple.mobile.notification_proxy", &service) != LOCKDOWN_E_SUCCESS) || service == NULL)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
    }
    
    /* Connect to Client */
    if (np_client_new(device, service, &client) != NP_E_SUCCESS)
    {
        return finish(nil, [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorConnectionFailed userInfo:nil]);
    }
    
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(lockdownClient);
    idevice_free(device);
    
    ALTNotificationConnection *notificationConnection = [[ALTNotificationConnection alloc] initWithDevice:altDevice client:client];
    completionHandler(notificationConnection, nil);
}

- (void)startDebugConnectionToDevice:(ALTDevice *)device completionHandler:(void (^)(ALTDebugConnection * _Nullable, NSError * _Nullable))completionHandler
{
    ALTDebugConnection *connection = [[ALTDebugConnection alloc] initWithDevice:device];
    [connection connectWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success)
        {
            completionHandler(connection, nil);
        }
        else
        {
            completionHandler(nil, error);
        }
    }];
}
#pragma mark - Getters -

- (NSArray<ALTDevice *> *)connectedDevices
{    
    return [self availableDevicesIncludingNetworkDevices:NO];
}

- (NSArray<ALTDevice *> *)availableDevices
{
    return [self availableDevicesIncludingNetworkDevices:YES];
}

- (NSArray<ALTDevice *> *)availableDevicesIncludingNetworkDevices:(BOOL)includingNetworkDevices
{
    NSMutableSet *connectedDevices = [NSMutableSet set];
    
    int count = 0;
    idevice_info_t *devices = NULL;
    
    if (idevice_get_device_list_extended(&devices, &count) < 0)
    {
        fprintf(stderr, "ERROR: Unable to retrieve device list!\n");
        return @[];
    }
    
    for (int i = 0; i < count; i++)
    {
        idevice_info_t device_info = devices[i];
        char *udid = device_info->udid;
        
        idevice_t device = NULL;
        lockdownd_client_t client = NULL;
        
        char *device_name = NULL;
        char *device_type_string = NULL;
        char *device_version_string = NULL;
        
        plist_t device_type_plist = NULL;
        plist_t device_version_plist = NULL;
        
        void (^cleanUp)(void) = ^{
            if (device_version_plist) {
                plist_free(device_version_plist);
            }
            
            if (device_type_plist) {
                plist_free(device_type_plist);
            }
            
            if (device_version_string) {
                free(device_version_string);
            }
            
            if (device_type_string) {
                free(device_type_string);
            }
            
            if (device_name) {
                free(device_name);
            }
            
            if (client) {
                lockdownd_client_free(client);
            }
            
            if (device) {
                idevice_free(device);
            }
        };
        
        if (includingNetworkDevices)
        {
            idevice_new_with_options(&device, udid, (enum idevice_options)((int)IDEVICE_LOOKUP_NETWORK | (int)IDEVICE_LOOKUP_USBMUX));
        }
        else
        {
            idevice_new_with_options(&device, udid, IDEVICE_LOOKUP_USBMUX);
        }
        
        if (!device)
        {
            continue;
        }
        
        int result = lockdownd_client_new(device, &client, "altserver");
        if (result != LOCKDOWN_E_SUCCESS)
        {
            fprintf(stderr, "ERROR: Connecting to device %s failed! (%d)\n", udid, result);
            
            cleanUp();
            continue;
        }
        
        if (lockdownd_get_device_name(client, &device_name) != LOCKDOWN_E_SUCCESS || device_name == NULL)
        {
            fprintf(stderr, "ERROR: Could not get device name!\n");
            
            cleanUp();
            continue;
        }
        
        if (lockdownd_get_value(client, NULL, "ProductType", &device_type_plist) != LOCKDOWN_E_SUCCESS)
        {
            fprintf(stderr, "ERROR: Could not get device type for %s!\n", device_name);
            
            cleanUp();
            continue;
        }
        
        plist_get_string_val(device_type_plist, &device_type_string);
        
        ALTDeviceType deviceType = ALTDeviceTypeiPhone;
        if ([@(device_type_string) hasPrefix:@"iPhone"])
        {
            deviceType = ALTDeviceTypeiPhone;
        }
        else if ([@(device_type_string) hasPrefix:@"iPad"])
        {
            deviceType = ALTDeviceTypeiPad;
        }
        else if ([@(device_type_string) hasPrefix:@"AppleTV"])
        {
            deviceType = ALTDeviceTypeAppleTV;
        }
        else
        {
            fprintf(stderr, "ERROR: Unknown device type %s for %s!\n", device_type_string, device_name);
            
            cleanUp();
            continue;
        }
        
        if (lockdownd_get_value(client, NULL, "ProductVersion", &device_version_plist) != LOCKDOWN_E_SUCCESS)
        {
            fprintf(stderr, "ERROR: Could not get device type for %s!\n", device_name);
            
            cleanUp();
            continue;
        }
        
        plist_get_string_val(device_version_plist, &device_version_string);
        NSOperatingSystemVersion osVersion = NSOperatingSystemVersionFromString(@(device_version_string));
        
        NSString *name = [NSString stringWithCString:device_name encoding:NSUTF8StringEncoding];
        NSString *identifier = [NSString stringWithCString:udid encoding:NSUTF8StringEncoding];
        
        ALTDevice *altDevice = [[ALTDevice alloc] initWithName:name identifier:identifier type:deviceType];
        altDevice.osVersion = osVersion;
        [connectedDevices addObject:altDevice];
        
        cleanUp();
    }
    
    idevice_device_list_extended_free(devices);
    
    return connectedDevices.allObjects;
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
    
    if ((percent == -1 && progress.completedUnitCount > 0) || code != 0 || name != NULL)
    {
        void (^completionHandler)(NSError *) = ALTDeviceManager.sharedManager.installationCompletionHandlers[UUID];
        if (completionHandler != nil)
        {
            NSString *localizedDescription = @(description ?: "");
            
            if (code != 0 || name != NULL)
            {
                NSLog(@"Error installing app. %@ (%@). %@", @(code), @(name ?: ""), localizedDescription);
                
                NSError *error = nil;
                
                if (code == 3892346913)
                {
                    NSDictionary *userInfo = (localizedDescription.length != 0) ? @{NSLocalizedDescriptionKey: localizedDescription} : nil;
                    error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorMaximumFreeAppLimitReached userInfo:userInfo];
                }
                else
                {
                    NSString *errorName = [NSString stringWithCString:name ?: "" encoding:NSUTF8StringEncoding];
                    if ([errorName isEqualToString:@"DeviceOSVersionTooLow"])
                    {
                        error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorUnsupportediOSVersion userInfo:nil];
                    }
                    else
                    {
                        NSError *underlyingError = [NSError errorWithDomain:AltServerInstallationErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: localizedDescription}];
                        error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorInstallationFailed userInfo:@{NSUnderlyingErrorKey: underlyingError}];
                    }
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

void ALTDeviceManagerUpdateAppDeletionStatus(plist_t command, plist_t status, void *uuid)
{
    NSUUID *UUID = [[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:(const char *)uuid]];
    
    char *statusName = NULL;
    instproxy_status_get_name(status, &statusName);

    char *errorName = NULL;
    char *errorDescription = NULL;
    uint64_t code = 0;
    instproxy_status_get_error(status, &errorName, &errorDescription, &code);
    
    if ([@(statusName) isEqualToString:@"Complete"] || code != 0 || errorName != NULL)
    {
        void (^completionHandler)(NSError *) = ALTDeviceManager.sharedManager.deletionCompletionHandlers[UUID];
        if (completionHandler != nil)
        {
            if (code != 0 || errorName != NULL)
            {
                NSLog(@"Error removing app. %@ (%@). %@", @(code), @(errorName ?: ""), @(errorDescription ?: ""));
                
                NSError *underlyingError = [NSError errorWithDomain:AltServerInstallationErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: @(errorDescription ?: "")}];
                NSError *error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorAppDeletionFailed userInfo:@{NSUnderlyingErrorKey: underlyingError}];
                
                completionHandler(error);
            }
            else
            {
                NSLog(@"Finished removing app!");
                completionHandler(nil);
            }
            
            ALTDeviceManager.sharedManager.deletionCompletionHandlers[UUID] = nil;
        }
    }
}

void ALTDeviceDidChangeConnectionStatus(const idevice_event_t *event, void *user_data)
{
    ALTDevice * (^deviceForUDID)(NSString *, NSArray<ALTDevice *> *) = ^ALTDevice *(NSString *udid, NSArray<ALTDevice *> *devices) {
        for (ALTDevice *device in devices)
        {
            if ([device.identifier isEqualToString:udid])
            {
                return device;
            }
        }
        
        return nil;
    };
    
    switch (event->event)
    {
        case IDEVICE_DEVICE_ADD:
        {
            ALTDevice *device = deviceForUDID(@(event->udid), ALTDeviceManager.sharedManager.connectedDevices);
            [[NSNotificationCenter defaultCenter] postNotificationName:ALTDeviceManagerDeviceDidConnectNotification object:device];
            
            if (device)
            {
                [ALTDeviceManager.sharedManager.cachedDevices addObject:device];
            }
            
            break;
        }
            
        case IDEVICE_DEVICE_REMOVE:
        {
            ALTDevice *device = deviceForUDID(@(event->udid), ALTDeviceManager.sharedManager.cachedDevices.allObjects);
            [[NSNotificationCenter defaultCenter] postNotificationName:ALTDeviceManagerDeviceDidDisconnectNotification object:device];
            
            if (device)
            {
                 [ALTDeviceManager.sharedManager.cachedDevices removeObject:device];
            }

            break;
        }
            
        default: break;
    }
}

ssize_t ALTDeviceManagerUploadFile(void *buffer, size_t size, void *user_data)
{
    return fread(buffer, 1, size, (FILE*)user_data);
}
