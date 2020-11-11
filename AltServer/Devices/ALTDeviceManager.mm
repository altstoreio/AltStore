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

#import "ALTConstants.h"
#import "NSError+ALTServerError.h"

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/installation_proxy.h>
#include <libimobiledevice/notification_proxy.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/misagent.h>

void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *udid);
void ALTDeviceManagerUpdateAppDeletionStatus(plist_t command, plist_t status, void *uuid);
void ALTDeviceDidChangeConnectionStatus(const idevice_event_t *event, void *user_data);

NSNotificationName const ALTDeviceManagerDeviceDidConnectNotification = @"ALTDeviceManagerDeviceDidConnectNotification";
NSNotificationName const ALTDeviceManagerDeviceDidDisconnectNotification = @"ALTDeviceManagerDeviceDidDisconnectNotification";

@interface ALTDeviceManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(NSError *)> *installationCompletionHandlers;
@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, void (^)(NSError *)> *deletionCompletionHandlers;

@property (nonatomic, readonly) NSMutableDictionary<NSUUID *, NSProgress *> *installationProgress;
@property (nonatomic, readonly) dispatch_queue_t installationQueue;

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
        _installationQueue = dispatch_queue_create("com.rileytestut.AltServer.InstallationQueue", DISPATCH_QUEUE_SERIAL);
        
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
        if (idevice_new(&device, udid.UTF8String) != IDEVICE_E_SUCCESS)
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
        if (idevice_new(&device, udid.UTF8String) != IDEVICE_E_SUCCESS)
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
    if (idevice_new_ignore_network(&device, altDevice.identifier.UTF8String) != IDEVICE_E_SUCCESS)
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
    if (idevice_new_ignore_network(&device, altDevice.identifier.UTF8String) != IDEVICE_E_SUCCESS)
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
        
        if (includingNetworkDevices)
        {
            idevice_new(&device, udid);
        }
        else
        {
            idevice_new_ignore_network(&device, udid);
        }
        
        if (!device)
        {
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
        
        ALTDevice *altDevice = [[ALTDevice alloc] initWithName:name identifier:identifier type:ALTDeviceTypeiPhone];
        [connectedDevices addObject:altDevice];
        
        if (device_name != NULL)
        {
            free(device_name);
        }
    }
    
    idevice_device_list_free(udids);
    
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
            if (code != 0 || name != NULL)
            {
                NSLog(@"Error installing app. %@ (%@). %@", @(code), @(name ?: ""), @(description ?: ""));
                
                NSError *error = nil;
                
                if (code == 3892346913)
                {
                    error = [NSError errorWithDomain:AltServerErrorDomain code:ALTServerErrorMaximumFreeAppLimitReached userInfo:nil];
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
                        NSError *underlyingError = [NSError errorWithDomain:AltServerInstallationErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: @(description ?: "")}];
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
