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

class SourceDetailViewController: HeaderContentViewController<SourceHeaderView, SourceDetailContentViewController>
{
    @Managed private(set) var source: Source
    
    private var addButton: VibrantButton!
    
    private var previousBounds: CGRect?
    
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        super.init(coder: coder)
        
        self.title = source.name
        self.tintColor = source.effectiveTintColor
    }
    
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.addButton = VibrantButton(type: .system)
        self.addButton.title = NSLocalizedString("ADD", comment: "")
        self.addButton.contentInsets = PillButton.contentInsets
        self.addButton.sizeToFit()
        self.view.addSubview(self.addButton)
        
        Nuke.loadImage(with: self.source.effectiveIconURL, into: self.navigationBarIconView)
        Nuke.loadImage(with: self.source.effectiveHeaderImageURL, into: self.backgroundImageView)
        
        self.update()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.addButton.layer.cornerRadius = self.addButton.bounds.midY
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
        
        var addButtonSize = self.addButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        addButtonSize.width = max(addButtonSize.width, PillButton.minimumSize.width)
        addButtonSize.height = max(addButtonSize.height, PillButton.minimumSize.height)
        self.addButton.frame.size = addButtonSize
        
        // Place in top-right corner.
        let inset = 15.0
        self.addButton.center.y = self.backButton.center.y
        self.addButton.frame.origin.x = self.view.bounds.width - inset - self.addButton.bounds.width
        
        guard self.view.bounds != self.previousBounds else { return }
        self.previousBounds = self.view.bounds
        
        let headerSize = self.headerView.systemLayoutSizeFitting(CGSize(width: self.view.bounds.width - inset * 2, height: UIView.layoutFittingCompressedSize.height))
        self.headerView.frame.size.height = headerSize.height
    }
    
    //MARK: Override
    
    override func makeContentViewController() -> SourceDetailContentViewController
    {
        guard let storyboard = self.storyboard else { fatalError("SourceDetailViewController must be initialized via UIStoryboard.") }
        
        let contentViewController = storyboard.instantiateViewController(identifier: "sourceDetailContentViewController") { coder in
            SourceDetailContentViewController(source: self.source, coder: coder)
        }
        return contentViewController
    }
    
    override func makeHeaderView() -> SourceHeaderView
    {
        let sourceAboutView = SourceHeaderView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
        sourceAboutView.websiteButton.addTarget(self, action: #selector(SourceDetailViewController.showWebsite), for: .primaryActionTriggered)
        return sourceAboutView
    }
    
    override func update()
    {
        super.update()
        
        if self.source.identifier == Source.altStoreIdentifier
        {
            // Users can't remove default AltStore source, so hide buttons.
            self.addButton.isHidden = true
            self.navigationBarButton.isHidden = true
        }
    }
    
    //MARK: Actions
    
    @objc private func showWebsite()
    {
        guard let websiteURL = self.source.websiteURL else { return }
        
        let safariViewController = SFSafariViewController(url: websiteURL)
        safariViewController.preferredControlTintColor = self.source.effectiveTintColor ?? .altPrimary
        self.present(safariViewController, animated: true, completion: nil)
    }
}
