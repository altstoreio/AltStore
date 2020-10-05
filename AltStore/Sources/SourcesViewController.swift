//
//  SourcesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/17/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import CoreData

import AltStoreCore
import Roxas

struct SourceError: LocalizedError
{
    enum Code
    {
        case unsupported
    }
    
    var code: Code
    @Managed var source: Source
    
    var errorDescription: String? {
        switch self.code
        {
        case .unsupported: return String(format: NSLocalizedString("The source “%@” is not supported by this version of AltStore.", comment: ""), self.$source.name)
        }
    }
}

class SourcesViewController: UICollectionViewController
{
    var deepLinkSourceURL: URL? {
        didSet {
            guard let sourceURL = self.deepLinkSourceURL else { return }
            self.addSource(url: sourceURL)
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
        
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.dataSource = self.dataSource
        
        #if !BETA
        // Hide "Add Source" button for public version while in beta.
        self.navigationItem.leftBarButtonItem = nil
        #endif
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if self.deepLinkSourceURL != nil
        {
            self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
        }
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        if let sourceURL = self.deepLinkSourceURL
        {
            self.addSource(url: sourceURL)
            self.deepLinkSourceURL = nil
        }
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
            cell.bannerView.buttonLabel.isHidden = true
            cell.bannerView.button.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
                                                
            cell.bannerView.titleLabel.text = source.name
            cell.bannerView.subtitleLabel.text = source.sourceURL.absoluteString
            cell.bannerView.subtitleLabel.numberOfLines = 2
            
            cell.errorBadge?.isHidden = (source.error == nil)
            
            let attributedLabel = NSAttributedString(string: source.name + "\n" + source.sourceURL.absoluteString, attributes: [.accessibilitySpeechPunctuation: true])
            cell.bannerView.accessibilityAttributedLabel = attributedLabel
            cell.bannerView.accessibilityTraits.remove(.button)
            
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
        let alertController = UIAlertController(title: NSLocalizedString("Add Source", comment: ""), message: nil, preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.placeholder = "https://apps.altstore.io"
            textField.textContentType = .URL
        }
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { (action) in
            guard let text = alertController.textFields![0].text else { return }
            guard var sourceURL = URL(string: text) else { return }
            if sourceURL.scheme == nil {
                guard let httpsSourceURL = URL(string: "https://" + text) else { return }
                sourceURL = httpsSourceURL
            }
            self.addSource(url: sourceURL)
        })
        
        self.present(alertController, animated: true, completion: nil)
    }

    func addSource(url: URL)
    {
        guard self.view.window != nil else { return }
        
        self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
        
        func finish(error: Error?)
        {
            DispatchQueue.main.async {
                if let error = error
                {
                    self.present(error)
                }
                
                self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
            }
        }
        
        AppManager.shared.fetchSource(sourceURL: url) { (result) in
            do
            {
                let source = try result.get()
                let sourceName = source.name
                let managedObjectContext = source.managedObjectContext
                
                #if !BETA
                guard Source.allowedIdentifiers.contains(source.identifier) else { throw SourceError(code: .unsupported, source: source) }
                #endif
                
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName),
                                                            message: NSLocalizedString("Sources control what apps appear in AltStore. Make sure to only add sources that you trust.", comment: ""), preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                        finish(error: nil)
                    })
                    alertController.addAction(UIAlertAction(title: UIAlertAction.ok.title, style: UIAlertAction.ok.style) { _ in
                        managedObjectContext?.perform {
                            do
                            {
                                try managedObjectContext?.save()
                                finish(error: nil)
                            }
                            catch
                            {
                                finish(error: error)
                            }
                        }
                    })
                    self.present(alertController, animated: true, completion: nil)
                }
            }
            catch
            {
                finish(error: error)
            }
        }
    }
    
    func present(_ error: Error)
    {
        if let transitionCoordinator = self.transitionCoordinator
        {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                self.present(error)
            }
            
            return
        }
        
        let nsError = error as NSError
        let message = nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? nsError.localizedRecoverySuggestion
        
        let alertController = UIAlertController(title: error.localizedDescription, message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
}

extension SourcesViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        self.collectionView.deselectItem(at: indexPath, animated: true)
        
        let source = self.dataSource.item(at: indexPath)
        guard let error = source.error else { return }
        
        self.present(error)
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

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { (suggestedActions) -> UIMenu? in
            let viewErrorAction = UIAction(title: NSLocalizedString("View Error", comment: ""), image: UIImage(systemName: "exclamationmark.circle")) { (action) in
                guard let error = source.error else { return }
                self.present(error)
            }
            
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
            
            var actions: [UIAction] = []
            
            if source.error != nil
            {
                actions.append(viewErrorAction)
            }
            
            if source.identifier != Source.altStoreIdentifier
            {
                actions.append(deleteAction)
            }            

            let menu = UIMenu(title: "", children: actions)
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
