//
//  RevisedSourceDetailViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/21/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

import AltStoreCore
import Roxas

import Nuke

class RevisedSourceDetailViewController: HeaderContentViewController<SourceAboutView, SourceDetailContentViewController>
{
    let source: Source
    
    private var previousBounds: CGRect?
    
    @IBOutlet private var addButton: VibrantButton!
    
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
        
        self.title = source.name
    }
    
    class func make(source: Source) -> RevisedSourceDetailViewController
    {
        let storyboard = UIStoryboard(name: "Sources", bundle: .main)
        
        let sourceDetailViewController = storyboard.instantiateViewController(identifier: "sourceDetailViewController") { coder in
            RevisedSourceDetailViewController(source: source, coder: coder)
        }
        return sourceDetailViewController
    }
    
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tintColor = self.source.effectiveTintColor
        
        self.addButton = VibrantButton(type: .system)
        self.addButton.title = NSLocalizedString("ADD", comment: "")
        self.addButton.contentInsets = PillButton.contentInsets
        self.addButton.addTarget(self, action: #selector(RevisedSourceDetailViewController.addSource), for: .primaryActionTriggered)
        self.addButton.sizeToFit()
        self.view.insertSubview(self.addButton, belowSubview: self.backButton)
        
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
        
        Nuke.loadImage(with: self.source.effectiveIconURL, into: self.navigationBarIconView)
        Nuke.loadImage(with: self.source.effectiveHeaderImageURL, into: self.backgroundImageView)
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let inset = 15.0
                
        var addButtonSize = self.addButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        addButtonSize.width = max(addButtonSize.width, PillButton.minimumSize.width)
        addButtonSize.height = max(addButtonSize.height, PillButton.minimumSize.height)
        self.addButton.frame.size = addButtonSize

        self.addButton.center.y = self.backButton.center.y
        self.addButton.frame.origin.x = self.view.bounds.width - inset - self.addButton.bounds.width
        
        guard self.view.bounds != self.previousBounds else { return }
        self.previousBounds = self.view.bounds
                
        let headerSize = self.headerView.systemLayoutSizeFitting(CGSize(width: self.view.bounds.width - inset * 2, height: UIView.layoutFittingCompressedSize.height))
        self.headerView.frame.size.height = headerSize.height
        
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
        self.addButton.layer.cornerRadius = self.addButton.bounds.midY
    }
    
    override func makeContentViewController() -> SourceDetailContentViewController
    {
        let contentViewController = SourceDetailContentViewController(source: self.source)
        return contentViewController
    }
    
    override func makeHeaderView() -> SourceAboutView
    {
        let sourceAboutView = SourceAboutView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
//        sourceAboutView.linkButton.addTarget(self, action: #selector(SourceDetailViewController.showWebsite), for: .primaryActionTriggered)
        return sourceAboutView
    }
    
    //MARK: Actions
    
    @objc private func addSource()
    {
        print("[ALTLog] Add Source!")
    }
}

