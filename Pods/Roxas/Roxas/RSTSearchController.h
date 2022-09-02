//
//  RSTSearchResultsController.h
//  Roxas
//
//  Created by Riley Testut on 2/7/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface RSTSearchValue : NSObject <NSCopying>

@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSPredicate *predicate;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END


NS_ASSUME_NONNULL_BEGIN

@interface RSTSearchController : UISearchController <UISearchResultsUpdating>

// Used to generate RSTSearchValue predicates.
@property (copy, nonatomic) NSSet<NSString *> *searchableKeyPaths;

// Handler called when the search text changes.
// To perform a synchronous search, perform the necessary search logic synchronously in the handler, and return nil.
// To perform an asynchronous search, return an NSOperation that will perform the search logic.
// When searching asynchronously, the previous search NSOperation will be cancelled when the search text changes.
// To ensure outdated results are not displayed, make sure to check that -[NSOperation isCancelled] is NO before updating results.
@property (nullable, copy, nonatomic) NSOperation *_Nullable (^searchHandler)(RSTSearchValue *searchValue, RSTSearchValue *_Nullable previousSearchValue);

@end

NS_ASSUME_NONNULL_END
