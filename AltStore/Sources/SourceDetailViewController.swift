//
//  SourceDetailViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/15/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

import AltStoreCore
import Roxas

import Nuke

extension Source
{
    var tintColor: UIColor? {
        return self.apps.first?.tintColor
    }
    
    var iconURL: URL? {
        return self.apps.first?.iconURL
    }
    
    var websiteURL: URL? {
        return URL(string: "https://altstore.io")
    }
    
    var localizedDescription: String? {
        return """
Lorem ipsum dolizzle sit amizzle, gangster adipiscing elit. Nullam sapizzle velizzle, things volutpizzle, suscipit brizzle, hizzle vel, that's the shizzle. Pellentesque eget tortizzle. Sizzle erizzle. Check it out at dolor dapibus daahng dawg tempizzle shizzlin dizzle. Fo shizzle pellentesque nibh et break it down. Vestibulum izzle shiz. Pellentesque mofo rhoncus dang. In dang sizzle platea dope. Shizzle my nizzle crocodizzle dapibizzle. We gonna chung sure urna, pretizzle the bizzle, mattis dizzle, dang hizzle, nunc. Rizzle suscipizzle. Its fo rizzle semper pimpin' sizzle the bizzle.

Etizzle fo shizzle urna for sure nisl. Mammasay mammasa mamma oo sa quis izzle. Maecenas pulvinar, ipsizzle malesuada malesuada scelerisque, check out this purus euismizzle funky fresh, fo shizzle mah nizzle fo rizzle, mah home g-dizzle luctus metus stuff izzle izzle. Vivamizzle ullamcorper, tortizzle et varizzle shiz, crunk fo shizzle mah nizzle fo rizzle, mah home g-dizzle owned pizzle, izzle sheezy leo elizzle in pizzle. Boofron we gonna chung, orci break yo neck, yall volutpizzle black, sizzle phat luctizzle mah nizzle, for sure bibendizzle enizzle own yo' ut sure. Nullam a izzle izzle shiz hizzle viverra. Phasellus get down get down boofron. Curabitizzle nizzle shit i saw beyonces tizzles and my pizzle went crizzle pede sodalizzle facilisizzle. Hizzle sapizzle boofron, daahng dawg vel, molestie rizzle, yo a, erizzle. Shut the shizzle up vitae owned quis bibendizzle boofron. Nizzle fo shizzle my nizzle consectetuer . Aliquizzle dawg volutpat. Fo shizzle ut leo izzle dang pretizzle faucibus. Cras stuff lacus dui izzle ultricies. Fo shizzle my nizzle nisl. Fo shizzle et own yo'. Integer things rizzle mammasay mammasa mamma oo sa mi. Fo shizzle my nizzle izzle boofron.
"""
    }
}

class DummyTableViewController: UITableViewController, CarolineContentViewController
{
    lazy var dataSource = self.makeDataSource()
    
    var scrollView: UIScrollView { self.tableView }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        self.tableView.rowHeight = 100
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: RSTCellContentGenericCellIdentifier)
    }
    
    func makeDataSource() -> RSTArrayTableViewDataSource<NSString>
    {
        let dataSource = RSTArrayTableViewDataSource(items: ["Riley", "Shane", "Caroline", "Ryan", "Josh", "Evan", "Nicole"] as [NSString])
        dataSource.cellConfigurationHandler = { (cell, name, indexPath) in
            cell.textLabel?.text = name as String
        }
        
        return dataSource
    }
}

class AlmostPillButton: UIButton
{
    var useExtraPadding = true
    
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        guard useExtraPadding else {
            size.height = 31
            size.width = 31
            return size
        }
        
        size.width += 26
//        size.height += 3
        size.height = 31
        
        size.width = max(size.width, 71)
        
        return size
    }
}

class SourceDetailViewController: CarolineParentContentViewController
{
    let source: Source
    
    private var previousBounds: CGRect?
    
    private var addButton: AlmostPillButton!
    private var addButtonContainerView: UIView!
    
    private var isSourceAdded = false {
        didSet {
            self.update()
        }
    }
    
    init(source: Source)
    {
        self.source = source
        
        super.init()
    }
    
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.tintColor = self.source.tintColor
        
        self.navigationController?.navigationBar.tintColor = self.source.tintColor
        
        let useInfoIcon = false
        
        self.addButton = AlmostPillButton(type: .system)
        self.addButton.translatesAutoresizingMaskIntoConstraints = false
        self.addButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        self.addButton.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
        self.addButton.addTarget(self, action: #selector(SourceDetailViewController.addSource), for: .primaryActionTriggered)
        
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .secondaryLabel)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        vibrancyView.contentView.addSubview(self.addButton, pinningEdgesWith: .zero)
        blurView.contentView.addSubview(vibrancyView, pinningEdgesWith: .zero)
        self.addButtonContainerView = blurView

        self.contentView.addSubview(self.addButtonContainerView)
        
        if useInfoIcon
        {
            self.navigationBarButton.setTitle(nil, for: .normal)
            self.navigationBarButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
            self.navigationBarButton.addTarget(self, action: #selector(SourceDetailViewController.showAboutViewController), for: .primaryActionTriggered)
            
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.navigationBarButton)
        }
        else
        {
            self.navigationBarButton.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.navigationBarButton)
            
//            let barButtonItem = UIBarButtonItem(title: NSLocalizedString("About", comment: ""), style: .done, target: self, action: #selector(SourceDetailViewController.showAboutViewController))
//            self.navigationItem.rightBarButtonItem = barButtonItem
        }
        
        self.navigationBarButton.addTarget(self, action: #selector(SourceDetailViewController.addSource), for: .primaryActionTriggered)
        
//        self.primaryOcculusionView = self.labelsStackView
        
//        let completedProgress = Progress(totalUnitCount: 1)
//        completedProgress.completedUnitCount = 1
//
//        self.addButton = PillButton(frame: .zero)
//        self.addButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
//        self.addButton.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
//
//        var size = self.addButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
//        size.width = 72
//        self.addButton.frame.size = size
//
//        self.contentView.addSubview(self.addButton)
        
//        self.addButton.tintColor = self.source.tintColor
//        self.addButton.progressTintColor = .white
//        self.addButton.progress = completedProgress
//        self.addButton.isIndicatingActivity = false
//        self.addButton.isUserInteractionEnabled = true
        
//        self.addButton.progressTintColor = .red
        
        
        
//        let progress = Progress.discreteProgress(totalUnitCount: 10)
//        progress.completedUnitCount = 5
//
//        self.addButton.progress = progress
//        self.addButton.isIndicatingActivity = false
//        self.addButton.isUserInteractionEnabled = true
        
        
        
        
        Nuke.loadImage(with: self.source.iconURL, into: self.backgroundImageView)
        Nuke.loadImage(with: self.source.iconURL, into: self.navigationBarAppIconImageView)
        Nuke.loadImage(with: self.source.iconURL, into: self.headerImageView)
        
        self.navigationBarAppNameLabel.text = self.source.name
        self.navigationBarAppNameLabel.sizeToFit()
        
        let fittingSize = self.navigationBarTitleView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.navigationBarTitleView.frame.size = fittingSize
        
        self.navigationItem.titleView = nil
        self.navigationItem.titleView = self.navigationBarTitleView

        let addButtonSize = self.addButton.intrinsicContentSize
        self.addButtonContainerView.frame.size = addButtonSize
        
        self.addButtonContainerView.clipsToBounds = true
        self.addButtonContainerView.layer.cornerRadius = self.addButtonContainerView.bounds.midY
        
        NSLayoutConstraint.activate([
            self.navigationBarButton.widthAnchor.constraint(greaterThanOrEqualToConstant: addButtonSize.width),
            self.navigationBarButton.heightAnchor.constraint(greaterThanOrEqualToConstant: addButtonSize.height),
        ])
        
        self.update()
    }
    
    override func update()
    {
        super.update()
        
//        for button in [self.navigationBarButton!]
//        {
//            button.tintColor = self.source.tintColor
//        }
        
        self.navigationBarButton.tintColor = self.isSourceAdded ? .refreshRed : self.source.tintColor ?? .altPrimary
        
        let title = self.isSourceAdded ? NSLocalizedString("REMOVE", comment: "") : NSLocalizedString("ADD", comment: "")
        guard self.addButton?.title(for: .normal) != title else { return }
        
        self.navigationBarButton.setTitle(title, for: .normal)
        self.addButton?.setTitle(title, for: .normal)
        
        self.navigationItem.rightBarButtonItem = nil
        
        let titleView = self.navigationItem.titleView
        self.navigationItem.titleView = nil
        
        self.navigationBarButton.frame.size.width = 100
        self.navigationBarButton.setContentCompressionResistancePriority(UILayoutPriority(rawValue: 9000), for: .horizontal)
        
        let barButtonItem = UIBarButtonItem(customView: self.navigationBarButton)
        self.navigationItem.rightBarButtonItem = barButtonItem
        
        self.navigationController?.navigationBar.setNeedsLayout()
        self.navigationController?.navigationBar.layoutIfNeeded()
        
        self.navigationItem.titleView = titleView
    }
    
    override func makeContentViewController() -> CarolineContentViewController
    {
        let contentViewController = SourceDetailContentViewController(source: self.source)
        return contentViewController
    }
    
    override func makeHeaderContentView() -> UIView?
    {
        let sourceAboutView = SourceAboutView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
        sourceAboutView.linkButton.addTarget(self, action: #selector(SourceDetailViewController.showWebsite), for: .primaryActionTriggered)
        return sourceAboutView
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let inset = 15.0
        
        self.addButtonContainerView.frame.size = self.addButton.intrinsicContentSize
        
        self.addButtonContainerView.center.y = self.backButtonContainerView.center.y
        self.addButtonContainerView.frame.origin.x = self.view.bounds.width - inset - self.addButtonContainerView.bounds.width
        
        guard self.view.bounds != self.previousBounds else { return }
        self.previousBounds = self.view.bounds
                
        let headerSize = self.headerContentView.systemLayoutSizeFitting(CGSize(width: self.view.bounds.width - inset * 2, height: UIView.layoutFittingCompressedSize.height))
        self.headerContentView.frame.size.height = headerSize.height
    }
}

private extension SourceDetailViewController
{
    @IBAction func showAboutViewController()
    {
        let storyboard = UIStoryboard(name: "Main", bundle: .main)
        
        let aboutViewController = storyboard.instantiateViewController(identifier: "aboutSourceViewController") { coder in
            SourceAboutViewController(source: self.source, coder: coder)
        }
        
        let navigationController = UINavigationController(rootViewController: aboutViewController)
        self.present(navigationController, animated: true)
    }
    
    @IBAction func unwindToSourceDetail(_ segue: UIStoryboardSegue)
    {
    }
    
    
    @IBAction func addSource()
    {
        self.isSourceAdded.toggle()
    }
    
    @IBAction func showWebsite()
    {
        guard let websiteURL = self.source.websiteURL else { return }
        
        let safariViewController = SFSafariViewController(url: websiteURL)
        safariViewController.preferredControlTintColor = self.source.tintColor
        self.present(safariViewController, animated: true, completion: nil)
    }
}
