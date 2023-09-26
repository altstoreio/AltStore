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

import Nuke

class MySourcesViewController: UICollectionViewController
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
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.view.tintColor = .altPrimary
        self.navigationController?.view.tintColor = .altPrimary
        
        if let navigationBar = self.navigationController?.navigationBar as? NavigationBar
        {
            // Don't automatically adjust item positions when being presented non-full screen,
            // or else the navigation bar content won't be vertically centered.
            navigationBar.automaticallyAdjustsItemPositions = false
        }
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
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
        }
    }
}

private extension MySourcesViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.headerMode = .supplementary
            configuration.showsSeparators = false
            configuration.backgroundColor = .altBackground
            configuration.headerTopPadding = 0
            
            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
//            layoutSection.contentInsets.top = 4
            return layoutSection
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let fetchRequest = Source.fetchRequest() as NSFetchRequest<Source>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Source.name, ascending: true),
                                        
                                        // Can't sort by URLs or else app will crash.
                                        // NSSortDescriptor(keyPath: \Source.sourceURL, ascending: true),
                                        
                                        NSSortDescriptor(keyPath: \Source.identifier, ascending: true)]
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<Source, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, source, indexPath) in
            guard let self else { return }
            
            let tintColor = source.effectiveTintColor ?? .altPrimary
            
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.style = .source
            cell.layoutMargins.top = 5
            cell.layoutMargins.bottom = 5
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            
            cell.bannerView.button.isHidden = true
            cell.bannerView.buttonLabel.isHidden = true
                                                
            cell.bannerView.titleLabel.text = source.name
            
            if #available(iOS 15, *)
            {
                let dateText: String
                
                if let lastUpdatedDate = source.lastUpdatedDate
                {
                    dateText = lastUpdatedDate.formatted(.relative(presentation: .named)).capitalized
                }
                else
                {
                    dateText = NSLocalizedString("Never", comment: "")
                }
                                
                let text = String(format: NSLocalizedString("Last Updated: %@", comment: ""), dateText)
                cell.bannerView.subtitleLabel.text = text
                cell.bannerView.subtitleLabel.numberOfLines = 1
                
                let attributedLabel = NSAttributedString(string: source.name + "\n" + text)
                cell.bannerView.accessibilityAttributedLabel = attributedLabel
            }
            else
            {
                cell.bannerView.subtitleLabel.text = source.sourceURL.absoluteString
                cell.bannerView.subtitleLabel.numberOfLines = 2
                
                let attributedLabel = NSAttributedString(string: source.name + "\n" + source.sourceURL.absoluteString, attributes: [.accessibilitySpeechPunctuation: true])
                cell.bannerView.accessibilityAttributedLabel = attributedLabel
            }
            
            cell.errorBadge?.isHidden = (source.error == nil)
            
            cell.bannerView.accessibilityTraits.remove(.button)
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        dataSource.prefetchHandler = { (source, indexPath, completionHandler) in
            guard let imageURL = source.effectiveIconURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
    
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        return sourceDetailViewController
    }
}

private extension MySourcesViewController
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
    
    func addSource(url: URL, completionHandler: ((Result<Void, Error>) -> Void)? = nil)
    {
        guard self.view.window != nil else { return }
        
        if url == self.deepLinkSourceURL
        {
            // Only handle deep link once.
            self.deepLinkSourceURL = nil
        }
        
//        func finish(_ result: Result<Void, Error>)
//        {
//            DispatchQueue.main.async {
//                switch result
//                {
//                case .success: break
//                case .failure(OperationError.cancelled): break
//
//                case .failure(var error as SourceError):
//                    let title = String(format: NSLocalizedString("“%@” could not be added to AltStore.", comment: ""), error.$source.name)
//                    error.errorTitle = title
//                    self.present(error)
//
//                case .failure(let error as NSError):
//                    self.present(error.withLocalizedTitle(NSLocalizedString("Unable to Add Source", comment: "")))
//                }
//
//                self.collectionView.reloadSections([Section.trusted.rawValue])
//
//                completionHandler?(result)
//            }
//        }
//
//        var dependencies: [Foundation.Operation] = []
//        if let fetchTrustedSourcesOperation = self.fetchTrustedSourcesOperation
//        {
//            // Must fetch trusted sources first to determine whether this is a trusted source.
//            // We assume fetchTrustedSources() has already been called before this method.
//            dependencies = [fetchTrustedSourcesOperation]
//        }
//
//        AppManager.shared.fetchSource(sourceURL: url, dependencies: dependencies) { (result) in
//            do
//            {
//                // Use @Managed before calling perform() to keep
//                // strong reference to source.managedObjectContext.
//                @Managed var source = try result.get()
//
//                let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
//                backgroundContext.perform {
//                    do
//                    {
//                        let predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), $source.identifier)
//                        if let existingSource = Source.first(satisfying: predicate, in: backgroundContext)
//                        {
//                            throw SourceError.duplicate(source, existingSource: existingSource)
//                        }
//
//                        DispatchQueue.main.async {
//                            self.showSourceDetails(for: source)
//                        }
//
//                        finish(.success(()))
//                    }
//                    catch
//                    {
//                        finish(.failure(error))
//                    }
//                }
//            }
//            catch
//            {
//                finish(.failure(error))
//            }
//        }
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
        let title = nsError.localizedTitle // OK if nil.
        let message = [nsError.localizedDescription, nsError.localizedDebugDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func remove(_ source: Source)
    {
        Task<Void, Never> { @MainActor in
            do
            {
                try await AppManager.shared.remove(source, presentingViewController: self)
            }
            catch
            {
                self.present(error)
            }
        }
    }
    
    func showSourceDetails(for source: Source)
    {
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
}

extension MySourcesViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        self.collectionView.deselectItem(at: indexPath, animated: true)
        
        let source = self.dataSource.item(at: indexPath)
        self.showSourceDetails(for: source)
    }
}

extension MySourcesViewController: UICollectionViewDelegateFlowLayout
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let reuseIdentifier = (kind == UICollectionView.elementKindSectionHeader) ? "Header" : "Footer"
        
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as! TextCollectionReusableView
        headerView.layoutMargins.left = self.view.layoutMargins.left
        headerView.layoutMargins.right = self.view.layoutMargins.right
        
        /* Changing NSLayoutConstraint priorities from required to optional (and vice versa) isn’t supported, and crashes on iOS 12. */
        // let almostRequiredPriority = UILayoutPriority(UILayoutPriority.required.rawValue - 1) // Can't be required or else we can't satisfy constraints when hidden (size = 0).
        // headerView.leadingLayoutConstraint?.priority = almostRequiredPriority
        // headerView.trailingLayoutConstraint?.priority = almostRequiredPriority
        // headerView.topLayoutConstraint?.priority = almostRequiredPriority
        // headerView.bottomLayoutConstraint?.priority = almostRequiredPriority
        
        headerView.textLabel.text = NSLocalizedString("Sources control what apps are available to download through AltStore.", comment: "")
        headerView.textLabel.font = UIFont.preferredFont(forTextStyle: .callout)
        headerView.textLabel.textAlignment = .natural
        
        headerView.topLayoutConstraint.constant = 15
        headerView.bottomLayoutConstraint.constant = 15
                
        return headerView
    }
}

extension MySourcesViewController
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
            
            var actions: [UIAction] = []
            
            if source.error != nil
            {
                actions.append(viewErrorAction)
            }
            
            if source.identifier != Source.altStoreIdentifier
            {
                actions.append(deleteAction)
            }
            
            actions.append(deleteAction)
            
            guard !actions.isEmpty else { return nil }
            
            let menu = UIMenu(title: "", children: actions)
            return menu
        }
    }

    override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    {
        guard let indexPath = configuration.identifier as? NSIndexPath else { return nil }
        guard let cell = collectionView.cellForItem(at: indexPath as IndexPath) as? AppBannerCollectionViewCell else { return nil }

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

#Preview(traits: .portrait) {
    DatabaseManager.shared.startSynchronously()
    
    let storyboard = UIStoryboard(name: "Sources", bundle: nil)
    let sourcesViewController = storyboard.instantiateViewController(identifier: "mySourcesViewController")
    
    let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
    context.performAndWait {
        _ = Source.make(name: "OatmealDome's AltStore Source",
                        identifier: "me.oatmealdome.altstore",
                        sourceURL: URL(string: "https://altstore.oatmealdome.me")!,
                        context: context)
        
        _ = Source.make(name: "UTM Repository",
                        identifier: "com.utmapp.repos.UTM",
                        sourceURL: URL(string: "https://alt.getutm.app")!,
                        context: context)
        
        _ = Source.make(name: "Flyinghead",
                        identifier: "com.flyinghead.source",
                        sourceURL: URL(string: "https://flyinghead.github.io/flycast-builds/altstore.json")!,
                        context: context)
        
        _ = Source.make(name: "Provenance",
                        identifier: "org.provenance-emu.AltStore",
                        sourceURL: URL(string: "https://provenance-emu.com/apps.json")!,
                        context: context)
        
        _ = Source.make(name: "PojavLauncher Repository",
                        identifier: "dev.crystall1ne.repos.PojavLauncher",
                        sourceURL: URL(string: "http://alt.crystall1ne.dev")!,
                        context: context)
        
        try! context.save()
    }
    
    AppManager.shared.fetchSources { result in
        print("[RSTLog] Preview fetched sources!")
        
        do
        {
            let (sources, context) = try result.get()
            
            try context.save()
            
            print("[RSTLog] Preview fetched sources!", sources.count)
        }
        catch
        {
            print("[RSTLog] Preview failed to fetch sources:", error)
        }
    }
    
    let navigationController = UINavigationController(rootViewController: sourcesViewController)
    return navigationController
}
