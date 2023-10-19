//
//  AddSourceViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/26/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore
import Roxas

import Nuke

private extension UIAction.Identifier
{
    static let addSource = UIAction.Identifier("io.altstore.AddSource")
}

private typealias SourcePreviewResult = (sourceURL: URL, result: Result<Managed<Source>, Error>)

extension AddSourceViewController
{
    private enum Section: Int
    {
        case add
        case preview
        case recommended
    }
    
    private enum ReuseID: String
    {
        case textFieldCell = "TextFieldCell"
        case placeholderFooter = "PlaceholderFooter"
    }
    
    private class ViewModel: ObservableObject
    {
        /* Pipeline */
        @Published
        var sourceAddress: String = ""
        
        @Published
        var sourceURL: URL?

        @Published
        var sourcePreviewResult: SourcePreviewResult?
        
        
        /* State */
        @Published
        var isLoadingPreview: Bool = false
        
        @Published
        var isShowingPreviewStatus: Bool = false
    }
}

class AddSourceViewController: UICollectionViewController 
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var addSourceDataSource = self.makeAddSourceDataSource()
    private lazy var sourcePreviewDataSource = self.makeSourcePreviewDataSource()
    private lazy var recommendedSourcesDataSource = self.makeRecommendedSourcesDataSource()
    
    private var fetchRecommendedSourcesOperation: UpdateKnownSourcesOperation?
    private var fetchRecommendedSourcesResult: Result<Void, Error>?
    private var _fetchRecommendedSourcesContext: NSManagedObjectContext?
    
    private let viewModel = ViewModel()
    private var cancellables: Set<AnyCancellable> = []
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
                
        self.navigationController?.isModalInPresentation = true
        self.navigationController?.view.tintColor = .altPrimary
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(AddSourceTextFieldCell.self, forCellWithReuseIdentifier: ReuseID.textFieldCell.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: UICollectionView.elementKindSectionFooter)
        self.collectionView.register(PlaceholderCollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: ReuseID.placeholderFooter.rawValue)
        
        self.collectionView.backgroundColor = .altBackground
        self.collectionView.keyboardDismissMode = .onDrag
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.startPipeline()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if self.fetchRecommendedSourcesOperation == nil
        {
            self.fetchRecommendedSources()
        }
    }
}

private extension AddSourceViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .safeArea
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self, let section = Section(rawValue: sectionIndex) else { return nil }
            switch section
            {
            case .add:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(20))
                let headerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.boundarySupplementaryItems = [headerItem]
                return layoutSection
                
            case .preview:
                var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                
                if self.viewModel.sourceURL != nil && self.viewModel.isShowingPreviewStatus
                {
                    switch self.viewModel.sourcePreviewResult
                    {
                    case (_, .success)?: configuration.footerMode = .none
                    case (_, .failure)?: configuration.footerMode = .supplementary
                    case nil where self.viewModel.isLoadingPreview: configuration.footerMode = .supplementary
                    default: configuration.footerMode = .none
                    }
                }
                else
                {
                    configuration.footerMode = .none
                }
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
                
            case .recommended:
                var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                
                switch self.fetchRecommendedSourcesResult
                {
                case nil:
                    configuration.headerMode = .supplementary
                    configuration.footerMode = .supplementary
                    
                case .failure: configuration.footerMode = .supplementary
                case .success: configuration.headerMode = .supplementary
                }
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
            }
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>(dataSources: [self.addSourceDataSource, 
                                                                                                        self.sourcePreviewDataSource,
                                                                                                        self.recommendedSourcesDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makeAddSourceDataSource() -> RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 1 }
        dataSource.cellIdentifierHandler = { _ in ReuseID.textFieldCell.rawValue }
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AddSourceTextFieldCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.textField.delegate = self
            
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            
            NotificationCenter.default
                .publisher(for: UITextField.textDidChangeNotification, object: cell.textField)
                .map { ($0.object as? UITextField)?.text ?? "" }
                .assign(to: &self.viewModel.$sourceAddress)
            
                // Results in memory leak
                // .assign(to: \.viewModel.sourceAddress, on: self)
        }
        
        return dataSource
    }
    
    func makeSourcePreviewDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AppBannerCollectionViewCell
            self.configure(cell, with: source)
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
    
    func makeRecommendedSourcesDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AppBannerCollectionViewCell
            self.configure(cell, with: source)
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
}

private extension AddSourceViewController
{
    func startPipeline()
    {
        /* Pipeline */
        
        // Map UITextField text -> URL
        self.viewModel.$sourceAddress
            .map { [weak self] in self?.sourceURL(from: $0) }
            .assign(to: &self.viewModel.$sourceURL)
        
        let showPreviewStatusPublisher = self.viewModel.$isShowingPreviewStatus
            .filter { $0 == true }
        
        let sourceURLPublisher = self.viewModel.$sourceURL
            .removeDuplicates()
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .map { [weak self] sourceURL in
                // Only set sourcePreviewResult to nil if sourceURL actually changes.
                self?.viewModel.sourcePreviewResult = nil
                return sourceURL
            }
        
        // Map URL -> Source Preview
        Publishers.CombineLatest(sourceURLPublisher, showPreviewStatusPublisher.prepend(false))
            .receive(on: RunLoop.main)
            .map { $0.0 }
            .compactMap { [weak self] (sourceURL: URL?) -> AnyPublisher<SourcePreviewResult?, Never>? in
                guard let self else { return nil }
                
                guard let sourceURL else {
                    // Unlike above guard, this continues the pipeline with nil value.
                    return Just(nil).eraseToAnyPublisher()
                }
                
                self.viewModel.isLoadingPreview = true
                return self.fetchSourcePreview(sourceURL: sourceURL).eraseToAnyPublisher()
            }
            .switchToLatest() // Cancels previous publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] sourcePreviewResult in
                self?.viewModel.isLoadingPreview = false
                self?.viewModel.sourcePreviewResult = sourcePreviewResult
            }
            .store(in: &self.cancellables)
        
        
        /* Update UI */
        
        Publishers.CombineLatest(self.viewModel.$isLoadingPreview.removeDuplicates(),
                                 self.viewModel.$isShowingPreviewStatus.removeDuplicates())
        .sink { [weak self] _ in
            guard let self else { return }
            
            // @Published fires _before_ property is updated, so wait until next run loop.
            DispatchQueue.main.async {
                self.collectionView.performBatchUpdates {
                    let indexPath = IndexPath(item: 0, section: Section.preview.rawValue)
                    
                    if let footerView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath) as? PlaceholderCollectionReusableView
                    {
                        self.configure(footerView, with: self.viewModel.sourcePreviewResult)
                    }
                    
                    let context = UICollectionViewLayoutInvalidationContext()
                    context.invalidateSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter, at: [indexPath])
                    self.collectionView.collectionViewLayout.invalidateLayout(with: context)
                }
            }
        }
        .store(in: &self.cancellables)
        
        self.viewModel.$sourcePreviewResult
            .map { $0?.1 }
            .map { result -> Managed<Source>? in
                switch result
                {
                case .success(let source): return source
                case .failure, nil: return nil
                }
            }
            .removeDuplicates { (sourceA: Managed<Source>?, sourceB: Managed<Source>?) in
                sourceA?.identifier == sourceB?.identifier
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] source in
                self?.updateSourcePreview(for: source?.wrappedValue)
            }
            .store(in: &self.cancellables)
        
        let addPublisher = NotificationCenter.default.publisher(for: AppManager.didAddSourceNotification)
        let removePublisher = NotificationCenter.default.publisher(for: AppManager.didRemoveSourceNotification)
        Publishers.Merge(addPublisher, removePublisher)
            .compactMap { notification -> String? in
                guard let source = notification.object as? Source,
                      let context = source.managedObjectContext
                else { return nil }
                
                let sourceID = context.performAndWait { source.identifier }
                return sourceID
            }
            .receive(on: RunLoop.main)
            .compactMap { [dataSource = recommendedSourcesDataSource] sourceID -> IndexPath? in
                guard let index = dataSource.items.firstIndex(where: { $0.identifier == sourceID }) else { return nil }
                
                let indexPath = IndexPath(item: index, section: Section.recommended.rawValue)
                return indexPath
            }
            .sink { [weak self] indexPath in
                // Added or removed a recommended source, so make sure to update its state.
                self?.collectionView.reloadItems(at: [indexPath])
            }
            .store(in: &self.cancellables)
    }
    
    func sourceURL(from address: String) -> URL?
    {
        guard let sourceURL = URL(string: address) else { return nil }
        
        // URLs without hosts are OK (e.g. localhost:8000)
        // guard sourceURL.host != nil else { return }
        
        guard let scheme = sourceURL.scheme else {
            let sanitizedURL = URL(string: "https://" + address)
            return sanitizedURL
        }
        
        guard scheme.lowercased() != "localhost" else {
            let sanitizedURL = URL(string: "http://" + address)
            return sanitizedURL
        }
        
        return sourceURL
    }
    
    func fetchSourcePreview(sourceURL: URL) -> some Publisher<SourcePreviewResult?, Never>
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
        
        var fetchOperation: FetchSourceOperation?
        return Future<Source, Error> { promise in
            fetchOperation = AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                promise(result)
            }
        }
        .map { source in
            let result = SourcePreviewResult(sourceURL, .success(Managed(wrappedValue: source)))
            return result
        }
        .catch { error in
            print("Failed to fetch source for URL \(sourceURL).", error.localizedDescription)
            
            let result = SourcePreviewResult(sourceURL, .failure(error))
            return Just<SourcePreviewResult?>(result)
        }
        .handleEvents(receiveCancel: {
            fetchOperation?.cancel()
        })
    }
    
    func updateSourcePreview(for source: Source?)
    {
        let items = [source].compactMap { $0 }
        
        // Have to provide changes in terms of sourcePreviewDataSource.
        let indexPath = IndexPath(row: 0, section: 0)
        
        if !items.isEmpty && self.sourcePreviewDataSource.items.isEmpty
        {
            let change = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: indexPath)
            self.sourcePreviewDataSource.setItems(items, with: [change])
        }
        else if items.isEmpty && !self.sourcePreviewDataSource.items.isEmpty
        {
            let change = RSTCellContentChange(type: .delete, currentIndexPath: indexPath, destinationIndexPath: nil)
            self.sourcePreviewDataSource.setItems(items, with: [change])
        }
        else if !items.isEmpty && !self.sourcePreviewDataSource.items.isEmpty
        {
            let change = RSTCellContentChange(type: .update, currentIndexPath: indexPath, destinationIndexPath: indexPath)
            self.sourcePreviewDataSource.setItems(items, with: [change])
        }
        
        if source == nil
        {
            self.collectionView.reloadSections([Section.preview.rawValue])
        }
        else
        {
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}

private extension AddSourceViewController
{
    func configure(_ cell: AppBannerCollectionViewCell, with source: Source)
    {
        cell.bannerView.style = .source
        cell.layoutMargins.top = 5
        cell.layoutMargins.bottom = 5
        cell.layoutMargins.left = self.view.layoutMargins.left
        cell.layoutMargins.right = self.view.layoutMargins.right
        cell.contentView.backgroundColor = .altBackground
        
        cell.bannerView.configure(for: source)
        cell.bannerView.subtitleLabel.numberOfLines = 2
        
        cell.bannerView.iconImageView.image = nil
        cell.bannerView.iconImageView.isIndicatingActivity = true
        
        let config = UIImage.SymbolConfiguration(scale: .medium)
        let image = UIImage(systemName: "plus.circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        cell.bannerView.button.setImage(image, for: .normal)
        cell.bannerView.button.setImage(image, for: .highlighted)
        cell.bannerView.button.setTitle(nil, for: .normal)
        cell.bannerView.button.imageView?.contentMode = .scaleAspectFit
        cell.bannerView.button.contentHorizontalAlignment = .fill // Fill entire button with imageView
        cell.bannerView.button.contentVerticalAlignment = .fill
        cell.bannerView.button.contentEdgeInsets = .zero
        cell.bannerView.button.tintColor = .clear
        cell.bannerView.button.isHidden = false
        
        let action = UIAction(identifier: .addSource) { [weak self] _ in
            self?.add(source)
        }
        cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
        
        Task<Void, Never>(priority: .userInitiated) {
            do
            {
                let isAdded = try await source.isAdded
                if isAdded
                {
                    cell.bannerView.button.isHidden = true
                }
            }
            catch
            {
                print("Failed to determine if source is added.", error)
            }
        }
    }
    
    func configure(_ footerView: PlaceholderCollectionReusableView, with sourcePreviewResult: SourcePreviewResult?)
    {
        footerView.placeholderView.stackView.isLayoutMarginsRelativeArrangement = false
        
        footerView.placeholderView.textLabel.textColor = .secondaryLabel
        footerView.placeholderView.textLabel.font = .preferredFont(forTextStyle: .subheadline)
        footerView.placeholderView.textLabel.textAlignment = .center
        
        footerView.placeholderView.detailTextLabel.isHidden = true
        
        switch sourcePreviewResult
        {
        case (let sourceURL, .failure(let previewError))? where self.viewModel.sourceURL == sourceURL && !self.viewModel.isLoadingPreview:
            // The current URL matches the error being displayed, and we're not loading another preview, so show error.
            
            footerView.placeholderView.textLabel.text = (previewError as NSError).localizedDebugDescription ?? previewError.localizedDescription
            footerView.placeholderView.textLabel.isHidden = false
            
            footerView.placeholderView.activityIndicatorView.stopAnimating()
            
        default:
            // The current URL does not match the URL of the source/error being displayed, so show loading indicator.
            
            footerView.placeholderView.textLabel.text = nil
            footerView.placeholderView.textLabel.isHidden = true
            
            footerView.placeholderView.activityIndicatorView.startAnimating()
        }
    }
    
    func fetchRecommendedSources()
    {
        // Closure instead of local function so we can capture `self` weakly.
        let finish: (Result<[Source], Error>) -> Void = { [weak self] result in
            self?.fetchRecommendedSourcesResult = result.map { _ in () }
            
            DispatchQueue.main.async {
                do
                {
                    let sources = try result.get()
                    print("Fetched recommended sources:", sources.map { $0.identifier })
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems(sources, with: [sectionUpdate])
                }
                catch
                {
                    print("Error fetching recommended sources:", error)
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems([], with: [sectionUpdate])
                }
            }
        }
        
        self.fetchRecommendedSourcesOperation = AppManager.shared.updateKnownSources { [weak self] result in
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success((let trustedSources, _)):
                
                // Don't show sources without a sourceURL.
                let featuredSourceURLs = trustedSources.compactMap { $0.sourceURL }
                
                // This context is never saved, but keeps the managed sources alive.
                let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
                self?._fetchRecommendedSourcesContext = context
                
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
                            case .failure(let error):
                                print("Failed to load recommended source \(sourceURL.absoluteString):", error.localizedDescription)
                                fetchError = error
                                
                            case .success(let source): sourcesByURL[source.sourceURL] = source
                            }
                            
                            dispatchGroup.leave()
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    let sources = featuredSourceURLs.compactMap { sourcesByURL[$0] }
                    
                    if let error = fetchError, sources.isEmpty
                    {
                        finish(.failure(error))
                    }
                    else
                    {
                        finish(.success(sources))
                    }
                }
            }
        }
    }
    
    func add(@AsyncManaged _ source: Source)
    {
        Task<Void, Never> {
            do
            {
                let isRecommended = await $source.isRecommended
                if isRecommended
                {
                    try await AppManager.shared.add(source, message: nil, presentingViewController: self)
                }
                else
                {
                    // Use default message
                    try await AppManager.shared.add(source, presentingViewController: self)
                }
                
                self.dismiss()
                
            }
            catch is CancellationError {}
            catch
            {
                let errorTitle = NSLocalizedString("Unable to Add Source", comment: "")
                await self.presentAlert(title: errorTitle, message: error.localizedDescription)
            }
        }
    }
    
    func dismiss()
    {
        guard 
            let navigationController = self.navigationController, let presentingViewController = navigationController.presentingViewController
        else { return }
        
        presentingViewController.dismiss(animated: true)
    }
}

private extension AddSourceViewController
{
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        sourceDetailViewController?.addedSourceHandler = { [weak self] _ in
            self?.dismiss()
        }
        return sourceDetailViewController
    }
}

extension AddSourceViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) 
    {
        guard Section(rawValue: indexPath.section) != .add else { return }
        
        let source = self.dataSource.item(at: indexPath)
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
}

extension AddSourceViewController: UICollectionViewDelegateFlowLayout
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)!
        switch (section, kind)
        {
        case (.add, UICollectionView.elementKindSectionHeader):
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var configuation = UIListContentConfiguration.cell()
            configuation.text = NSLocalizedString("Enter a source's URL below, or add one of the recommended sources.", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
            return headerView
            
        case (.preview, UICollectionView.elementKindSectionFooter):
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ReuseID.placeholderFooter.rawValue, for: indexPath) as! PlaceholderCollectionReusableView
            
            self.configure(footerView, with: self.viewModel.sourcePreviewResult)
            
            return footerView
                        
        case (.recommended, UICollectionView.elementKindSectionHeader):
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var configuation = UIListContentConfiguration.groupedHeader()
            configuation.text = NSLocalizedString("Recommended Sources", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
            return headerView
            
        case (.recommended, UICollectionView.elementKindSectionFooter):
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ReuseID.placeholderFooter.rawValue, for: indexPath) as! PlaceholderCollectionReusableView
            
            footerView.placeholderView.stackView.spacing = 15
            footerView.placeholderView.stackView.directionalLayoutMargins.top = 20
            footerView.placeholderView.stackView.isLayoutMarginsRelativeArrangement = true
            
            if let result = self.fetchRecommendedSourcesResult, case .failure(let error) = result
            {
                footerView.placeholderView.textLabel.isHidden = false
                footerView.placeholderView.textLabel.font = UIFont.preferredFont(forTextStyle: .headline)
                footerView.placeholderView.textLabel.text = NSLocalizedString("Unable to Load Recommended Sources", comment: "")
                
                footerView.placeholderView.detailTextLabel.isHidden = false
                footerView.placeholderView.detailTextLabel.text = error.localizedDescription
                
                footerView.placeholderView.activityIndicatorView.stopAnimating()
            }
            else
            {
                footerView.placeholderView.textLabel.isHidden = true
                footerView.placeholderView.detailTextLabel.isHidden = true
                
                footerView.placeholderView.activityIndicatorView.startAnimating()
            }
            
            return footerView
            
        default: fatalError()
        }
    }
}

extension AddSourceViewController: UITextFieldDelegate
{
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool 
    {
        self.viewModel.isShowingPreviewStatus = false
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) 
    {
        self.viewModel.isShowingPreviewStatus = true
    }
}

@available(iOS 17.0, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let storyboard = UIStoryboard(name: "Sources", bundle: .main)
    
    let addSourceNavigationController = storyboard.instantiateViewController(withIdentifier: "addSourceNavigationController")
    return addSourceNavigationController
}
