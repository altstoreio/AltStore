//
//  NSPredicate+Search.h
//  Roxas
//
//  Created by Riley Testut on 2/14/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface NSPredicate (Search)

+ (instancetype)predicateForSearchingForText:(NSString *)searchText inValuesForKeyPaths:(NSSet<NSString *> *)keyPaths;

@end

NS_ASSUME_NONNULL_END
