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

class LoadingCollectionReusableView: UICollectionReusableView
{
    let activityIndicatorView: UIActivityIndicatorView
    
    override init(frame: CGRect)
    {
        self.activityIndicatorView = UIActivityIndicatorView(style: .medium)
        self.activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        self.activityIndicatorView.startAnimating()
        
        super.init(frame: frame)
                
        self.addSubview(self.activityIndicatorView)
        
        NSLayoutConstraint.activate([
            self.activityIndicatorView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.activityIndicatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.activityIndicatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PlaceholderCollectionReusableView: UICollectionReusableView
{
    let placeholderView: RSTPlaceholderView
    
    override init(frame: CGRect)
    {
        self.placeholderView = RSTPlaceholderView(frame: .zero)
        
        super.init(frame: frame)
                
        self.addSubview(self.placeholderView, pinningEdgesWith: .zero)
        
        NSLayoutConstraint.activate([
            self.placeholderView.leadingAnchor.constraint(equalTo: self.placeholderView.stackView.leadingAnchor),
            self.placeholderView.trailingAnchor.constraint(equalTo: self.placeholderView.stackView.trailingAnchor),
            self.placeholderView.topAnchor.constraint(equalTo: self.placeholderView.stackView.topAnchor),
            self.placeholderView.bottomAnchor.constraint(equalTo: self.placeholderView.stackView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension AddSourceViewController
{
    private enum Section: Int
    {
        case add
        case preview
        case recommended
    }
    
    private class SourceTextFieldCell: UICollectionViewCell
    {
        let textField: UITextField
        
        private let backgroundEffectView: UIVisualEffectView
        private let imageView: UIImageView
        
        override init(frame: CGRect)
        {
            self.textField = UITextField(frame: frame)
            self.textField.translatesAutoresizingMaskIntoConstraints = false
            self.textField.placeholder = "apps.altstore.io"
            self.textField.tintColor = .altPrimary
            self.textField.textColor = .altPrimary
            self.textField.textContentType = .URL
            self.textField.keyboardType = .URL
            self.textField.returnKeyType = .done
            self.textField.autocapitalizationType = .none
            self.textField.autocorrectionType = .no
            self.textField.spellCheckingType = .no
            self.textField.enablesReturnKeyAutomatically = true
            
            let blurEffect = UIBlurEffect(style: .systemChromeMaterial)
            self.backgroundEffectView = UIVisualEffectView(effect: blurEffect)
            self.backgroundEffectView.clipsToBounds = true
            self.backgroundEffectView.backgroundColor = .altPrimary
            self.backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
            
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            let image = UIImage(systemName: "link", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
            self.imageView = UIImageView(image: image)
            self.imageView.contentMode = .center
            self.imageView.tintColor = .altPrimary
//            self.imageView.contentMode = .scaleAspectFit
            self.imageView.translatesAutoresizingMaskIntoConstraints = false
            
            super.init(frame: frame)
            
            self.contentView.preservesSuperviewLayoutMargins = true
            
            self.backgroundEffectView.contentView.addSubview(self.imageView)
            self.backgroundEffectView.contentView.addSubview(self.textField)
            
            self.contentView.addSubview(self.backgroundEffectView)
//            self.contentView.addSubview(backgroundEffectView, pinningEdgesWith: .zero)
            
            
            NSLayoutConstraint.activate([
                self.backgroundEffectView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
                self.backgroundEffectView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
                self.backgroundEffectView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
                self.backgroundEffectView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
                
                self.imageView.widthAnchor.constraint(equalToConstant: 44),
                self.imageView.heightAnchor.constraint(equalToConstant: 44),
                self.imageView.centerYAnchor.constraint(equalTo: self.backgroundEffectView.centerYAnchor),
                
                self.textField.topAnchor.constraint(equalTo: self.backgroundEffectView.topAnchor, constant: 15),
                self.textField.bottomAnchor.constraint(equalTo: self.backgroundEffectView.bottomAnchor, constant: -15),
                self.textField.trailingAnchor.constraint(equalTo: self.backgroundEffectView.trailingAnchor, constant: -15),
                
                self.imageView.leadingAnchor.constraint(equalTo: self.backgroundEffectView.leadingAnchor, constant: 15),
                self.textField.leadingAnchor.constraint(equalToSystemSpacingAfter: self.imageView.trailingAnchor, multiplier: 1.0),
            ])
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() 
        {
            super.layoutSubviews()
            
            self.backgroundEffectView.layer.cornerRadius = self.backgroundEffectView.bounds.midY
        }
    }
}

class AddSourceViewController: UICollectionViewController 
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var addSourceDataSource = self.makeAddSourceDataSource()
    private lazy var previewSourceDataSource = self.makePreviewSourceDataSource()
    private lazy var recommendedSourcesDataSource = self.makeRecommendedSourcesDataSource()
    
    private var addingSource: Source?
    
    private var fetchTrustedSourcesOperation: UpdateKnownSourcesOperation?
    private var fetchTrustedSourcesResult: Result<Void, Error>?
    private var _fetchTrustedSourcesContext: NSManagedObjectContext?
    
    private var cancellables: Set<AnyCancellable> = []
    
    @Published
    private var sourceURLString: String = ""
    
    @Published
    private var sourceURL: URL?
    
    @Published
    private var isLoadingPreview: Bool = false
//    {
//        didSet {
//            if oldValue != self.isLoadingPreview, !self.isLoadingPreview
//            {
//                self.collectionView.reloadSections([Section.preview.rawValue])
//            }
//        }
//    }
    
//    @Published
//    private var sourcePreviewResult: Result<AsyncManaged<Source>, Error>?
    
    @AsyncManaged
    private var previewSource: Source? {
        didSet {
            defer {
                DispatchQueue.main.async {
                    if self.previewSource == nil
                    {
                        self.collectionView.reloadSections([Section.preview.rawValue])
                    }
                    else
                    {
                        self.collectionView.collectionViewLayout.invalidateLayout()
                    }
                }
            }
            
            guard self.previewSource?.identifier != oldValue?.identifier else { return }
            
            let items = [self.previewSource].compactMap { $0 }
            
            // Have to provide changes in terms of previewDataSource
            let indexPath = IndexPath(row: 0, section: 0)
            
            let change: RSTCellContentChange
            
            if self.previewSourceDataSource.items.isEmpty
            {
                change = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: indexPath)
            }
            else if items.isEmpty
            {
                change = RSTCellContentChange(type: .delete, currentIndexPath: indexPath, destinationIndexPath: nil)
            }
            else
            {
                change = RSTCellContentChange(type: .update, currentIndexPath: indexPath, destinationIndexPath: indexPath)
            }
            
            print("Updating with change:", change)
            self.previewSourceDataSource.setItems(items, with: [change])
        }
    }
    
    @Published
    private var previewSourceURL: URL?
    
    @Published
    private var showPreviewErrorInline: Bool = false 
//    {
//        didSet {
//            if oldValue != false && self.showPreviewErrorInline != false
//            {
////                self.collectionView.reloadSections([Section.preview.rawValue])
//                self.collectionView.collectionViewLayout.invalidateLayout()
//            }
//            else
//            {
//                self.collectionView.performBatchUpdates {
//                    //self.collectionView.reloadSections([Section.preview.rawValue])
//                    self.collectionView.collectionViewLayout.invalidateLayout()
//                }
//            }
//        }
//    }
    
    private var previewError: Error?
//    {
//        didSet {
//            if oldValue != nil && self.previewError != nil
//            {
//                print("[RSTLog] Requesting re-layout for error (non-animated)")
//                
////                self.collectionView.reloadSections([Section.preview.rawValue])
//                self.collectionView.collectionViewLayout.invalidateLayout()
//            }
//            else
//            {
//                print("[RSTLog] Requesting re-layout for error (animated)")
//                
//                self.collectionView.performBatchUpdates {
////                    self.collectionView.reloadSections([Section.preview.rawValue])
//                    self.collectionView.collectionViewLayout.invalidateLayout()
//                }
//            }
//        }
//    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Add Source", comment: "")
        
//        self.collectionView.backgroundColor = .secondarySystemBackground
        self.collectionView.backgroundColor = .altBackground
        
        self.navigationController?.isModalInPresentation = true
        self.navigationController?.view.tintColor = .altPrimary
        
        self.collectionView.collectionViewLayout = self.makeLayout()
        
//        let backgroundView = UIView(frame: .zero)
//        backgroundView.backgroundColor = .yellow
//        self.collectionView.backgroundView = backgroundView
        
        self.collectionView.register(SourceTextFieldCell.self, forCellWithReuseIdentifier: "TextFieldCell")
        
        // Registered in Storyboard with Segue
        // self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.keyboardDismissMode = .onDrag
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: UICollectionView.elementKindSectionFooter)
        self.collectionView.register(PlaceholderCollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "PlaceholderFooter")
        self.collectionView.register(LoadingCollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "LoadingFooter")
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.startPipeline()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if self.fetchTrustedSourcesOperation == nil
        {
            self.fetchTrustedSources()
        }
    }
    
    func fetchPreviewSource(sourceURL: URL) -> some Publisher<Managed<Source>, Error>
    {
        var fetchOperation: FetchSourceOperation?
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
        
        return Future<Source, Error> { promise in
            fetchOperation = AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                promise(result)
            }
        }
        .map { Managed(wrappedValue: $0) }
        .handleEvents(receiveCancel: {
            print("[RSTLog] Cancelling fetch source:", sourceURL)
            fetchOperation?.cancel()
        })
    }
    
    private func startPipeline()
    {
        // Map UITextField -> URL
        self.$sourceURLString
            .map { (urlString: String) -> URL? in
                guard let sourceURL = URL(string: urlString) else { return nil }
                
                guard sourceURL.scheme != nil else {
                    let sanitizedURL = URL(string: "https://" + urlString)
                    return sanitizedURL
                }
                
                return sourceURL
            }
            .assign(to: &$sourceURL)
        
        // Preview Source/Error inline
        let showErrorPublisher = self.$showPreviewErrorInline
            .filter { $0 == true }
        
        let sourceURLPublisher = self.$sourceURL
            .removeDuplicates()
            .debounce(for: 0.2, scheduler: RunLoop.main)
        
        // Map URL -> Source
        Publishers.CombineLatest(sourceURLPublisher, showErrorPublisher.prepend(false))
            .compactMap { (sourceURL: URL?, _) -> AnyPublisher<Managed<Source>?, Never> in
                guard let sourceURL else {
                    return Just(nil).eraseToAnyPublisher()
                }
                
                print("[RSTLog] Loading source URL \(sourceURL) 1")
                
                self.isLoadingPreview = true
                self.previewSource = nil
                
                return self.fetchPreviewSource(sourceURL: sourceURL)
                    .map { source in
                        self.previewError = nil
                        return Optional(source)
                    }
                    .catch { error in
                        print("[RSTLog] Failed to fetch source for URL \(sourceURL):", error.localizedDescription)
                        self.previewError = error
                        
                        return Just<Managed<Source>?>(nil)
                    }
                    .map { source in
                        self.previewSourceURL = sourceURL
                        return source
                    }
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .map { (source) in
                print("[RSTLog] Loading source URL \(source?.perform { _ in source?.sourceURL }) 2")
                
                self.isLoadingPreview = false
                return source?.wrappedValue
            }
            .assign(to: \AddSourceViewController.previewSource, on: self)
            .store(in: &self.cancellables)
        
//            .sink { [weak self] completion in
//                        switch completion
//                        {
//                        case .finished: break
//                        case .failure(let error): self?.previewError = error
//                        }
//
//                        self?.isLoadingPreview = false
//
//                    }, receiveValue: { [weak self] source in
//                        self?.previewSource = source
//                        self?.isLoadingPreview = false
//                    }
        
        
//            .map { [weak self] (sourceURL: URL?) in
//                Future<Source?, Error> { promise in
//                    guard let sourceURL else { return promise(.success(nil)) }
//                    
//                    let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
//                    AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
//                        promise(result.map { $0 as Source? })
//                    }
//                }
//                .map { [weak self] source in
//                    self?.previewError = nil
//                    return source
//                }
//                .receive(on: RunLoop.main)
////                .catch { error in
////                    print("[RSTLog] Failed to fetch source for URL:", sourceURL ?? "nil", error)
////                    
////                    self?.previewError = error
////                    return Empty()
////                }
//                .map { source in
//                    self?.previewSourceURL = sourceURL
//                    return source
//                }
//            }
//            .sink { [weak self] completion in
//                switch completion
//                {
//                case .finished: break
//                case .failure(let error): self?.previewError = error
//                }
//            }, receiveValue: { [weak self] source in
//                self?.previewSource = source
//            }
//            .switchToLatest()
//            .map { [weak self] source in
//                self?.isLoadingPreview = false
//                return source
//            }
//            .assign(to: \AddSourceViewController.previewSource, on: self)
//            .store(in: &self.cancellables)
        
        // Preview Source/Error inline
//        let showErrorPublisher = self.$showPreviewErrorInline
//            .filter { $0 == true }
//        
//        Publishers.CombineLatest($previewSource, showErrorPublisher)
//            .removeDuplicates()
//            .receive(on: RunLoop.main)
//            .sink { [weak self] source in
//                self?.previewSource = source.wrappedValue
//                
//                if source.wrappedValue != nil
//                {
//                    self?.previewError = nil
//                }
//            }
//            .store(in: &self.cancellables)
        
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
            .sink { indexPath in
                // Added or removed a recommended source, so make sure to update its state.
                self.collectionView.reloadItems(at: [indexPath])
            }
            .store(in: &self.cancellables)
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
                
            case .preview, .recommended:
                var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                
                if case .recommended = section 
                {
                    switch self.fetchTrustedSourcesResult
                    {
                    case .none:
                        configuration.headerMode = .supplementary
                        configuration.footerMode = .supplementary
                        
                    case .failure: configuration.footerMode = .supplementary
                    case .success: configuration.headerMode = .supplementary
                    }
                }
                else if case .preview = section 
                {
                    if self.showPreviewErrorInline && (self.previewError != nil || self.isLoadingPreview)
                    {
                        configuration.footerMode = .supplementary
                    }
                    else
                    {
                        configuration.footerMode = .none
                    }
                }
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
            }
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>(dataSources: [self.addSourceDataSource, self.previewSourceDataSource, self.recommendedSourcesDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makeAddSourceDataSource() -> RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 1 }
        dataSource.cellIdentifierHandler = { _ in "TextFieldCell" }
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! SourceTextFieldCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.textField.delegate = self
            
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            
            NotificationCenter.default
                .publisher(for: UITextField.textDidChangeNotification, object: cell.textField)
                .map { ($0.object as? UITextField)?.text ?? "" }
                .assign(to: \.sourceURLString, on: self)
                .store(in: &self.cancellables)
        }
        
        return dataSource
    }
    
    func makePreviewSourceDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AppBannerCollectionViewCell
            self.configure(cell, source: source)
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
            self.configure(cell, source: source)
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
    
    func configure(_ cell: AppBannerCollectionViewCell, source: Source)
    {
        let tintColor = source.effectiveTintColor ?? .altPrimary
        
        cell.bannerView.style = .source
        cell.layoutMargins.top = 5
        cell.layoutMargins.bottom = 5
        cell.layoutMargins.left = self.view.layoutMargins.left
        cell.layoutMargins.right = self.view.layoutMargins.right
        cell.tintColor = tintColor
        cell.contentView.backgroundColor = .altBackground
        //cell.contentView.backgroundColor = .secondarySystemBackground
        
        cell.bannerView.iconImageView.image = nil
        cell.bannerView.iconImageView.isIndicatingActivity = true
        
        let config = UIImage.SymbolConfiguration(scale: .small)
        let image = UIImage(systemName: "plus.circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        cell.bannerView.button.setImage(image, for: .normal)
        cell.bannerView.button.setImage(image, for: .highlighted)
        cell.bannerView.button.imageView?.contentMode = .scaleAspectFit
        cell.bannerView.button.contentHorizontalAlignment = .fill // Fill entire button with imageView
        cell.bannerView.button.contentVerticalAlignment = .fill
        cell.bannerView.button.setTitle(nil, for: .normal)
        
        cell.bannerView.button.isHidden = false
        cell.bannerView.button.style = .custom
        cell.bannerView.button.contentEdgeInsets = .zero
        cell.bannerView.button.tintColor = .clear
        cell.bannerView.stackView.directionalLayoutMargins.trailing = 20
        
        let action = UIAction(identifier: .addSource) { [weak self] _ in
            self?.add(source)
        }
        cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
        
        cell.bannerView.titleLabel.text = source.name
        cell.bannerView.buttonLabel.isHidden = true
        
        if let subtitle = source.subtitle
        {
            cell.bannerView.subtitleLabel.text = subtitle
        }
        else
        {
            var sanitizedURL = source.sourceURL.absoluteString
            
            if let scheme = source.sourceURL.scheme
            {
                sanitizedURL = sanitizedURL.replacingOccurrences(of: scheme + "://", with: "")
            }
            
            cell.bannerView.subtitleLabel.text = sanitizedURL
        }
        
        cell.bannerView.subtitleLabel.numberOfLines = 2
        
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
    
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        return sourceDetailViewController
    }
}

private extension AddSourceViewController
{
    func fetchTrustedSources()
    {
        // Closure instead of local function so we can capture `self` weakly.
        let finish: (Result<[Source], Error>) -> Void = { [weak self] result in
            self?.fetchTrustedSourcesResult = result.map { _ in () }
            
            DispatchQueue.main.async {
                do
                {
                    let sources = try result.get()
                    print("Fetched trusted sources:", sources.map { $0.identifier })

                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems(sources, with: [sectionUpdate])
                }
                catch
                {
                    print("Error fetching trusted sources:", error)
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems([], with: [sectionUpdate])
                }
            }
        }
        
        self.fetchTrustedSourcesOperation = AppManager.shared.updateKnownSources { [weak self] result in
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success((let trustedSources, _)):
                                
                // Don't show sources without a sourceURL.
                let featuredSourceURLs = trustedSources.compactMap { $0.sourceURL }
                
                // This context is never saved, but keeps the managed sources alive.
                let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
                self?._fetchTrustedSourcesContext = context
                
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
    
    func add(_ source: Source)
    {
        let isTrusted = source.isTrusted
        
        Task<Void, Never>.detached {
            do
            {
                if isTrusted
                {
                    try await AppManager.shared.add(source, message: nil, presentingViewController: self)
                }
                else
                {
                    // Use default message
                    try await AppManager.shared.add(source, presentingViewController: self)
                }
                
                await MainActor.run { [self] in
                    if let navigationController = self.navigationController, let presentingViewController = navigationController.presentingViewController
                    {
                        //TODO: Should this be automatic? Or more explicit with callbacks?
                        presentingViewController.dismiss(animated: true)
                    }
                }
                
            }
            catch is CancellationError {}
            catch
            {
                let errorTitle = NSLocalizedString("Unable to Add Source", comment: "")
                await self.presentAlert(title: errorTitle, message: error.localizedDescription)
            }
        }
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
            if let previewError, self.sourceURL == self.previewSourceURL
            {
                let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
                
                var configuation = UIListContentConfiguration.cell()
                configuation.text = (previewError as NSError).localizedDebugDescription ?? previewError.localizedDescription
                                
                configuation.textProperties.color = .secondaryLabel
                configuation.textProperties.font = .preferredFont(forTextStyle: .subheadline)
                configuation.textProperties.alignment = .center
                
                headerView.contentConfiguration = configuation
                
                return headerView
            }
            else
            {
                // The current URL does not match the URL of the source/error being displayed, so show loading indicator.
                let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "LoadingFooter", for: indexPath) as! LoadingCollectionReusableView
                return headerView
            }
                        
        case (.recommended, UICollectionView.elementKindSectionHeader):
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var configuation = UIListContentConfiguration.groupedHeader()
            configuation.text = NSLocalizedString("Recommended Sources", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
            return headerView
            
        case (.recommended, UICollectionView.elementKindSectionFooter):
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "PlaceholderFooter", for: indexPath) as! PlaceholderCollectionReusableView
            
            footerView.placeholderView.stackView.spacing = 15
            footerView.placeholderView.stackView.directionalLayoutMargins.top = 20
            footerView.placeholderView.stackView.isLayoutMarginsRelativeArrangement = true
            
            if let result = self.fetchTrustedSourcesResult, case .failure(let error) = result
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
        self.showPreviewErrorInline = false
        
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) 
    {
        self.showPreviewErrorInline = true
    }
}

@available(iOS 17.0, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startSynchronously()
    
    let storyboard = UIStoryboard(name: "Sources", bundle: .main)
    
    let addSourceNavigationController = storyboard.instantiateViewController(withIdentifier: "addSourceNavigationController")
    return addSourceNavigationController
}
