//
//  NSFileManager+URLs.m
//  Roxas
//
//  Created by Riley Testut on 12/21/14.
//  Copyright (c) 2014 Riley Testut. All rights reserved.
//

#import "NSFileManager+URLs.h"

@implementation NSFileManager (URLs)

- (void)prepareTemporaryURL:(void (^)(NSURL *))fileHandlingBlock
{
    if (fileHandlingBlock == nil)
    {
        return;
    }
    
    NSURL *temporaryURL = [self uniqueTemporaryURL];
    
    fileHandlingBlock(temporaryURL);
    
    NSError *error = nil;
    if (![self removeItemAtURL:temporaryURL error:&error])
    {
        // Ignore this error, because it means the client has manually removed the file themselves
        if (error.code != NSFileNoSuchFileError)
        {
            ELog(error);
        }
    }
}

- (BOOL)copyItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL shouldReplace:(BOOL)shouldReplace error:(NSError *__autoreleasing  _Nullable *)error
{
    if (!shouldReplace)
    {
        return [self copyItemAtURL:sourceURL toURL:destinationURL error:error];
    }
    
    NSURL *temporaryDirectory = [self URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:destinationURL create:YES error:error];
    if (temporaryDirectory == nil)
    {
        return NO;
    }
    
    void (^removeDirectory)(void) = ^{
        NSError *error = nil;
        if (![self removeItemAtURL:temporaryDirectory error:&error])
        {
            ELog(error);
        }
    };
    
    NSURL *temporaryURL = [temporaryDirectory URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    if (![self copyItemAtURL:sourceURL toURL:temporaryURL error:error])
    {
        removeDirectory();
        return NO;
    }
    
    if (![self replaceItemAtURL:destinationURL withItemAtURL:temporaryURL backupItemName:nil options:0 resultingItemURL:nil error:error])
    {
        removeDirectory();
        return NO;
    }
    
    removeDirectory();
    return YES;
}

#pragma mark - Getters/Setters -

- (NSURL *)uniqueTemporaryURL
{
    NSURL *temporaryDirectoryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSString *uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
    
    NSURL *temporaryURL = [temporaryDirectoryURL URLByAppendingPathComponent:uniqueIdentifier];
    return temporaryURL;
}

- (NSURL *)documentsDirectory
{
    NSURL *documentsDirectory = [self URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return documentsDirectory;
}

- (NSURL *)libraryDirectory
{
    NSURL *libraryDirectory = [self URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
    return libraryDirectory;
}

- (NSURL *)applicationSupportDirectory
{
    NSURL *applicationSupportDirectory = [self URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return applicationSupportDirectory;
}

- (NSURL *)cachesDirectory
{
    NSURL *cachesDirectory = [self URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return cachesDirectory;
}

@end
