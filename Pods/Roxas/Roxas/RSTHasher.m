//
//  RSTHasher.m
//  Roxas
//
//  Created by Riley Testut on 11/7/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTHasher.h"

@import CommonCrypto;

@implementation RSTHasher

+ (nullable NSString *)sha1HashOfFileAtURL:(NSURL *)fileURL error:(NSError * _Nullable __autoreleasing * _Nullable)error
{
    NSInteger bufferSize = 1024 * 1024;
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:fileURL error:error];
    if (fileHandle == nil)
    {
        return nil;
    }
    
    CC_SHA1_CTX context;
    CC_SHA1_Init(&context);
    
    while (true)
    {
        @autoreleasepool
        {
            NSData *data = [fileHandle readDataOfLength:bufferSize];
            if (data.length == 0)
            {
                break;
            }
            
            CC_SHA1_Update(&context, [data bytes], (unsigned int)data.length);
        }
    }
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &context);
    
    NSString *hashString = [RSTHasher hashStringFromDigest:digest];
    return hashString;
}

+ (NSString *)sha1HashOfData:(NSData *)data
{
    CC_SHA1_CTX context;
    CC_SHA1_Init(&context);
    
    CC_SHA1_Update(&context, [data bytes], (unsigned int)data.length);
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &context);
    
    NSString *hashString = [RSTHasher hashStringFromDigest:digest];
    return hashString;
}

+ (NSString *)hashStringFromDigest:(unsigned char[CC_SHA1_DIGEST_LENGTH])digest
{
    NSMutableString *hashString = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
    {
        [hashString appendFormat:@"%02x", digest[i]];
    }
    
    return [hashString copy];
}

@end
