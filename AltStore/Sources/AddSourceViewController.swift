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
            self.textField.returnKeyType = .done
            self.textField.autocapitalizationType = .none
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
    
    @AsyncManaged
    private var previewSource: Source? {
        didSet {
            guard self.previewSource?.identifier != oldValue?.identifier else { return }
            
            let items = [self.previewSource].compactMap { $0 }
            
            let indexPath = IndexPath(row: 0, section: Section.preview.rawValue)
            
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
            self.previewSourceDataSource.setItems(items, with: nil)
        }
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Add Source", comment: "")
        self.navigationController?.navigationBar.prefersLargeTitles = true
        
        self.collectionView.collectionViewLayout = self.makeLayout()
        
        self.collectionView.register(SourceTextFieldCell.self, forCellWithReuseIdentifier: "TextFieldCell")
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.keyboardDismissMode = .onDrag
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")
        
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
        
//        UIPasteboard.general.string = "apps.altstore.io"
    }
    
    private func startPipeline()
    {
        self.$sourceURLString
            .removeDuplicates()
            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .compactMap { (urlString: String) -> URL? in
                guard let sourceURL = URL(string: urlString) else { return nil }
                
                guard sourceURL.scheme != nil else {
                    let sanitizedURL = URL(string: "https://" + urlString)
                    return sanitizedURL
                }
                
                return sourceURL
            }
            .flatMap { (sourceURL: URL) in
                let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
                
                return Future<Source?, Error> { promise in
                    AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                        print("Running pipeline 4!", result)
                        promise(result.map { $0 as Source? })
                    }
                }
                .catch { error in
                    print("Failed to fetch source for URL:", sourceURL)
                    return Just(Source?.none)
                }
                .map { AsyncManaged(wrappedValue: $0) }
            }
            .receive(on: RunLoop.main)
            .map { [weak self] source in
                print("Running pipeline 5???", source)
                self?.previewSource = source.wrappedValue
                
                return source
            }
            .assign(to: \._previewSource, on: self)
            .store(in: &self.cancellables)
    }
}

private extension AddSourceViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .safeArea
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
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
                configuration.headerMode = (section == .recommended) ? .supplementary : .none
                configuration.showsSeparators = false
                configuration.backgroundColor = .altBackground
                
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
        
        cell.bannerView.iconImageView.image = nil
        cell.bannerView.iconImageView.isIndicatingActivity = true
        
        let config = UIImage.SymbolConfiguration(scale: .small)
        let image = UIImage(systemName: "plus", withConfiguration: config)?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        cell.bannerView.button.setImage(image, for: .normal)
        cell.bannerView.button.setTitle(nil, for: .normal)
        
        cell.bannerView.stackView.directionalLayoutMargins.trailing = 20
        
        if cell.bannerView.buttonWidthLayoutConstraint.isActive
        {
            cell.bannerView.buttonWidthLayoutConstraint.isActive = false
            cell.bannerView.buttonHeightLayoutConstraint.constant = 24
            
            let widthConstraint = cell.bannerView.button.widthAnchor.constraint(equalTo: cell.bannerView.button.heightAnchor)
            widthConstraint.isActive = true
        }
        
        cell.bannerView.button.contentEdgeInsets = .zero
        cell.bannerView.button.tintColor = .white
        cell.bannerView.buttonLabel.isHidden = true
                                            
        cell.bannerView.titleLabel.text = source.name
        
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
    }
}

extension AddSourceViewController
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
}

extension AddSourceViewController: UICollectionViewDelegateFlowLayout
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let reuseIdentifier = (kind == UICollectionView.elementKindSectionHeader) ? "Header" : "Footer"
        
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseIdentifier, for: indexPath) as! UICollectionViewListCell
        
        switch Section(rawValue: indexPath.section)!
        {
        case .add:
            var configuation = UIListContentConfiguration.cell()
            configuation.text = NSLocalizedString("Enter a source's URL below, or add one of the recommended sources.", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
        case .preview: break
            
        case .recommended:
            var configuation = UIListContentConfiguration.groupedHeader()
            configuation.text = NSLocalizedString("Recommended Sources", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
        }
        
        return headerView
    }
}

extension AddSourceViewController: UITextFieldDelegate
{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool 
    {
        textField.resignFirstResponder()
        return false
    }
}

@available(iOS 17.0, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startSynchronously()
    
    let addSourceViewController = AddSourceViewController(collectionViewLayout: UICollectionViewFlowLayout())
    
    let navigationController = ForwardingNavigationController(rootViewController: addSourceViewController)
    return navigationController
}
