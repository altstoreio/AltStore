//
//  AppCardCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 10/13/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

private let minimumItemSpacing = 8.0

class AppCardCollectionViewCell: UICollectionViewCell
{
    let bannerView: AppBannerView
    let captionLabel: UILabel
    
    var prefersPagingScreenshots = true
    
    private let screenshotsCollectionView: UICollectionView
    private let stackView: UIStackView
    
    private let topAreaPanGestureRecognizer: UIPanGestureRecognizer
    
    private lazy var dataSource = self.makeDataSource()
    
    private var screenshots: [AppScreenshot] = [] {
        didSet {
            self.dataSource.items = self.screenshots
            
            if self.screenshots.isEmpty
            {
                // No screenshots, so hide collection view.
                self.collectionViewAspectRatioConstraint.isActive = false
                self.stackView.layoutMargins.bottom = 0
            }
            else
            {
                // At least one screenshot, so show collection view.
                self.collectionViewAspectRatioConstraint.isActive = true
                self.stackView.layoutMargins.bottom = self.screenshotsCollectionView.directionalLayoutMargins.leading
            }
        }
    }
    
    private let collectionViewAspectRatioConstraint: NSLayoutConstraint
    
    override init(frame: CGRect)
    {
        self.bannerView = AppBannerView(frame: .zero)
        self.bannerView.layoutMargins.bottom = 0
        
        let vibrancyEffect = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemChromeMaterial), style: .secondaryLabel)
        let captionVibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        
        self.captionLabel = UILabel(frame: .zero)
        self.captionLabel.font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote).bolded(), size: 0)
        self.captionLabel.textAlignment = .center
        self.captionLabel.numberOfLines = 2
        self.captionLabel.minimumScaleFactor = 0.8
        captionVibrancyView.contentView.addSubview(self.captionLabel, pinningEdgesWith: .zero)
        
        self.screenshotsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        self.screenshotsCollectionView.backgroundColor = nil
        self.screenshotsCollectionView.alwaysBounceVertical = false
        self.screenshotsCollectionView.alwaysBounceHorizontal = true
        self.screenshotsCollectionView.showsHorizontalScrollIndicator = false
        self.screenshotsCollectionView.showsVerticalScrollIndicator = false
        
        self.stackView = UIStackView(arrangedSubviews: [self.bannerView, captionVibrancyView, self.screenshotsCollectionView])
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.spacing = 12
        self.stackView.axis = .vertical
        self.stackView.alignment = .fill
        self.stackView.distribution = .equalSpacing
        
        // Aspect ratio constraint to fit exactly 3 modern portrait iPhone screenshots side-by-side (with spacing).
        let inset = self.bannerView.layoutMargins.left
        let multiplier = (AppScreenshot.defaultAspectRatio.width * 3) / AppScreenshot.defaultAspectRatio.height
        let spacing = (inset * 2) + (minimumItemSpacing * 2)
        self.collectionViewAspectRatioConstraint = self.screenshotsCollectionView.widthAnchor.constraint(equalTo: self.screenshotsCollectionView.heightAnchor, multiplier: multiplier, constant: spacing)
        
        // Allows us to ignore swipes in top portion of screenshotsCollectionView.
        self.topAreaPanGestureRecognizer = UIPanGestureRecognizer(target: nil, action: nil)
        self.topAreaPanGestureRecognizer.cancelsTouchesInView = false
        self.topAreaPanGestureRecognizer.delaysTouchesBegan = false
        self.topAreaPanGestureRecognizer.delaysTouchesEnded = false
        
        super.init(frame: frame)
        
        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerCurve = .continuous
        
        self.contentView.addSubview(self.bannerView.backgroundEffectView, pinningEdgesWith: .zero)
        self.contentView.addSubview(self.stackView, pinningEdgesWith: .zero)
        
        self.screenshotsCollectionView.collectionViewLayout = self.makeLayout()
        self.screenshotsCollectionView.dataSource = self.dataSource
        self.screenshotsCollectionView.prefetchDataSource = self.dataSource
        
        // Adding screenshotsCollectionView's gesture recognizers to self.contentView breaks paging,
        // so instead we intercept taps and pass them onto delegate.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(AppCardCollectionViewCell.handleTapGesture(_:)))
        tapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.delaysTouchesBegan = false
        tapGestureRecognizer.delaysTouchesEnded = false
        self.screenshotsCollectionView.addGestureRecognizer(tapGestureRecognizer)
        
        self.topAreaPanGestureRecognizer.delegate = self
        self.screenshotsCollectionView.panGestureRecognizer.require(toFail: self.topAreaPanGestureRecognizer)
        self.screenshotsCollectionView.addGestureRecognizer(self.topAreaPanGestureRecognizer)
        
        self.screenshotsCollectionView.register(AppScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.stackView.isLayoutMarginsRelativeArrangement = true
        self.stackView.layoutMargins.bottom = inset
        
        self.contentView.preservesSuperviewLayoutMargins = true
        self.screenshotsCollectionView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
        
        NSLayoutConstraint.activate([
            self.bannerView.heightAnchor.constraint(equalToConstant: AppBannerView.standardHeight - inset)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.contentView.layer.cornerRadius = self.bannerView.layer.cornerRadius
    }
}

private extension AppCardCollectionViewCell
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self else { return nil }
            
            var contentWidth = 0.0
            var numberOfVisibleScreenshots = 0
            
            for screenshot in self.screenshots
            {
                var aspectRatio = screenshot.aspectRatio
                if aspectRatio.width > aspectRatio.height
                {
                    switch screenshot.deviceType
                    {
                    case .iphone:
                        // Always rotate landscape iPhone screenshots
                        aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                        
                    case .ipad:
                        // Never rotate iPad screenshots
                        break
                        
                    default: break
                    }
                }
                
                let screenshotWidth = (layoutEnvironment.container.effectiveContentSize.height * (aspectRatio.width / aspectRatio.height)).rounded(.up) // Round to ensure we over-estimate contentWidth.
                
                let totalContentWidth = contentWidth + (screenshotWidth + minimumItemSpacing)
                if totalContentWidth > layoutEnvironment.container.effectiveContentSize.width
                {
                    // totalContentWidth is larger than visible width.
                    break
                }
                
                contentWidth = totalContentWidth
                numberOfVisibleScreenshots += 1
            }
            
            // Use .estimated(1) to ensure we don't over-estimate widths, which can cause incorrect layouts for the last group.
            let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(1), heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            if numberOfVisibleScreenshots == 1
            {
                // If there's only one screenshot visible initially, we'll (reluctantly) opt-in to flexible spacing on both sides.
                // This ensures the items are always centered, but may result in larger spacings between items than we'd prefer.
                item.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .flexible(0), top: nil, trailing: .flexible(0), bottom: nil)
            }
            else
            {
                // Otherwise, only have flexible spacing on the leading edge, which will be balanced by trailingGroup's flexible trailing spacing.
                item.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .flexible(0), top: nil, trailing: nil, bottom: nil)
            }
            
            let groupItem = NSCollectionLayoutItem(layoutSize: itemSize)
            let trailingGroup = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [groupItem])
            trailingGroup.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: nil, top: nil, trailing: .flexible(0), bottom: nil)
            
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, trailingGroup])
            group.interItemSpacing = .fixed(minimumItemSpacing)
            
            if numberOfVisibleScreenshots < self.screenshots.count
            {
                // There are more screenshots than what is displayed, so no need to manually center them.
            }
            else
            {
                // We're showing all screenshots initially, so make sure they're centered.
                
                let insetWidth = (layoutEnvironment.container.effectiveContentSize.width - contentWidth) / 2.0
                group.contentInsets.leading = (insetWidth - 1).rounded(.down) // Subtract 1 to avoid overflowing/clipping
            }
            
            let layoutSection = NSCollectionLayoutSection(group: group)
            layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
            layoutSection.interGroupSpacing = self.screenshotsCollectionView.directionalLayoutMargins.leading + self.screenshotsCollectionView.directionalLayoutMargins.trailing
            return layoutSection
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { (cell, screenshot, indexPath) in
            let cell = cell as! AppScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
            
            var aspectRatio = screenshot.aspectRatio
            if aspectRatio.width > aspectRatio.height
            {
                switch screenshot.deviceType
                {
                case .iphone:
                    // Always rotate landscape iPhone screenshots
                    aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                    
                case .ipad:
                    // Never rotate iPad screenshots
                    break
                    
                default: break
                }
            }
            
            cell.aspectRatio = aspectRatio
        }
        dataSource.prefetchHandler = { (screenshot, indexPath, completionHandler) in
            let imageURL = screenshot.imageURL
            return RSTAsyncBlockOperation() { (operation) in
                let request = ImageRequest(url: imageURL)
                ImagePipeline.shared.loadImage(with: request, progress: nil) { result in
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
            let cell = cell as! AppScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.setImage(image)
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
    
    @objc func handleTapGesture(_ tapGesture: UITapGestureRecognizer)
    {
        var superview: UIView? = self.superview
        var collectionView: UICollectionView? = nil
        
        while case let view? = superview
        {
            if let cv = view as? UICollectionView
            {
                collectionView = cv
                break
            }
            
            superview = view.superview
        }
        
        if let collectionView, let indexPath = collectionView.indexPath(for: self)
        {
            collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
        }
    }
}

extension AppCardCollectionViewCell
{
    func configure(for storeApp: StoreApp, showSourceIcon: Bool = true)
    {
        self.screenshots = storeApp.preferredScreenshots()
        
        // Explicitly set to false to ensure we're starting from a non-activity indicating state.
        // Otherwise, cell reuse can mess up some cached values.
        self.bannerView.button.isIndicatingActivity = false
        
        self.bannerView.tintColor = storeApp.tintColor
        self.bannerView.configure(for: storeApp, showSourceIcon: showSourceIcon)
        
        self.bannerView.subtitleLabel.numberOfLines = 1
        self.bannerView.subtitleLabel.lineBreakMode = .byTruncatingTail
        self.bannerView.subtitleLabel.minimumScaleFactor = 0.8
        self.bannerView.subtitleLabel.text = storeApp.developerName
        
        if let subtitle = storeApp.subtitle, !subtitle.isEmpty
        {
            self.captionLabel.text = subtitle
            self.captionLabel.isHidden = false
        }
        else
        {
            self.captionLabel.isHidden = true
        }
    }
}

extension AppCardCollectionViewCell: UIGestureRecognizerDelegate
{
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    {
        // Never recognize topAreaPanGestureRecognizer unless prefersPagingScreenshots is false.
        guard !self.prefersPagingScreenshots else { return false }
        
        let point = gestureRecognizer.location(in: self.screenshotsCollectionView)
        
        // Top area = Top 3/4
        let isTopArea = point.y < (self.screenshotsCollectionView.bounds.height / 4) * 3
        return isTopArea
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool 
    {
        guard let panGestureRecognizer = otherGestureRecognizer as? UIPanGestureRecognizer, let view = panGestureRecognizer.view else { return false }
        
        if view.isDescendant(of: self.screenshotsCollectionView)
        {
            // Only allow nested gesture recognizers if topAreaPanGestureRecognizer fails.
            return true
        }
        else 
        {
            // Always allow parent gesture recognizers.
            return false
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool 
    {
        guard let panGestureRecognizer = otherGestureRecognizer as? UIPanGestureRecognizer, let view = panGestureRecognizer.view else { return true }
        
        if view.isDescendant(of: self.screenshotsCollectionView)
        {
            // Don't recognize topAreaPanGestureRecognizer alongside nested gesture recognizers.
            return false
        }
        else 
        {
            // Allow recognizing simultaneously with parent gesture recognizers.
            // This fixes accidentally breaking scrolling in parent.
            return true
        }
    }
}
