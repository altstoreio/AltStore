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

private extension UIAction.Identifier
{
    static let showDetails = UIAction.Identifier("io.altstore.showDetails")
    static let showError = UIAction.Identifier("io.altstore.showError")
}

class SourcesViewController: UICollectionViewController
{
    var deepLinkSourceURL: URL? {
        didSet {
            self.handleAddSourceDeepLink()
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    private var placeholderView: RSTPlaceholderView!
    private var placeholderViewButton: UIButton!
    private var placeholderViewCenterYConstraint: NSLayoutConstraint!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.navigationController?.view.tintColor = .altPrimary
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        self.collectionView.allowsSelectionDuringEditing = false
        
        let backgroundView = UIView(frame: .zero)
        backgroundView.backgroundColor = .altBackground
        self.collectionView.backgroundView = backgroundView
        
        self.placeholderView = RSTPlaceholderView(frame: .zero)
        self.placeholderView.translatesAutoresizingMaskIntoConstraints = false
        self.placeholderView.textLabel.text = NSLocalizedString("Add More Sources!", comment: "")
        self.placeholderView.detailTextLabel.text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Duis massa tortor, tempor vel est vitae, consequat luctus arcu."
        backgroundView.addSubview(self.placeholderView)
        
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).bolded()
        self.placeholderView.textLabel.font = UIFont(descriptor: fontDescriptor, size: 0.0)
        self.placeholderView.detailTextLabel.font = UIFont.preferredFont(forTextStyle: .body)
        self.placeholderView.detailTextLabel.textAlignment = .natural
        
        self.placeholderViewButton = UIButton(type: .system, primaryAction: UIAction(title: NSLocalizedString("View Recommended Sources", comment: "")) { [weak self] _ in
            self?.performSegue(withIdentifier: "addSource", sender: nil)
        })
        self.placeholderViewButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.placeholderView.stackView.spacing = 15
        self.placeholderView.stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        self.placeholderView.stackView.isLayoutMarginsRelativeArrangement = true
        self.placeholderView.stackView.addArrangedSubview(self.placeholderViewButton)
        
        self.placeholderViewCenterYConstraint = self.placeholderView.safeAreaLayoutGuide.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            self.placeholderViewCenterYConstraint,
            self.placeholderView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            self.placeholderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            self.placeholderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            
            self.placeholderView.leadingAnchor.constraint(equalTo: self.placeholderView.stackView.leadingAnchor),
            self.placeholderView.trailingAnchor.constraint(equalTo: self.placeholderView.stackView.trailingAnchor),
            self.placeholderView.topAnchor.constraint(equalTo: self.placeholderView.stackView.topAnchor),
            self.placeholderView.bottomAnchor.constraint(equalTo: self.placeholderView.stackView.bottomAnchor),
        ])

        self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        self.update()
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        self.handleAddSourceDeepLink()
    }
    
    override func viewDidLayoutSubviews() 
    {
        super.viewDidLayoutSubviews()
        
        // Vertically center placeholder view in gap below first item.
        
        let indexPath = IndexPath(item: 0, section: 0)
        guard let layoutAttributes = self.collectionView.layoutAttributesForItem(at: indexPath) else { return }
        
        let maxY = layoutAttributes.frame.maxY
        
        let constant = maxY / 2
        if self.placeholderViewCenterYConstraint.constant != constant
        {
            self.placeholderViewCenterYConstraint.constant = constant
        }
    }
}

private extension SourcesViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
        configuration.headerMode = .supplementary
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self else { return UISwipeActionsConfiguration(actions: []) }
            
            let source = self.dataSource.item(at: indexPath)
            var actions: [UIContextualAction] = []
            
            if source.identifier != Source.altStoreIdentifier
            {
                // Prevent users from removing AltStore source.
                
                let removeAction = UIContextualAction(style: .destructive,
                                                      title: NSLocalizedString("Remove", comment: "")) { _, _, completion in
                    self.remove(source, completionHandler: completion)
                }
                removeAction.image = UIImage(systemName: "trash.fill")
                
                actions.append(removeAction)
            }
            
            if let error = source.error
            {
                let viewErrorAction = UIContextualAction(style: .normal,
                                                         title: NSLocalizedString("View Error", comment: "")) { _, _, completion in
                    self.present(error)
                    completion(true)
                }
                viewErrorAction.backgroundColor = .systemYellow
                viewErrorAction.image = UIImage(systemName: "exclamationmark.circle.fill")
                
                actions.append(viewErrorAction)
            }
            
            let config = UISwipeActionsConfiguration(actions: actions)
            config.performsFirstActionWithFullSwipe = false
            
            return config
        }
        
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
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
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<Source, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, source, indexPath) in
            guard let self else { return }
                        
            let cell = cell as! AppBannerCollectionViewCell
            cell.layoutMargins.top = 5
            cell.layoutMargins.bottom = 5
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.bannerView.configure(for: source)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            
            let numberOfApps: Int
            if let patreonAccount = DatabaseManager.shared.patreonAccount(), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
            {
                numberOfApps = source.apps.count
            }
            else
            {
                numberOfApps = source.apps.filter { !$0.isBeta }.count
            }
            
            if let error = source.error
            {
                let image = UIImage(systemName: "exclamationmark")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                
                cell.bannerView.button.setImage(image, for: .normal)
                cell.bannerView.button.setTitle(nil, for: .normal)
                cell.bannerView.button.tintColor = .systemYellow.withAlphaComponent(0.75)
                
                let action = UIAction(identifier: .showError) { _ in
                    self.present(error)
                }
                cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
                cell.bannerView.button.removeAction(identifiedBy: .showDetails, for: .primaryActionTriggered)
            }
            else
            {
                cell.bannerView.button.setImage(nil, for: .normal)
                cell.bannerView.button.setTitle(numberOfApps.description, for: .normal)
                cell.bannerView.button.tintColor = .white.withAlphaComponent(0.2)
                
                let action = UIAction(identifier: .showDetails) { _ in
                    self.showSourceDetails(for: source)
                }
                cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
                cell.bannerView.button.removeAction(identifiedBy: .showError, for: .primaryActionTriggered)
            }
            
            let dateText: String
            if let lastUpdatedDate = source.lastUpdatedDate
            {
                dateText = Date().relativeDateString(since: lastUpdatedDate, dateFormatter: self.dateFormatter)
            }
            else
            {
                dateText = NSLocalizedString("Never", comment: "")
            }
                            
            let text = String(format: NSLocalizedString("Last Updated: %@", comment: ""), dateText)
            cell.bannerView.subtitleLabel.text = text
            cell.bannerView.subtitleLabel.numberOfLines = 1
            
            let numberOfAppsText: String
            if #available(iOS 15, *)
            {
                let attributedOutput = AttributedString(localized: "^[\(numberOfApps) app](inflect: true)")
                numberOfAppsText = String(attributedOutput.characters)
            }
            else
            {
                numberOfAppsText = ""
            }
            
            let accessibilityLabel = source.name + "\n" + text + ".\n" + numberOfAppsText
            cell.bannerView.accessibilityLabel = accessibilityLabel
                        
            if source.identifier != Source.altStoreIdentifier
            {
                cell.accessories = [.delete(displayed: .whenEditing)]
            }
            else
            {
                cell.accessories = []
            }
            
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

private extension SourcesViewController
{
    func handleAddSourceDeepLink()
    {
        guard let url = self.deepLinkSourceURL, self.view.window != nil else { return }
        
        // Only handle deep link once.
        self.deepLinkSourceURL = nil
        
        self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
        
        func finish(_ result: Result<Void, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .success: break
                case .failure(OperationError.cancelled): break
                    
                case .failure(var error as SourceError):
                    let title = String(format: NSLocalizedString("“%@” could not be added to AltStore.", comment: ""), error.$source.name)
                    error.errorTitle = title
                    self.present(error)
                    
                case .failure(let error as NSError):
                    self.present(error.withLocalizedTitle(NSLocalizedString("Unable to Add Source", comment: "")))
                }
                
                self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
            }
        }
        
        AppManager.shared.fetchSource(sourceURL: url) { (result) in
            do
            {
                // Use @Managed before calling perform() to keep
                // strong reference to source.managedObjectContext.
                @Managed var source = try result.get()
                
                DispatchQueue.main.async {
                    self.showSourceDetails(for: source)
                }
                
                finish(.success(()))
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
        let title = nsError.localizedTitle // OK if nil.
        let message = [nsError.localizedDescription, nsError.localizedDebugDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func remove(_ source: Source, completionHandler: ((Bool) -> Void)? = nil)
    {
        Task<Void, Never> {
            do
            {
                try await AppManager.shared.remove(source, presentingViewController: self)
                
                completionHandler?(true)
            }
            catch is CancellationError
            {
                completionHandler?(false)
            }
            catch
            {
                completionHandler?(false)
                
                self.present(error)
            }
        }
    }
    
    func showSourceDetails(for source: Source)
    {
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
    
    func update()
    {
        if self.dataSource.itemCount < 2
        {
            // Show placeholder view
            
            self.placeholderView.isHidden = false
            self.collectionView.alwaysBounceVertical = false
            
            self.setEditing(false, animated: true)
            self.editButtonItem.isEnabled = false
        }
        else
        {
            self.placeholderView.isHidden = true
            self.collectionView.alwaysBounceVertical = true
            
            self.editButtonItem.isEnabled = true
        }
    }
}

extension SourcesViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        self.collectionView.deselectItem(at: indexPath, animated: true)
        
        let source = self.dataSource.item(at: indexPath)
        self.showSourceDetails(for: source)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
        
        var configuation = UIListContentConfiguration.cell()
        configuation.text = NSLocalizedString("Sources control what apps are available to download through AltStore.", comment: "")
        configuation.textProperties.color = .secondaryLabel
        configuation.textProperties.alignment = .natural
        
        headerView.contentConfiguration = configuation
        
        return headerView
    }
}

extension SourcesViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) 
    {
        self.dataSource.controllerWillChangeContent(controller)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) 
    {
        self.update()
        
        self.dataSource.controllerDidChangeContent(controller)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) 
    {
        self.dataSource.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) 
    {
        self.dataSource.controller(controller, didChange: sectionInfo, atSectionIndex: UInt(sectionIndex), for: type)
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let storyboard = UIStoryboard(name: "Sources", bundle: nil)
    let sourcesViewController = storyboard.instantiateInitialViewController()!
    
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
        do
        {
            let (sources, context) = try result.get()
            try context.save()
        }
        catch
        {
            print("Preview failed to fetch sources:", error)
        }
    }
    
    return sourcesViewController
}
