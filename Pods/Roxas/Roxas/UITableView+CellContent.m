//
//  UITableView+CellContent.m
//  Roxas
//
//  Created by Riley Testut on 10/21/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "UITableView+CellContent.h"
#import "RSTCellContentChange.h"

@implementation UITableView (CellContent)

- (void)addChange:(RSTCellContentChange *)change
{
    switch (change.type)
    {
        case NSFetchedResultsChangeInsert:
        {
            if (change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self insertSections:[NSIndexSet indexSetWithIndex:change.sectionIndex] withRowAnimation:change.rowAnimation];
            }
            else
            {
                [self insertRowsAtIndexPaths:@[change.destinationIndexPath] withRowAnimation:change.rowAnimation];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeDelete:
        {
            if (change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self deleteSections:[NSIndexSet indexSetWithIndex:change.sectionIndex] withRowAnimation:change.rowAnimation];
            }
            else
            {
                [self deleteRowsAtIndexPaths:@[change.currentIndexPath] withRowAnimation:change.rowAnimation];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeMove:
        {
            // According to documentation:
            // Move is reported when an object changes in a manner that affects its position in the results.  An update of the object is assumed in this case, no separate update message is sent to the delegate.
            
            // Therefore, we need to manually send another update message to items that moved after move is complete on the next run loop.
            // (because it may crash if you try to update an item that is moving in the same batch updates...)
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadRowsAtIndexPaths:@[change.destinationIndexPath] withRowAnimation:change.rowAnimation];
            });
            
            [self moveRowAtIndexPath:change.currentIndexPath toIndexPath:change.destinationIndexPath];
            break;
        }
            
        case NSFetchedResultsChangeUpdate:
        {
            [self reloadRowsAtIndexPaths:@[change.currentIndexPath] withRowAnimation:change.rowAnimation];
            break;
        }
    }
}

- (id)cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self cellForRowAtIndexPath:indexPath];
}

- (id)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath
{
    return [self dequeueReusableCellWithIdentifier:identifier forIndexPath:indexPath];
}

#pragma mark - Getters/Setters -

- (Protocol *)dataSourceProtocol
{
    return @protocol(UITableViewDataSource);
}

@end
