//
//  ALTDeviceManager.m
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTDeviceManager.h"

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>

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
