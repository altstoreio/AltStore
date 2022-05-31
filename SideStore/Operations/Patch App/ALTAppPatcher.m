//
//  ALTAppPatcher.m
//  AltStore
//
//  Created by Riley Testut on 10/18/21.
//  Copied with minor modifications from sample code provided by Linus Henze.
//

#import "ALTAppPatcher.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@import Roxas;

#define CPU_SUBTYPE_PAC    0x80000000
#define FAT_MAGIC 0xcafebabe

#define ROUND_TO_PAGE(val) (((val % 0x4000) == 0) ? val : (val + (0x4000 - (val & 0x3FFF))))

typedef struct {
    uint32_t magic;
    uint32_t cpuType;
    uint32_t cpuSubType;
    // Incomplete, we don't need anything else
} MachOHeader;

typedef struct {
    uint32_t cpuType;
    uint32_t cpuSubType;
    uint32_t fileOffset;
    uint32_t size;
    uint32_t alignment;
} FatArch;

typedef struct {
    uint32_t magic;
    uint32_t archCount;
    FatArch  archs[0];
} FatHeader;

// Given two MachO files, return a FAT file with the following properties:
// 1. installd will still see the original MachO and validate it's code signature
// 2. The kernel will only see the injected MachO instead
//
// Only arm64e for now
void *injectApp(void *originalApp, size_t originalAppSize, void *appToInject, size_t appToInjectSize, size_t *outputSize) {
    *outputSize = 0;
    
    // First validate the App to inject: It must be an arm64e application
    if (appToInjectSize < sizeof(MachOHeader)) {
        return NULL;
    }
    
    MachOHeader *injectedHeader = (MachOHeader*) appToInject;
    if (injectedHeader->cpuType != CPU_TYPE_ARM64) {
        return NULL;
    }
    
    if (injectedHeader->cpuSubType != (CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_PAC)) {
        return NULL;
    }
    
    // Ok, the App to inject is ok
    // Now build a fat header
    size_t originalAppSizeRounded = ROUND_TO_PAGE(originalAppSize);
    size_t appToInjectSizeRounded = ROUND_TO_PAGE(appToInjectSize);
    size_t totalSize = 0x4000 /* Fat Header + Alignment */ + originalAppSizeRounded + appToInjectSizeRounded;
    
    void *fatBuf = malloc(totalSize);
    if (fatBuf == NULL) {
        return NULL;
    }
    
    bzero(fatBuf, totalSize);
    
    FatHeader *fatHeader = (FatHeader*) fatBuf;
    fatHeader->magic = htonl(FAT_MAGIC);
    fatHeader->archCount = htonl(2);
    
    // Write first arch (original app)
    fatHeader->archs[0].cpuType    = htonl(CPU_TYPE_ARM64);
    fatHeader->archs[0].cpuSubType = htonl(CPU_SUBTYPE_ARM64E); /* Note that this is not a valid cpu subtype */
    fatHeader->archs[0].fileOffset = htonl(0x4000);
    fatHeader->archs[0].size       = htonl(originalAppSize);
    fatHeader->archs[0].alignment  = htonl(0xE);
    
    // Write second arch (injected app)
    fatHeader->archs[1].cpuType    = htonl(CPU_TYPE_ARM64);
    fatHeader->archs[1].cpuSubType = htonl(CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_PAC);
    fatHeader->archs[1].fileOffset = htonl(0x4000 + originalAppSizeRounded);
    fatHeader->archs[1].size       = htonl(appToInjectSize);
    fatHeader->archs[1].alignment  = htonl(0xE);
    
    // Ok, now write the MachOs
    memcpy(fatBuf + 0x4000, originalApp, originalAppSize);
    memcpy(fatBuf + 0x4000 + originalAppSizeRounded, appToInject, appToInjectSize);
    
    // We're done!
    *outputSize = totalSize;
    return fatBuf;
}

@implementation ALTAppPatcher

- (BOOL)patchAppBinaryAtURL:(NSURL *)appFileURL withBinaryAtURL:(NSURL *)patchFileURL error:(NSError *__autoreleasing *)error
{
    NSMutableData *originalApp = [NSMutableData dataWithContentsOfURL:appFileURL options:0 error:error];
    if (originalApp == nil)
    {
        return NO;
    }
    
    NSMutableData *injectedApp = [NSMutableData dataWithContentsOfURL:patchFileURL options:0 error:error];
    if (injectedApp == nil)
    {
        return NO;
    }

    size_t outputSize = 0;
    void *output = injectApp(originalApp.mutableBytes, originalApp.length, injectedApp.mutableBytes, injectedApp.length, &outputSize);
    if (output == NULL)
    {
        if (error)
        {
            // If injectApp fails, it means the patch app is in the wrong format.
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSURLErrorKey: patchFileURL}];
        }
        
        return NO;
    }
    
    NSData *outputData = [NSData dataWithBytesNoCopy:output length:outputSize freeWhenDone:YES];
    if (![outputData writeToURL:appFileURL options:NSDataWritingAtomic error:error])
    {
        return NO;
    }
    
    return YES;
}

@end
