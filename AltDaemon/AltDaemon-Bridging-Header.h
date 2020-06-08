//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Foundation/Foundation.h>

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
