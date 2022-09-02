//
//  RSTCellContentChangeOperation.m
//  Roxas
//
//  Created by Riley Testut on 8/2/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

#import "RSTCellContentChangeOperation.h"

#import "RSTCellContentChange.h"

@implementation RSTCellContentChangeOperation

- (instancetype)initWithChange:(RSTCellContentChange *)change
{
    self = [super init];
    if (self)
    {
        _change = [change copy];
    }
    
    return self;
}

@end


@implementation RSTTableViewChangeOperation

- (instancetype)initWithChange:(RSTCellContentChange *)change tableView:(nullable UITableView *)tableView
{
    self = [super initWithChange:change];
    if (self)
    {
        _tableView = tableView;
    }
    
    return self;
}

- (void)main
{
    switch (self.change.type)
    {
        case NSFetchedResultsChangeInsert:
        {
            if (self.change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:self.change.sectionIndex] withRowAnimation:self.change.rowAnimation];
            }
            else
            {
                [self.tableView insertRowsAtIndexPaths:@[self.change.destinationIndexPath] withRowAnimation:self.change.rowAnimation];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeDelete:
        {
            if (self.change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:self.change.sectionIndex] withRowAnimation:self.change.rowAnimation];
            }
            else
            {
                [self.tableView deleteRowsAtIndexPaths:@[self.change.currentIndexPath] withRowAnimation:self.change.rowAnimation];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeMove:
        {
            [self.tableView moveRowAtIndexPath:self.change.currentIndexPath toIndexPath:self.change.destinationIndexPath];
            break;
        }
            
        case NSFetchedResultsChangeUpdate:
        {
            [self.tableView reloadRowsAtIndexPaths:@[self.change.currentIndexPath] withRowAnimation:self.change.rowAnimation];
            break;
        }
    }
}

@end


@implementation RSTCollectionViewChangeOperation

- (instancetype)initWithChange:(RSTCellContentChange *)change collectionView:(UICollectionView *)collectionView
{
    self = [super initWithChange:change];
    if (self)
    {
        _collectionView = collectionView;
    }

    return self;
}

- (void)main
{
    switch (self.change.type)
    {
        case NSFetchedResultsChangeInsert:
        {
            if (self.change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:self.change.sectionIndex]];
            }
            else
            {
                [self.collectionView insertItemsAtIndexPaths:@[self.change.destinationIndexPath]];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeDelete:
        {
            if (self.change.sectionIndex != RSTUnknownSectionIndex)
            {
                [self.collectionView deleteSections:[NSIndexSet indexSetWithIndex:self.change.sectionIndex]];
            }
            else
            {
                [self.collectionView deleteItemsAtIndexPaths:@[self.change.currentIndexPath]];
            }
            
            break;
        }
            
        case NSFetchedResultsChangeMove:
        {
            [self.collectionView moveItemAtIndexPath:self.change.currentIndexPath toIndexPath:self.change.destinationIndexPath];
            break;
        }
            
        case NSFetchedResultsChangeUpdate:
        {
            [self.collectionView reloadItemsAtIndexPaths:@[self.change.currentIndexPath]];
            break;
        }
    }
}

@end
