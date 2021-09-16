//
//  NSPredicate+Search.m
//  Roxas
//
//  Created by Riley Testut on 2/14/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

#import "NSPredicate+Search.h"

@implementation NSPredicate (Search)

+ (instancetype)predicateForSearchingForText:(NSString *)searchText inValuesForKeyPaths:(NSSet<NSString *> *)keyPaths
{
    if (keyPaths.count == 0)
    {
        return [NSPredicate predicateWithValue:NO];
    }
    
    if (searchText.length == 0)
    {
        return [NSPredicate predicateWithValue:YES];
    }
    
    // Strip out all the leading and trailing spaces.
    NSString *strippedString = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // Break up the search terms (separated by spaces).
    NSArray *searchTerms = [strippedString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSMutableArray *subpredicates = [NSMutableArray arrayWithCapacity:keyPaths.count];
    
    for (NSString *searchTerm in searchTerms)
    {
        // Every search term must exist in at least ONE keyPath value.
        // To accomplish this, we use an OR predicate when iterating keyPaths (since only one needs to return true),
        // and then combine them with an AND predicate at the end (to ensure each search term exists somewhere).
        
        NSMutableArray *andPredicates = [NSMutableArray array];
        
        for (NSString *keyPath in keyPaths)
        {
            // Determine whether lhs (valueForKeyPath) contains rhs (a term from searchText)
            NSExpression *lhs = [NSExpression expressionForKeyPath:keyPath];
            NSExpression *rhs = [NSExpression expressionForConstantValue:searchTerm];
            
            NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression:lhs
                                                                        rightExpression:rhs
                                                                               modifier:NSDirectPredicateModifier
                                                                                   type:NSContainsPredicateOperatorType
                                                                                options:NSCaseInsensitivePredicateOption | NSDiacriticInsensitivePredicateOption];
            
            [andPredicates addObject:predicate];
        }
        
        NSCompoundPredicate *compoundPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:andPredicates];
        [subpredicates addObject:compoundPredicate];
    }
    
    NSCompoundPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:subpredicates];
    return predicate;
}

@end
