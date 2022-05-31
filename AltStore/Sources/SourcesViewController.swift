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

@objc(SourcesFooterView)
private class SourcesFooterView: TextCollectionReusableView
{
    @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet var textView: UITextView!
}

extension SourcesViewController
{
    private enum Section: Int, CaseIterable
    {
        case added
        case trusted
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
    private lazy var addedSourcesDataSource = self.makeAddedSourcesDataSource()
    private lazy var trustedSourcesDataSource = self.makeTrustedSourcesDataSource()
    
    private var fetchTrustedSourcesOperation: FetchTrustedSourcesOperation?
    private var fetchTrustedSourcesResult: Result<Void, Error>?
    private var _fetchTrustedSourcesContext: NSManagedObjectContext?
        
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
        
        if self.fetchTrustedSourcesOperation == nil
        {
            self.fetchTrustedSources()
        }
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        if let sourceURL = self.deepLinkSourceURL
        {
            self.addSource(url: sourceURL)
        }
    }
}

private extension SourcesViewController
{
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<Source>
    {
        let dataSource = RSTCompositeCollectionViewDataSource<Source>(dataSources: [self.addedSourcesDataSource, self.trustedSourcesDataSource])
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { (cell, source, indexPath) in
            let tintColor = UIColor.altPrimary
            
            let cell = cell as! BannerCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
                        
            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.buttonLabel.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
            
            switch Section.allCases[indexPath.section]
            {
            case .added:
                cell.bannerView.button.isHidden = true
                
            case .trusted:
                // Quicker way to determine whether a source is already added than by reading from disk.
                if (self.addedSourcesDataSource.fetchedResultsController.fetchedObjects ?? []).contains(where: { $0.identifier == source.identifier })
                {
                    // Source exists in .added section, so hide the button.
                    cell.bannerView.button.isHidden = true
                    
                    if #available(iOS 13.0, *)
                    {
                        let configuation = UIImage.SymbolConfiguration(pointSize: 24)
                        
                        let imageAttachment = NSTextAttachment()
                        imageAttachment.image = UIImage(systemName: "checkmark.circle", withConfiguration: configuation)?.withTintColor(.altPrimary)

                        let attributedText = NSAttributedString(attachment: imageAttachment)
                        cell.bannerView.buttonLabel.attributedText = attributedText
                        cell.bannerView.buttonLabel.textAlignment = .center
                        cell.bannerView.buttonLabel.isHidden = false
                    }
                }
                else
                {
                    // Source does not exist in .added section, so show the button.
                    cell.bannerView.button.isHidden = false
                    cell.bannerView.buttonLabel.attributedText = nil
                }
                
                cell.bannerView.button.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
                cell.bannerView.button.addTarget(self, action: #selector(SourcesViewController.addTrustedSource(_:)), for: .primaryActionTriggered)
            }
                                                
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
    
    func makeAddedSourcesDataSource() -> RSTFetchedResultsCollectionViewDataSource<Source>
    {
        let fetchRequest = Source.fetchRequest() as NSFetchRequest<Source>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Source.name, ascending: true),
                                        NSSortDescriptor(keyPath: \Source.sourceURL, ascending: true),
                                        NSSortDescriptor(keyPath: \Source.identifier, ascending: true)]
        
        let dataSource = RSTFetchedResultsCollectionViewDataSource<Source>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        return dataSource
    }
    
    func makeTrustedSourcesDataSource() -> RSTArrayCollectionViewDataSource<Source>
    {
        let dataSource = RSTArrayCollectionViewDataSource<Source>(items: [])
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
            
            self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
            
            self.addSource(url: sourceURL) { _ in
                self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
            }
        })
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func addSource(url: URL, isTrusted: Bool = false, completionHandler: ((Result<Void, Error>) -> Void)? = nil)
    {
        guard self.view.window != nil else { return }
        
        if url == self.deepLinkSourceURL
        {
            // Only handle deep link once.
            self.deepLinkSourceURL = nil
        }
        
        func finish(_ result: Result<Void, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .success: break
                case .failure(OperationError.cancelled): break
                case .failure(let error): self.present(error)
                }
                
                self.collectionView.reloadSections([Section.trusted.rawValue])
                
                completionHandler?(result)
            }
        }
        
        var dependencies: [Foundation.Operation] = []
        if let fetchTrustedSourcesOperation = self.fetchTrustedSourcesOperation
        {
            // Must fetch trusted sources first to determine whether this is a trusted source.
            // We assume fetchTrustedSources() has already been called before this method.
            dependencies = [fetchTrustedSourcesOperation]
        }
        
        AppManager.shared.fetchSource(sourceURL: url, dependencies: dependencies) { (result) in
            do
            {
                let source = try result.get()
                let sourceName = source.name
                let managedObjectContext = source.managedObjectContext
                
                #if !BETA
                guard let trustedSourceIDs = UserDefaults.shared.trustedSourceIDs, trustedSourceIDs.contains(source.identifier) else { throw SourceError(code: .unsupported, source: source) }
                #endif
                
                // Hide warning when adding a featured trusted source.
                let message = isTrusted ? nil : NSLocalizedString("Make sure to only add sources that you trust.", comment: "")
                
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName),
                                                            message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                        finish(.failure(OperationError.cancelled))
                    })
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Add Source", comment: ""), style: UIAlertAction.ok.style) { _ in
                        managedObjectContext?.perform {
                            do
                            {
                                try managedObjectContext?.save()
                                finish(.success(()))
                            }
                            catch
                            {
                                finish(.failure(error))
                            }
                        }
                    })
                    self.present(alertController, animated: true, completion: nil)
                }
            }
            catch
            {
                finish(.failure(error))
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
    
    func fetchTrustedSources()
    {
        func finish(_ result: Result<[Source], Error>)
        {
            self.fetchTrustedSourcesResult = result.map { _ in () }
            
            DispatchQueue.main.async {
                do
                {
                    let sources = try result.get()
                    print("Fetched trusted sources:", sources.map { $0.identifier })

                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self.trustedSourcesDataSource.setItems(sources, with: [sectionUpdate])
                }
                catch
                {
                    print("Error fetching trusted sources:", error)
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self.trustedSourcesDataSource.setItems([], with: [sectionUpdate])
                }
            }
        }
        
        self.fetchTrustedSourcesOperation = AppManager.shared.fetchTrustedSources { result in
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success(let trustedSources):
                // Cache trusted source IDs.
                UserDefaults.shared.trustedSourceIDs = trustedSources.map { $0.identifier }
                
                // Don't show sources without a sourceURL.
                let featuredSourceURLs = trustedSources.compactMap { $0.sourceURL }
                
                // This context is never saved, but keeps the managed sources alive.
                let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
                self._fetchTrustedSourcesContext = context
                
                let dispatchGroup = DispatchGroup()
                
                var sourcesByURL = [URL: Source]()
                var fetchError: Error?
                
                for sourceURL in featuredSourceURLs
                {
                    dispatchGroup.enter()
                    
                    AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                        // Serialize access to sourcesByURL.
                        context.performAndWait {
                            switch result
                            {
                            case .failure(let error): fetchError = error
                            case .success(let source): sourcesByURL[source.sourceURL] = source
                            }
                            
                            dispatchGroup.leave()
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    if let error = fetchError
                    {
                        finish(.failure(error))
                    }
                    else
                    {
                        let sources = featuredSourceURLs.compactMap { sourcesByURL[$0] }
                        finish(.success(sources))
                    }
                }
            }
        }
    }
    
    @IBAction func addTrustedSource(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let completedProgress = Progress(totalUnitCount: 1)
        completedProgress.completedUnitCount = 1
        sender.progress = completedProgress
        
        let source = self.dataSource.item(at: indexPath)
        self.addSource(url: source.sourceURL, isTrusted: true) { _ in
            //FIXME: Handle cell reuse.
            sender.progress = nil
        }
    }
    
    func remove(_ source: Source)
    {
        let alertController = UIAlertController(title: String(format: NSLocalizedString("Are you sure you want to remove the source “%@”?", comment: ""), source.name),
                                                message: NSLocalizedString("Any apps you've installed from this source will remain, but they'll no longer receive any app updates.", comment: ""), preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: nil))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove Source", comment: ""), style: .destructive) { _ in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let source = context.object(with: source.objectID) as! Source
                context.delete(source)
                
                do
                {
                    try context.save()
                    
                    DispatchQueue.main.async {
                        self.collectionView.reloadSections([Section.trusted.rawValue])
                    }
                }
                catch
                {
                    DispatchQueue.main.async {
                        self.present(error)
                    }
                }
            }
        })
        
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
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        guard Section(rawValue: section) == .trusted else { return .zero }
        
        let indexPath = IndexPath(row: 0, section: section)
        let headerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionFooter, at: indexPath)
        
        // Use this view to calculate the optimal size based on the collection view's width
        let size = headerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
                                                      withHorizontalFittingPriority: .required, // Width is fixed
                                                      verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
        return size
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let reuseIdentifier = (kind == UICollectionView.elementKindSectionHeader) ? "Header" : "Footer"
        
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as! TextCollectionReusableView
        headerView.layoutMargins.left = self.view.layoutMargins.left
        headerView.layoutMargins.right = self.view.layoutMargins.right
        
        let almostRequiredPriority = UILayoutPriority(UILayoutPriority.required.rawValue - 1) // Can't be required or else we can't satisfy constraints when hidden (size = 0).
        headerView.leadingLayoutConstraint?.priority = almostRequiredPriority
        headerView.trailingLayoutConstraint?.priority = almostRequiredPriority
        headerView.topLayoutConstraint?.priority = almostRequiredPriority
        headerView.bottomLayoutConstraint?.priority = almostRequiredPriority
        
        switch kind
        {
        case UICollectionView.elementKindSectionHeader:
            switch Section.allCases[indexPath.section]
            {
            case .added:
                headerView.textLabel.text = NSLocalizedString("Sources control what apps are available to download through AltStore.", comment: "")
                headerView.textLabel.font = UIFont.preferredFont(forTextStyle: .callout)
                headerView.textLabel.textAlignment = .natural
                
                headerView.topLayoutConstraint.constant = 14
                headerView.bottomLayoutConstraint.constant = 30
                
            case .trusted:
                switch self.fetchTrustedSourcesResult
                {
                case .failure: headerView.textLabel.text = NSLocalizedString("Error Loading Trusted Sources", comment: "")
                case .success, .none: headerView.textLabel.text = NSLocalizedString("Trusted Sources", comment: "")
                }
                
                let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .callout).withSymbolicTraits(.traitBold)!
                headerView.textLabel.font = UIFont(descriptor: descriptor, size: 0)
                headerView.textLabel.textAlignment = .center
                
                headerView.topLayoutConstraint.constant = 54
                headerView.bottomLayoutConstraint.constant = 15
            }
            
        case UICollectionView.elementKindSectionFooter:
            let footerView = headerView as! SourcesFooterView
            let font = UIFont.preferredFont(forTextStyle: .subheadline)
            
            switch self.fetchTrustedSourcesResult
            {
            case .failure(let error):
                footerView.textView.font = font
                footerView.textView.text = error.localizedDescription
                
                footerView.activityIndicatorView.stopAnimating()
                footerView.topLayoutConstraint.constant = 0
                footerView.textView.textAlignment = .center
                
            case .success, .none:
                footerView.textView.delegate = self
                
                let attributedText = NSMutableAttributedString(
                    string: NSLocalizedString("AltStore has reviewed these sources to make sure they meet our safety standards.\n\nSupport for untrusted sources is currently in beta, but you can help test them out by", comment: ""),
                    attributes: [.font: font, .foregroundColor: UIColor.gray]
                )
                attributedText.mutableString.append(" ")
                
                let boldedFont = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold)!, size: font.pointSize)
                let openPatreonURL = URL(string: "https://altstore.io/patreon")!
                
                let joinPatreonText = NSAttributedString(
                    string: NSLocalizedString("joining our Patreon.", comment: ""),
                    attributes: [.font: boldedFont, .link: openPatreonURL, .underlineColor: UIColor.clear]
                )
                attributedText.append(joinPatreonText)
                
                footerView.textView.attributedText = attributedText
                footerView.textView.textAlignment = .natural
                
                if self.fetchTrustedSourcesResult != nil
                {
                    footerView.activityIndicatorView.stopAnimating()
                    footerView.topLayoutConstraint.constant = 20
                }
                else
                {
                    footerView.activityIndicatorView.startAnimating()
                    footerView.topLayoutConstraint.constant = 0
                }
            }
            
        default: break
        }
                
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
                self.remove(source)
            }
            
            let addAction = UIAction(title: String(format: NSLocalizedString("Add “%@”", comment: ""), source.name), image: UIImage(systemName: "plus")) { (action) in
                self.addSource(url: source.sourceURL, isTrusted: true)
            }
            
            var actions: [UIAction] = []
            
            if source.error != nil
            {
                actions.append(viewErrorAction)
            }
            
            switch Section.allCases[indexPath.section]
            {
            case .added:
                if source.identifier != Source.altStoreIdentifier
                {
                    actions.append(deleteAction)
                }
                
            case .trusted:
                if let cell = collectionView.cellForItem(at: indexPath) as? BannerCollectionViewCell, !cell.bannerView.button.isHidden
                {
                    actions.append(addAction)
                }
            }
            
            guard !actions.isEmpty else { return nil }
            
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

extension SourcesViewController: UITextViewDelegate
{
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
    {
        return true
    }
}
