//
//  RSTPersistentContainer.m
//  Roxas
//
//  Created by Riley Testut on 7/16/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

#import "RSTPersistentContainer.h"
#import "RSTRelationshipPreservingMergePolicy.h"

#import "RSTError.h"

NS_ASSUME_NONNULL_BEGIN

@interface RSTPersistentContainer ()

@property (readonly, nonatomic) NSHashTable<NSManagedObjectContext *> *parentBackgroundContexts;
@property (readonly, nonatomic) NSHashTable<NSManagedObjectContext *> *pendingSaveParentBackgroundContexts;

@end

NS_ASSUME_NONNULL_END

@implementation RSTPersistentContainer

- (instancetype)initWithName:(NSString *)name bundle:(NSBundle *)bundle
{
    NSManagedObjectModel *managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:@[bundle]];
    
    self = [super initWithName:name managedObjectModel:managedObjectModel];
    if (self)
    {
        [self initialize];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name managedObjectModel:(NSManagedObjectModel *)model
{
    self = [super initWithName:name managedObjectModel:model];
    if (self)
    {
        [self initialize];
    }
    return self;
}

- (void)initialize
{
    _shouldAddStoresAsynchronously = NO;
    
    _preferredMergePolicy = [[RSTRelationshipPreservingMergePolicy alloc] init];
    
    _parentBackgroundContexts = [NSHashTable weakObjectsHashTable];
    _pendingSaveParentBackgroundContexts = [NSHashTable weakObjectsHashTable];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rst_managedObjectContextWillSave:) name:NSManagedObjectContextWillSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rst_managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
}

- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription * _Nonnull, NSError * _Nullable))completionHandler
{
    dispatch_group_t dispatchGroup = dispatch_group_create();
    
    for (NSPersistentStoreDescription *description in self.persistentStoreDescriptions)
    {
        description.shouldAddStoreAsynchronously = self.shouldAddStoresAsynchronously;
        
        NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:description.type URL:description.URL options:description.options error:nil];
        if (metadata == nil)
        {
            continue;
        }
        
        if (![self.managedObjectModel isConfiguration:nil compatibleWithStoreMetadata:metadata] && description.shouldMigrateStoreAutomatically)
        {
            // Migrate database if incompatible with managed object model.
            
            dispatch_group_enter(dispatchGroup);
            
            [self progressivelyMigratePersistentStoreToModel:self.managedObjectModel
                                               configuration:description.configuration
                                              isAsynchronous:description.shouldAddStoreAsynchronously
                                           completionHandler:^(NSError * _Nullable error) {
                                               if (error != nil)
                                               {
                                                   ELog(error);
                                               }
                                               
                                               dispatch_group_leave(dispatchGroup);
                                           }];
        }
    }
    
    void (^finish)(NSPersistentStoreDescription *, NSError *) = ^(NSPersistentStoreDescription *description, NSError *error) {
        [self configureManagedObjectContext:self.viewContext parent:nil];
        completionHandler(description, error);
    };
    
    if (self.shouldAddStoresAsynchronously)
    {
        dispatch_group_notify(dispatchGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [super loadPersistentStoresWithCompletionHandler:finish];
        });
    }
    else
    {
        dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
        
        [super loadPersistentStoresWithCompletionHandler:finish];
    }
}

- (NSManagedObjectContext *)newBackgroundContext
{
    NSManagedObjectContext *context = [super newBackgroundContext];
    [self configureManagedObjectContext:context parent:nil];
    return context;
}

- (NSManagedObjectContext *)newBackgroundSavingViewContext
{
    NSManagedObjectContext *parentBackgroundContext = [self newBackgroundContext];
    [self.parentBackgroundContexts addObject:parentBackgroundContext];
    
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [self configureManagedObjectContext:context parent:parentBackgroundContext];
    return context;
}

- (NSManagedObjectContext *)newViewContextWithParent:(NSManagedObjectContext *)parentContext
{
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [self configureManagedObjectContext:context parent:parentContext];
    return context;
}

- (NSManagedObjectContext *)newBackgroundContextWithParent:(NSManagedObjectContext *)parentContext
{
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self configureManagedObjectContext:context parent:parentContext];
    return context;
}

- (void)configureManagedObjectContext:(NSManagedObjectContext *)context parent:(nullable NSManagedObjectContext *)parent
{
    if (parent != nil)
    {
        context.parentContext = parent;
    }
    
    context.automaticallyMergesChangesFromParent = YES;
    context.mergePolicy = self.preferredMergePolicy;
}

#pragma mark - Migrations -

// Migration logic based off of https://www.objc.io/issues/4-core-data/core-data-migration/

- (void)progressivelyMigratePersistentStoreToModel:(NSManagedObjectModel *)model configuration:(nullable NSString *)configuration isAsynchronous:(BOOL)asynchronous completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    void (^migrate)(void) = ^(void) {
        NSError *error = nil;
        BOOL success = [self _progressivelyMigratePersistentStoreToModel:model configuration:configuration error:&error];
        
        if (success)
        {
            completionHandler(nil);
        }
        else
        {
            completionHandler(error);
        }
    };
    
    if (asynchronous)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            migrate();
        });
    }
    else
    {
        migrate();
    }
}

- (BOOL)_progressivelyMigratePersistentStoreToModel:(NSManagedObjectModel *)model configuration:(nullable NSString *)configuration error:(NSError * _Nonnull *)error
{
    NSPersistentStoreDescription *description = self.persistentStoreDescriptions.firstObject;
    if (description == nil)
    {
        *error = [NSError errorWithDomain:RoxasErrorDomain code:RSTErrorMissingPersistentStore userInfo:nil];
        return NO;
    }
    
    NSDictionary *sourceMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:description.type URL:description.URL options:description.options error:error];
    if (sourceMetadata == nil)
    {
        return NO;
    }
    
    if ([self.managedObjectModel isConfiguration:nil compatibleWithStoreMetadata:sourceMetadata])
    {
        // The store is now compatible with the managed object model, so we're done.
        return YES;
    }

    NSManagedObjectModel *sourceModel = [NSManagedObjectModel mergedModelFromBundles:NSBundle.allBundles forStoreMetadata:sourceMetadata];
    if (sourceModel == nil)
    {
        *error = [NSError errorWithDomain:RoxasErrorDomain code:RSTErrorMissingManagedObjectModel userInfo:nil];
        return NO;
    }
    
    NSMappingModel *mappingModel = nil;
    NSMigrationManager *migrationManager = [self progressiveMigrationManagerForSourceModel:sourceModel destinationModel:model configuration:configuration mappingModel:&mappingModel];
    if (migrationManager == nil)
    {
        *error = [NSError errorWithDomain:RoxasErrorDomain code:RSTErrorMissingMappingModel userInfo:nil];
        return NO;
    }
    
    NSString *temporaryFilename = [[[NSUUID UUID] UUIDString] stringByAppendingFormat:@".%@", description.URL.pathExtension];
    NSURL *temporaryDestinationURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:temporaryFilename];
    
    BOOL success = [migrationManager migrateStoreFromURL:description.URL
                                                    type:description.type
                                                 options:description.options
                                        withMappingModel:mappingModel // migrationManager.mappingModel is nil for some reason
                                        toDestinationURL:temporaryDestinationURL
                                         destinationType:description.type
                                      destinationOptions:description.options
                                                   error:error];
    if (!success)
    {
        return NO;
    }
    
    BOOL replacementSuccess = [self.persistentStoreCoordinator replacePersistentStoreAtURL:description.URL
                                                                        destinationOptions:description.options
                                                                withPersistentStoreFromURL:temporaryDestinationURL
                                                                             sourceOptions:description.options
                                                                                 storeType:description.type
                                                                                     error:error];
    if (!replacementSuccess)
    {
        return NO;
    }
    
    NSError *deletionError = nil;
    if (![self.persistentStoreCoordinator destroyPersistentStoreAtURL:temporaryDestinationURL withType:description.type options:description.options error:&deletionError])
    {
        ELog(deletionError);
    }
    
    return [self _progressivelyMigratePersistentStoreToModel:model configuration:configuration error:error];
}

- (nullable NSMigrationManager *)progressiveMigrationManagerForSourceModel:(NSManagedObjectModel *)sourceModel destinationModel:(NSManagedObjectModel *)destinationModel configuration:(nullable NSString *)configuration mappingModel:(NSMappingModel **)outMappingModel
{
    NSArray<NSURL *> *managedObjectModelURLs = [self managedObjectModelURLs];
    for (NSURL *modelURL in managedObjectModelURLs)
    {
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        NSMappingModel *mappingModel = [NSMappingModel mappingModelFromBundles:NSBundle.allBundles
                                                                forSourceModel:sourceModel
                                                              destinationModel:model];
        if (mappingModel == nil)
        {
            continue;
        }
        
        // If this model contains at least one entity that belongs to our configuration,
        // we can assume that this is a valid mapping model for the configuration.
        BOOL isValidForConfiguration = NO;
        
        // sourceModel doesn't properly merge configurations, so retrieve configuration entities via self.managedObjectModel.
        for (NSEntityDescription *entityDescription in [self.managedObjectModel entitiesForConfiguration:configuration])
        {
            if (model.entitiesByName[entityDescription.name] != nil)
            {
                isValidForConfiguration = YES;
                break;
            }
        }
        
        if (!isValidForConfiguration)
        {
            continue;
        }
        
        *outMappingModel = mappingModel;
        
        NSMigrationManager *migrationManager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel destinationModel:model];
        return migrationManager;
    }
    
    // Fallback to inferring mapping model.
    
    NSError *error = nil;
    NSMappingModel *inferredMappingModel = [NSMappingModel inferredMappingModelForSourceModel:sourceModel destinationModel:destinationModel error:&error];
    
    if (inferredMappingModel == nil)
    {
        NSLog(@"Error inferring mapping: %@", error);
        return nil;
    }
    
    *outMappingModel = inferredMappingModel;
    
    NSMigrationManager *migrationManager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel destinationModel:destinationModel];
    return migrationManager;
}

- (NSArray<NSURL *> *)managedObjectModelURLs
{
    NSMutableArray *modelURLs = [NSMutableArray array];
    
    for (NSBundle *bundle in NSBundle.allBundles)
    {
        NSArray *momdURLs = [bundle URLsForResourcesWithExtension:@"momd" subdirectory:nil];
        for (NSURL *URL in momdURLs)
        {
            NSString *resourceDirectory = [URL lastPathComponent];
            
            NSArray *momURLs = [bundle URLsForResourcesWithExtension:@"mom" subdirectory:resourceDirectory];
            [modelURLs addObjectsFromArray:momURLs];
        }
        
        NSArray *momURLs = [bundle URLsForResourcesWithExtension:@"mom" subdirectory:nil];
        [modelURLs addObjectsFromArray:momURLs];
    }
    
    return modelURLs;
}

#pragma mark - NSNotifications -

// Use rst_ prefix to prevent collisions with subclasses.
- (void)rst_managedObjectContextWillSave:(NSNotification *)notification
{
    NSManagedObjectContext *context = notification.object;
    if (![self.parentBackgroundContexts containsObject:context.parentContext])
    {
        return;
    }
    
    [self.pendingSaveParentBackgroundContexts addObject:context.parentContext];
}

// Use rst_ prefix to prevent collisions with subclasses.
- (void)rst_managedObjectContextObjectsDidChange:(NSNotification *)notification
{
    NSManagedObjectContext *context = notification.object;
    if (![self.pendingSaveParentBackgroundContexts containsObject:context])
    {
        return;
    }
    
    NSError *error = nil;
    if (![context save:&error])
    {
        ELog(error);
    }
    
    [self.pendingSaveParentBackgroundContexts removeObject:context];
}

@end
