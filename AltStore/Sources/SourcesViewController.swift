//
//  SourcesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/17/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import CoreData

import Roxas

class SourcesViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
        
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.dataSource = self.dataSource
    }
}

private extension SourcesViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewDataSource<Source>
    {
        let fetchRequest = Source.fetchRequest() as NSFetchRequest<Source>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Source.name, ascending: true),
                                        NSSortDescriptor(keyPath: \Source.sourceURL, ascending: true),
                                        NSSortDescriptor(keyPath: \Source.identifier, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewDataSource<Source>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { (cell, source, indexPath) in
            let tintColor = UIColor.altPrimary
            
            let cell = cell as! BannerCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
                        
            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.betaBadgeView.isHidden = true
            cell.bannerView.buttonLabel.isHidden = true
            cell.bannerView.button.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
                                                
            cell.bannerView.titleLabel.text = source.name
            cell.bannerView.subtitleLabel.text = source.sourceURL.absoluteString
            cell.bannerView.subtitleLabel.numberOfLines = 2
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        
        return dataSource
    }
}

private extension SourcesViewController
{
    @IBAction func addSource()
    {
        func addSource(url: URL)
        {
            AppManager.shared.fetchSource(sourceURL: url) { (result) in
                do
                {
                    let source = try result.get()
                    try source.managedObjectContext?.save()
                }
                catch let error as NSError
                {
                    let error = error.withLocalizedFailure(NSLocalizedString("Could not add source.", comment: ""))
                    
                    DispatchQueue.main.async {
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                    }
                }
            }
        }
        
        let alertController = UIAlertController(title: NSLocalizedString("Add Source", comment: ""), message: nil, preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.placeholder = "https://apps.altstore.io"
            textField.textContentType = .URL
        }
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { (action) in
            guard let text = alertController.textFields![0].text, let sourceURL = URL(string: text) else { return }
            addSource(url: sourceURL)
        })
        
        self.present(alertController, animated: true, completion: nil)
    }
}

extension SourcesViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: collectionView.bounds.width, height: 80)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let indexPath = IndexPath(row: 0, section: section)
        let headerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader, at: indexPath)
        
        // Use this view to calculate the optimal size based on the collection view's width
        let size = headerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
                                                      withHorizontalFittingPriority: .required, // Width is fixed
                                                      verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
        return size
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! TextCollectionReusableView
        headerView.layoutMargins.left = self.view.layoutMargins.left
        headerView.layoutMargins.right = self.view.layoutMargins.right
        return headerView
    }
}

@available(iOS 13, *)
extension SourcesViewController
{
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
    {
        let source = self.dataSource.item(at: indexPath)
        guard source.identifier != Source.altStoreIdentifier else { return nil }

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { (suggestedActions) -> UIMenu? in
            let deleteAction = UIAction(title: NSLocalizedString("Remove", comment: ""), image: UIImage(systemName: "trash"), attributes: [.destructive]) { (action) in
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let source = context.object(with: source.objectID) as! Source
                    context.delete(source)
                    
                    do
                    {
                        try context.save()
                    }
                    catch
                    {
                        print("Failed to save source context.", error)
                    }
                }
            }

            let menu = UIMenu(title: "", children: [deleteAction])
            return menu
        }
    }

    override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    {
        guard let indexPath = configuration.identifier as? NSIndexPath else { return nil }
        guard let cell = collectionView.cellForItem(at: indexPath as IndexPath) as? BannerCollectionViewCell else { return nil }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bannerView.bounds, cornerRadius: cell.bannerView.layer.cornerRadius)

        let preview = UITargetedPreview(view: cell.bannerView, parameters: parameters)
        return preview
    }

    override func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    {
        return self.collectionView(collectionView, previewForHighlightingContextMenuWithConfiguration: configuration)
    }
}
