//
//  RSTSearchResultsController.m
//  Roxas
//
//  Created by Riley Testut on 2/7/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "RSTSearchController.h"
#import "RSTOperationQueue.h"

#import "NSPredicate+Search.h"

@implementation RSTSearchValue

- (instancetype)initWithText:(NSString *)text predicate:(NSPredicate *)predicate
{
    self = [super init];
    if (self)
    {
        _text = [text copy];
        _predicate = [predicate copy];
    }
    
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    RSTSearchValue *copy = [[RSTSearchValue alloc] initWithText:self.text predicate:self.predicate];
    return copy;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[RSTSearchValue class]])
    {
        return NO;
    }
    
    return [self.text isEqual:[(RSTSearchValue *)object text]];
}

- (NSUInteger)hash
{
    return self.text.hash;
}

@end


@interface RSTSearchController ()

@property (nullable, copy, nonatomic) RSTSearchValue *previousSearchValue;

@property (nonatomic, readonly) RSTOperationQueue *searchOperationQueue;

@end


@implementation RSTSearchController

- (instancetype)initWithSearchResultsController:(UIViewController *)searchResultsController
{
    self = [super initWithSearchResultsController:searchResultsController];
    if (self)
    {
        _searchableKeyPaths = [NSSet setWithObject:@"self"];
        
        _searchOperationQueue = [[RSTOperationQueue alloc] init];
        _searchOperationQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
        
        // We want a concurrent queue, since this allows an operation to start before the previous operation has finished.
        // However, because we cancel the previous operation before adding a new one, there's no issue with finishing out of order.
        // _searchOperationQueue.maxConcurrentOperationCount = 1;
        
        self.searchResultsUpdater = self;
        
        if (searchResultsController == nil)
        {
            self.obscuresBackgroundDuringPresentation = NO;
        }
    }
    
    return self;
}

#pragma mark - <UISearchResultsUpdating> -

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *searchText = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSPredicate *searchPredicate = [NSPredicate predicateForSearchingForText:searchText inValuesForKeyPaths:self.searchableKeyPaths];
    
    RSTSearchValue *searchValue = [[RSTSearchValue alloc] initWithText:searchText predicate:searchPredicate];
    
    NSOperation *previousSearchOperation = self.searchOperationQueue[self.previousSearchValue];
    [previousSearchOperation cancel];
    
    if (self.searchHandler)
    {
        NSOperation *searchOperation = self.searchHandler(searchValue, self.previousSearchValue);
        if (searchOperation)
        {
            [self.searchOperationQueue addOperation:searchOperation forKey:searchValue];
        }
    }

    self.previousSearchValue = searchValue;
}

@end
