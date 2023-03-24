//
//  SourceDetailViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/15/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices
import Combine

import AltStoreCore
import Roxas

import Nuke

extension SourceDetailViewController
{
    private class ViewModel: ObservableObject
    {
        let source: Source
        
        @Published
        var isSourceAdded: Bool?
        
        @Published
        var isAddingSource: Bool = false
        
        init(source: Source)
        {
            self.source = source
            
            Task<Void, Never> {
                do
                {
                    self.isSourceAdded = try await self.source.isAdded
                }
                catch
                {
                    print("[ALTLog] Failed to check source is added.", error)
                }
            }
        }
    }
}

class SourceDetailViewController: HeaderContentViewController<SourceHeaderView, SourceDetailContentViewController>
{
    let source: Source
    
    private let viewModel: ViewModel
    
    private var addButton: VibrantButton!
    
    private var previousBounds: CGRect?
    private var cancellables = Set<AnyCancellable>()
    
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        self.viewModel = ViewModel(source: source)
        
        super.init(coder: coder)
        
        self.title = source.name
    }
    
    class func makeSourceDetailViewController(source: Source) -> SourceDetailViewController
    {
        let storyboard = UIStoryboard(name: "Sources", bundle: .main)
        
        let sourceDetailViewController = storyboard.instantiateViewController(identifier: "sourceDetailViewController") { coder in
            SourceDetailViewController(source: source, coder: coder)
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
        
        self.addButton = VibrantButton(type: .system)
        self.addButton.contentInsets = PillButton.contentInsets
        self.addButton.addTarget(self, action: #selector(SourceDetailViewController.addSource), for: .primaryActionTriggered)
        self.addButton.sizeToFit()
        self.view.addSubview(self.addButton)
        
        // Assign after creating addButton to avoid implicitly unwrapping optional.
        self.tintColor = self.source.effectiveTintColor
        
        self.navigationBarButton.addTarget(self, action: #selector(SourceDetailViewController.addSource), for: .primaryActionTriggered)
        
        Nuke.loadImage(with: self.source.effectiveIconURL, into: self.navigationBarIconView)
        Nuke.loadImage(with: self.source.effectiveHeaderImageURL, into: self.backgroundImageView)
        
        self.update()
        self.startObservations()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.addButton.layer.cornerRadius = self.addButton.bounds.midY
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
        
        let inset = 15.0
                
        var addButtonSize = self.addButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        addButtonSize.width = max(addButtonSize.width, PillButton.minimumSize.width)
        addButtonSize.height = PillButton.minimumSize.height // Enforce height so it doesn't change with UIActivityIndicatorView
        self.addButton.frame.size = addButtonSize

        self.addButton.center.y = self.backButton.center.y
        self.addButton.frame.origin.x = self.view.bounds.width - inset - self.addButton.bounds.width
        
        guard self.view.bounds != self.previousBounds else { return }
        self.previousBounds = self.view.bounds
                
        let headerSize = self.headerView.systemLayoutSizeFitting(CGSize(width: self.view.bounds.width - inset * 2, height: UIView.layoutFittingCompressedSize.height))
        self.headerView.frame.size.height = headerSize.height
    }
    
    override func makeContentViewController() -> SourceDetailContentViewController
    {
        let contentViewController = SourceDetailContentViewController(source: self.source)
        return contentViewController
    }
    
    override func makeHeaderView() -> SourceHeaderView
    {
        let sourceAboutView = SourceHeaderView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
        sourceAboutView.websiteButton.addTarget(self, action: #selector(SourceDetailViewController.showWebsite), for: .primaryActionTriggered)
        return sourceAboutView
    }
    
    //MARK: Actions
    
    @objc private func addSource()
    {
        self.viewModel.isAddingSource = true
        
        Task<Void, Never> {
            var isSourceAdded: Bool?
            
            do
            {
                let isAdded = try await self.source.isAdded
                if isAdded
                {
                    try await AppManager.shared.remove(self.source, presentingViewController: self)
                }
                else
                {
                    try await AppManager.shared.add(self.source, presentingViewController: self)
                }
               
                isSourceAdded = try await self.source.isAdded
            }
            catch is CancellationError {}
            catch
            {
                await self.presentAlert(title: NSLocalizedString("Unable to Add Source", comment: ""), message: error.localizedDescription)
            }
            
            self.viewModel.isAddingSource = false // Must set to false before setting isSourceAdded to avoid layout-related crashes.
            
            if let isSourceAdded
            {
                self.viewModel.isSourceAdded = isSourceAdded
            }
        }
    }
    
    @objc private func showWebsite()
    {
        guard let websiteURL = self.source.websiteURL else { return }
        
        let safariViewController = SFSafariViewController(url: websiteURL)
        safariViewController.preferredControlTintColor = self.source.effectiveTintColor ?? .altPrimary
        self.present(safariViewController, animated: true, completion: nil)
    }
    
    //MARK: Override
    
    override func update()
    {
        if self.source.identifier == Source.altStoreIdentifier
        {
            // Users can't remove default AltStore source, so hide buttons.
            self.addButton.isHidden = true
            self.navigationBarButton.isHidden = true
        }
        else
        {
            // Update isIndicatingActivity first to ensure later updates are applied correctly.
            self.addButton.isIndicatingActivity = self.viewModel.isAddingSource
            self.navigationBarButton.isIndicatingActivity = self.viewModel.isAddingSource
            
            let title: String
            
            switch self.viewModel.isSourceAdded
            {
            case true?:
                title = NSLocalizedString("REMOVE", comment: "")
                self.navigationBarButton.tintColor = .refreshRed
                
                self.addButton.isHidden = false
                self.navigationBarButton.isHidden = false
                
            case false?:
                title = NSLocalizedString("ADD", comment: "")
                self.navigationBarButton.tintColor = self.source.effectiveTintColor ?? .altPrimary
                
                self.addButton.isHidden = false
                self.navigationBarButton.isHidden = false
                
            case nil:
                title = ""
                
                self.addButton.isHidden = true
                self.navigationBarButton.isHidden = true
            }
            
            if self.addButton.title != title
            {
                self.addButton.title = title
                self.navigationBarButton.setTitle(title, for: .normal)
            }
            
            self.view.setNeedsLayout()
        }
        
        super.update()
    }
}

private extension SourceDetailViewController
{
    func startObservations()
    {
        self.viewModel.$isSourceAdded
            .receive(on: RunLoop.main)
            .sink { isSourceAdded in
                self.update()
            }.store(in: &self.cancellables)
        
        self.viewModel.$isAddingSource
            .receive(on: RunLoop.main)
            .sink { isAddingSource in
                self.update()
            }.store(in: &self.cancellables)
    }
}
