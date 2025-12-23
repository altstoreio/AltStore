//
//  FediverseInteractionsView.swift
//  AltStore
//
//  Created by Riley Testut on 11/19/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltStoreCore

@Observable
class FediverseInteractionsView: UIView
{
    var shareHandler: ((URL) -> UIViewController?)?
    
    private var contentView: UIView!
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.update(with: nil)
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.update(with: nil)
    }
    
    func configure(with item: some Federatable, isOpaque: Bool = false)
    {
        self.update(with: item, isOpaque: isOpaque)
    }
}

private extension FediverseInteractionsView
{
    func update(with item: (any Federatable)?, isOpaque: Bool = false)
    {
        self.contentView?.removeFromSuperview()
        
        let hostingConfiguration = UIHostingConfiguration {
            if let item
            {
                FediverseInteractions(item: item, isOpaque: isOpaque)
                    .environment(self)
                    .tint(Color(uiColor: self.tintColor))
            }
            else
            {
                EmptyView()
            }
        }.margins(.all, .init(self.directionalLayoutMargins))
        
        self.contentView = hostingConfiguration.makeContentView()
        self.addSubview(self.contentView, pinningEdgesWith: .zero)
    }
}

struct FediverseInteractions: View
{
    @State
    var item: Federatable
    
    @State
    var isOpaque: Bool = false
    
    @State
    private var accounts: [MastodonAPI.Account]?
    
    @Namespace
    private var unionNamespace
    
    @Environment(FediverseInteractionsView.self)
    private var fediverseInteractionsView
    
    private let preferredHeight: CGFloat = 30
    private let maximumAvatars: Int = 5
    
    var body: some View {
        Group {
            HStack {
                // Interactions
                HStack {
                    // Comment + Like buttons
                    socialButtons
                    
                    let avatarSpacing = -(preferredHeight / 2)
                    
                    // Avatars
                    SwiftUI.Button {
                        showLikes(for: item)
                    } label: {
                        HStack(spacing: avatarSpacing) {
                            if let accounts
                            {
                                ForEach(accounts, id: \.id) { account in
                                    AsyncImage(url: account.avatar_static) { image in
                                        image
                                            .resizable()
                                            .clipShape(.circle)
                                            .overlay(Circle().stroke(.tint, lineWidth: 1))
                                            .frame(width: preferredHeight, height: preferredHeight)
                                    } placeholder: {
                                        avatarPlaceholder
                                    }
                                }
                            }
                            else
                            {
                                let avatarsCount = min(Int(item.likesCount), maximumAvatars)
                                ForEach(0..<avatarsCount, id: \.self) { _ in
                                    avatarPlaceholder
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                shareButton
            }
            .frame(height: preferredHeight)
            .frame(minWidth: 100, maxWidth: .infinity)
        }
        .task(priority: .medium) { @MainActor in
            do
            {
                guard let rawStatusID = item.statusID, let statusID = Int(rawStatusID) else { return }
                
                let accounts = try await MastodonAPI.shared.fetchFavorites(tootID: statusID, limit: maximumAvatars)
                self.accounts = accounts
            }
            catch
            {
                Logger.main.error("Failed to fetch Fediverse interactions for \(String(describing: item), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private var socialButtonContent: some View {
        Group {
            // Comment button
            SwiftUI.Button {
                showFederatedStatus(for: item)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "bubble")
                    if item.commentsCount > 0
                    {
                        Text("\(item.commentsCount)")
                    }
                }
            }
            
            // Like button
            SwiftUI.Button {
                showLikes(for: item)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "heart")
                    if item.likesCount > 0
                    {
                        Text("\(item.likesCount)")
                    }
                }
            }
        }
    }
    
    private var socialButtons: some View {
        Group {
            if #available(iOS 26, *)
            {
                GlassEffectContainer(spacing: 0) {
                    if isOpaque
                    {
                        // On opaque background
                        HStack(spacing: -10) {
                            socialButtonContent
                        }
                        
                        .buttonStyle(.glassProminent) // Prominent glass
                        .glassEffectUnion(id: "button", namespace: unionNamespace)
                    }
                    else
                    {
                        // On translucent background
                        HStack(spacing: -10) {
                            socialButtonContent
                        }
                        .buttonStyle(.glass) // Regular glass
                        .glassEffectUnion(id: "button", namespace: unionNamespace)
                    }
                }
                .font(.subheadline)
            }
            else
            {
                HStack(spacing: 12) {
                    if isOpaque
                    {
                        socialButtonContent
                            .foregroundStyle(Color.white)
                    }
                    else
                    {
                        socialButtonContent
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.trailing, 5)
            }
        }
    }
    
    private var shareButton: some View {
        Group {
            if let federatedURL = item.federatedURL
            {
                if #available(iOS 26, *)
                {
                    if isOpaque
                    {
                        // On opaque background
                        SwiftUI.Button {
                            share(federatedURL)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .font(.subheadline)
                        .buttonStyle(.glassProminent) // Prominent glass
                        .buttonBorderShape(.circle)
                    }
                    else
                    {
                        // On translucent background
                        SwiftUI.Button {
                            share(federatedURL)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .font(.subheadline)
                        .buttonStyle(.glass) // Regular glass
                        .buttonBorderShape(.circle)
                    }
                }
                else
                {
                    SwiftUI.Button {
                        share(federatedURL)
                    } label: {
                        if isOpaque
                        {
                            Image(systemName: "square.and.arrow.up")
                                .tint(Color.white)
                        }
                        else
                        {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Group {
            if #available(iOS 26, *)
            {
                if isOpaque
                {
                    Circle().fill(.tint)
                        .glassEffect(.clear)
                }
                else
                {
                    Circle().fill(.clear)
                        .glassEffect(.regular)
                }
            }
            else
            {
                Circle().fill(.tint)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            }
        }
    }
}

private extension FediverseInteractions
{
    func showFederatedStatus(for item: some Federatable)
    {
        guard let federatedURL = item.federatedURL else { return }
        
        UIApplication.shared.open(federatedURL, options: [:])
    }
    
    func showLikes(for item: some Federatable)
    {
        guard var federatedURL = item.federatedURL else { return }
        federatedURL.append(component: "favourites")
        
        UIApplication.shared.open(federatedURL, options: [:])
    }
    
    func show(_ account: MastodonAPI.Account)
    {
        UIApplication.shared.open(account.url, options: [:])
    }
    
    func share(_ url: URL)
    {
        guard let presentingViewController = fediverseInteractionsView.shareHandler?(url) else { return }
        
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        presentingViewController.present(activityViewController, animated: true)
    }
}

struct TestFederatable: Federatable
{
    var statusID: String? = "115431859871064626"
    var federatedURL: URL? = URL(string: "")
    
    var likesCount: Int32
    var boostsCount: Int32
    var commentsCount: Int32
}

#Preview {
    FediverseInteractions(item: Federatable.Mock(statusID: "115431859871064626", federatedURL: URL(string: "https://rileytestut.com"), likesCount: 10, boostsCount: 0, commentsCount: 0), isOpaque: false)
}

