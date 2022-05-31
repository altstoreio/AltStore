//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Foundation/Foundation.h>

// Shared
#import "ALTConstants.h"
#import "ALTConnection.h"
#import "NSError+ALTServerError.h"
#import "CFNotificationName+AltStore.h"

// libproc
int proc_pidpath(int pid, void * buffer, uint32_t buffersize);

// Security.framework
CF_ENUM(uint32_t) {
    kSecCSInternalInformation = 1 << 0,
    kSecCSSigningInformation = 1 << 1,
    kSecCSRequirementInformation = 1 << 2,
    kSecCSDynamicInformation = 1 << 3,
    kSecCSContentInformation = 1 << 4,
    kSecCSSkipResourceDirectory = 1 << 5,
    kSecCSCalculateCMSDigest = 1 << 6,
};

OSStatus SecStaticCodeCreateWithPath(CFURLRef path, uint32_t flags, void ** __nonnull CF_RETURNS_RETAINED staticCode);
OSStatus SecCodeCopySigningInformation(void *code, uint32_t flags, CFDictionaryRef * __nonnull CF_RETURNS_RETAINED information);

NS_ASSUME_NONNULL_BEGIN

@interface AKDevice : NSObject

@property (class, readonly) AKDevice *currentDevice;

@property (strong, readonly) NSString *serialNumber;
@property (strong, readonly) NSString *uniqueDeviceIdentifier;
@property (strong, readonly) NSString *serverFriendlyDescription;

@end

@interface AKAppleIDSession : NSObject

- (instancetype)initWithIdentifier:(NSString *)identifier;

- (NSDictionary<NSString *, NSString *> *)appleIDHeadersForRequest:(NSURLRequest *)request;

@end

@interface LSApplicationWorkspace : NSObject

@property (class, readonly) LSApplicationWorkspace *defaultWorkspace;

- (BOOL)installApplication:(NSURL *)fileURL withOptions:(nullable NSDictionary<NSString *, id> *)options error:(NSError *_Nullable *)error;
- (BOOL)uninstallApplication:(NSString *)bundleIdentifier withOptions:(nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END
