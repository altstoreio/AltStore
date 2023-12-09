//
//  VerifyAppPledgeOperation.swift
//  AltStore
//
//  Created by Riley Testut on 12/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltStoreCore

class VerifyAppPledgeOperation: ResultOperation<Void>
{
    @AsyncManaged
    private(set) var storeApp: StoreApp
    
    private let presentingViewController: UIViewController?
    private var openPatreonPageContinuation: CheckedContinuation<Void, Never>?
    
    init(storeApp: StoreApp, presentingViewController: UIViewController?)
    {
        self.storeApp = storeApp
        self.presentingViewController = presentingViewController
    }
    
    override func main()
    {
        super.main()
        
        // _Don't_ rethrow earlier errors, or else user will only be taken to Patreon post if connected to same WiFi as AltServer.
        // if let error = self.context.error
        // {
        //     self.finish(.failure(error))
        //     return
        // }
        
        Task<Void, Never>.detached(priority: .medium) {
            do
            {
                guard await self.$storeApp.isPledgeRequired else { return self.finish(.success(())) }
                
                if let presentingViewController = self.presentingViewController
                {
                    // Ask user to connect Patreon account if they are signed-in to Patreon inside WebViewController, but haven't yet signed in through AltStore settings.
                    // This is most likely because the user joined a Patreon campaign directly through WebViewController before connecting Patreon account in settings.
                    try await self.connectPatreonAccountIfNeeded(presentingViewController: presentingViewController)
                }
                
                do
                {
                    try await self.verifyPledge()
                }
                catch let error as OperationError where error.code == .pledgeRequired || error.code == .pledgeInactive
                {
                    guard 
                        let presentingViewController = self.presentingViewController,
                        let source = await self.$storeApp.source,
                        let patreonURL = await self.$storeApp.perform({ _ in source.patreonURL })
                    else { throw error }
                    
                    let checkoutURL: URL
                    
                    let username = patreonURL.lastPathComponent
                    if !username.isEmpty, let url = URL(string: "https://www.patreon.com/join/" + username)
                    {
                        // Prefer /join URL over campaign homepage.
                        checkoutURL = url
                    }
                    else
                    {
                        checkoutURL = patreonURL
                    }
                    
                    // Direct user to Patreon page if they're not already pledged.
                    await self.openPatreonPage(checkoutURL, presentingViewController: presentingViewController)
                                        
                    let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                    if let patreonAccount = await context.performAsync({ DatabaseManager.shared.patreonAccount(in: context) })
                    {
                        // Patreon account is connected, so we'll update it via API to see if pledges changed.
                        // If so, we'll re-fetch the source to update pledge statuses.
                        try await self.updatePledges(for: source, account: patreonAccount)
                    }
                    else
                    {
                        // Patreon account is not connected, so prompt user to connect it.
                        try await self.connectPatreonAccountIfNeeded(presentingViewController: presentingViewController)
                    }
                    
                    do
                    {
                        try await self.verifyPledge()
                    }
                    catch
                    {
                        // Ignore error, but cancel remainder of operation.
                        throw CancellationError()
                    }
                }
                
                self.finish(.success(()))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}

private extension VerifyAppPledgeOperation
{
    func verifyPledge() async throws
    {
        let (appName, isPledged) = await self.$storeApp.perform { ($0.name, $0.isPledged) }
        
        if !PatreonAPI.shared.isAuthenticated || !isPledged
        {
            let isInstalled = await self.$storeApp.installedApp != nil
            if isInstalled
            {
                // Assume if there is an InstalledApp, the user had previously pledged to this app.
                throw OperationError.pledgeInactive(appName: appName)
            }
            else
            {
                throw OperationError.pledgeRequired(appName: appName)
            }
        }
    }
    
    func connectPatreonAccountIfNeeded(presentingViewController: UIViewController) async throws
    {
        guard !PatreonAPI.shared.isAuthenticated, let authCookie = PatreonAPI.shared.authCookies.first(where: { $0.name.lowercased() == "session_id" }) else { return }
        
        Logger.main.debug("Patreon Auth cookie: \(authCookie.name)=\(authCookie.value)")
        
        let message = NSLocalizedString("You're signed into Patreon but haven't connected your account with AltStore.\n\nPlease connect your account to download Patreon-exclusive apps.", comment: "")
        let action = await UIAlertAction(title: NSLocalizedString("Connect Patreon Account", comment: ""), style: .default)
        
        do
        {
            _ = try await presentingViewController.presentConfirmationAlert(title: NSLocalizedString("Patreon Account Detected", comment: ""),
                                                                            message: message, actions: [action])
        }
        catch
        {
            // Ignore and continue
            return
        }
        
        try await withCheckedThrowingContinuation { continuation in
            PatreonAPI.shared.authenticate(presentingViewController: presentingViewController) { result in
                do
                {
                    let account = try result.get()
                    try account.managedObjectContext?.save()
                    
                    continuation.resume()
                }
                catch
                {
                    continuation.resume(throwing: error)
                }
            }
        }
                
        if let source = await self.$storeApp.source
        {
            // Fetch source to update pledge status now that account is connected.
            try await self.update(source)
        }
    }
    
    func updatePledges(@AsyncManaged for source: Source, @AsyncManaged account: PatreonAccount) async throws
    {
        guard PatreonAPI.shared.isAuthenticated else { return }
        
        let previousPledgeIDs = Set(await $account.perform { $0.pledges.map(\.identifier) })
        
        let updatedPledgeIDs = try await withCheckedThrowingContinuation { continuation in
            PatreonAPI.shared.fetchAccount { (result: Result<PatreonAccount, Swift.Error>) in
                do
                {
                    let account = try result.get()
                    let pledgeIDs = Set(account.pledges.map(\.identifier))
                    
                    try account.managedObjectContext?.save()
                    
                    continuation.resume(returning: pledgeIDs)
                }
                catch
                {
                    Logger.main.error("Failed to update Patreon account. \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
                
        if updatedPledgeIDs != previousPledgeIDs
        {
            // Active pledges changed, so fetch source to update pledge status.
            try await self.update(source)
        }
    }
    
    func update(@AsyncManaged _ source: Source) async throws
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        _ = try await AppManager.shared.fetchSource(sourceURL: $source.sourceURL, managedObjectContext: context)
        
        try await context.performAsync {
            try context.save()
        }
    }
    
    @MainActor
    func openPatreonPage(_ patreonURL: URL, presentingViewController: UIViewController) async
    {
        let webViewController = WebViewController(url: patreonURL)
        webViewController.delegate = self

        let navigationController = UINavigationController(rootViewController: webViewController)
        presentingViewController.present(navigationController, animated: true)

        await withCheckedContinuation { continuation in
            self.openPatreonPageContinuation = continuation
        }
        
        // Cache auth cookies just in case user signed in.
        await PatreonAPI.shared.saveAuthCookies()

        navigationController.dismiss(animated: true)
    }
}

extension VerifyAppPledgeOperation: WebViewControllerDelegate
{
    func webViewControllerDidFinish(_ webViewController: WebViewController)
    {
        guard let continuation = self.openPatreonPageContinuation else { return }
        self.openPatreonPageContinuation = nil

        continuation.resume()
    }
}
