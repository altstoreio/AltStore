//
//  ErrorLogViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

import AltStoreCore
import Roxas

import Nuke

class ErrorLogViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    private var expandedErrorIDs = Set<NSManagedObjectID>()
    
    private var isScrolling = false {
        didSet {
            guard self.isScrolling != oldValue else { return }
            self.updateButtonInteractivity()
        }
    }
    
    private lazy var timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()
    
    @IBOutlet private var exportLogButton: UIBarButtonItem!
    @IBOutlet private var clearLogButton: UIBarButtonItem!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        self.tableView.prefetchDataSource = self.dataSource
        
        self.exportLogButton.activityIndicatorView.color = .white
        
        if #unavailable(iOS 15)
        {
            // Assign just clearLogButton to hide export button.
            self.navigationItem.rightBarButtonItems = [self.clearLogButton]
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard let loggedError = sender as? LoggedError, segue.identifier == "showErrorDetails" else { return }
        
        let navigationController = segue.destination as! UINavigationController
        
        let errorDetailsViewController = navigationController.viewControllers.first as! ErrorDetailsViewController
        errorDetailsViewController.loggedError = loggedError
    }
    
    @IBAction private func unwindFromErrorDetails(_ segue: UIStoryboardSegue)
    {
    }
}

private extension ErrorLogViewController
{
    func makeDataSource() -> RSTFetchedResultsTableViewPrefetchingDataSource<LoggedError, UIImage>
    {
        let fetchRequest = LoggedError.fetchRequest() as NSFetchRequest<LoggedError>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LoggedError.date, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(LoggedError.localizedDateString), cacheName: nil)
        
        let dataSource = RSTFetchedResultsTableViewPrefetchingDataSource<LoggedError, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.rowAnimation = .fade
        dataSource.cellConfigurationHandler = { [weak self] (cell, loggedError, indexPath) in
            guard let self else { return }
            
            let cell = cell as! ErrorLogTableViewCell
            cell.dateLabel.text = self.timeFormatter.string(from: loggedError.date)
            cell.errorFailureLabel.text = loggedError.localizedFailure ?? NSLocalizedString("Operation Failed", comment: "")
            cell.errorCodeLabel.text = loggedError.error.localizedErrorCode
            
            let nsError = loggedError.error as NSError
            let errorDescription = [nsError.localizedDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
            cell.errorDescriptionTextView.text = errorDescription
            cell.errorDescriptionTextView.maximumNumberOfLines = 5
            cell.errorDescriptionTextView.isCollapsed = !self.expandedErrorIDs.contains(loggedError.objectID)
            cell.errorDescriptionTextView.moreButton.addTarget(self, action: #selector(ErrorLogViewController.toggleCollapsingCell(_:)), for: .primaryActionTriggered)
            
            cell.appIconImageView.image = nil
            cell.appIconImageView.isIndicatingActivity = true
            cell.appIconImageView.layer.borderColor = UIColor.gray.cgColor
            
            let displayScale = (self.traitCollection.displayScale == 0.0) ? 1.0 : self.traitCollection.displayScale // 0.0 == "unspecified"
            cell.appIconImageView.layer.borderWidth = 1.0 / displayScale
                        
            let menu = UIMenu(title: "", children: [
                UIAction(title: NSLocalizedString("Copy Error Message", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyErrorMessage(for: loggedError)
                },
                UIAction(title: NSLocalizedString("Copy Error Code", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyErrorCode(for: loggedError)
                },
                UIAction(title: NSLocalizedString("Search FAQ", comment: ""), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                    self?.searchFAQ(for: loggedError)
                },
                UIAction(title: NSLocalizedString("View More Details", comment: ""), image: UIImage(systemName: "ellipsis.circle")) { [weak self] _ in
                    self?.viewMoreDetails(for: loggedError)
                },
            ])

            cell.menuButton.menu = menu

            if self.isScrolling
            {
                cell.menuButton.showsMenuAsPrimaryAction = false
            }
            else
            {
                cell.menuButton.showsMenuAsPrimaryAction = true
            }
            
            cell.selectionStyle = .none
            
            // Include errorDescriptionTextView's text in cell summary.
            cell.accessibilityLabel = [cell.errorFailureLabel.text, cell.dateLabel.text, cell.errorCodeLabel.text, cell.errorDescriptionTextView.text].compactMap { $0 }.joined(separator: ". ")
            
            // Group all paragraphs together into single accessibility element (otherwise, each paragraph is independently selectable).
            cell.errorDescriptionTextView.accessibilityLabel = cell.errorDescriptionTextView.text
        }
        dataSource.prefetchHandler = { (loggedError, indexPath, completion) in
            RSTAsyncBlockOperation { (operation) in
                loggedError.managedObjectContext?.perform {
                    if let installedApp = loggedError.installedApp
                    {
                        installedApp.loadIcon { (result) in
                            switch result
                            {
                            case .failure(let error): completion(nil, error)
                            case .success(let image): completion(image, nil)
                            }
                        }
                    }
                    else if let storeApp = loggedError.storeApp
                    {
                        ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { result in
                            guard !operation.isCancelled else { return operation.finish() }
                            
                            switch result
                            {
                            case .success(let response): completion(response.image, nil)
                            case .failure(let error): completion(nil, error)
                            }
                        }
                    }
                    else
                    {
                        // InstalledApp was probably deleted.
                        completion(nil, nil)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! ErrorLogTableViewCell
            cell.appIconImageView.image = image
            cell.appIconImageView.isIndicatingActivity = false
        }
        
        let placeholderView = RSTPlaceholderView()
        placeholderView.textLabel.text = NSLocalizedString("No Errors", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("Errors that occur when sideloading or refreshing apps will appear here.", comment: "")
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
}

private extension ErrorLogViewController
{
    @IBAction func toggleCollapsingCell(_ sender: UIButton)
    {
        let point = self.tableView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.tableView.indexPathForRow(at: point), let cell = self.tableView.cellForRow(at: indexPath) as? ErrorLogTableViewCell else { return }
        
        let loggedError = self.dataSource.item(at: indexPath)
        
        if cell.errorDescriptionTextView.isCollapsed
        {
            self.expandedErrorIDs.remove(loggedError.objectID)
        }
        else
        {
            self.expandedErrorIDs.insert(loggedError.objectID)
        }
        
        self.tableView.performBatchUpdates {
            cell.layoutIfNeeded()
        }
    }
    
    @IBAction func clearLoggedErrors(_ sender: UIBarButtonItem)
    {
        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to clear the error log?", comment: ""), message: nil, preferredStyle: .actionSheet)
        alertController.popoverPresentationController?.barButtonItem = sender
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Clear Error Log", comment: ""), style: .destructive) { _ in
            self.clearLoggedErrors()
        })
        self.present(alertController, animated: true)
    }
    
    func clearLoggedErrors()
    {
        DatabaseManager.shared.purgeLoggedErrors { result in
            do
            {
                try result.get()
            }
            catch
            {
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: NSLocalizedString("Failed to Clear Error Log", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(.ok)
                    self.present(alertController, animated: true)
                }
            }
        }
    }
    
    func copyErrorMessage(for loggedError: LoggedError)
    {
        let nsError = loggedError.error as NSError
        let errorMessage = [nsError.localizedDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        
        UIPasteboard.general.string = errorMessage
    }
    
    func copyErrorCode(for loggedError: LoggedError)
    {
        let errorCode = loggedError.error.localizedErrorCode
        UIPasteboard.general.string = errorCode
    }
    
    func searchFAQ(for loggedError: LoggedError)
    {
        let baseURL = URL(string: "https://faq.altstore.io/getting-started/error-codes")!
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        let query = [loggedError.domain, "\(loggedError.error.displayCode)"].joined(separator: "+")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        
        let safariViewController = SFSafariViewController(url: components.url ?? baseURL)
        safariViewController.preferredControlTintColor = .altPrimary
        self.present(safariViewController, animated: true)
    }
    
    func viewMoreDetails(for loggedError: LoggedError)
    {
        self.performSegue(withIdentifier: "showErrorDetails", sender: loggedError)
    }
    
    @available(iOS 15, *)
    @IBAction func exportDetailedLog(_ sender: UIBarButtonItem)
    {
        self.exportLogButton.isIndicatingActivity = true
        
        Task<Void, Never>.detached(priority: .userInitiated) {
            do
            {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                
                // All logs since the app launched.
                let position = store.position(timeIntervalSinceLatestBoot: 0)
                
                let entries = try store.getEntries(at: position)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem.contains(Logger.altstoreSubsystem) }
                    .map { "[\($0.date.formatted())] [\($0.category)] [\($0.level.localizedName)] \($0.composedMessage)" }
                
                let outputText = entries.joined(separator: "\n")
                                
                let outputDirectory = FileManager.default.uniqueTemporaryURL()
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                
                let outputURL = outputDirectory.appendingPathComponent("altlog.txt")
                try outputText.write(to: outputURL, atomically: true, encoding: .utf8)
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task<Void, Never> { @MainActor in
                        let activityViewController = UIActivityViewController(activityItems: [outputURL], applicationActivities: nil)
                        activityViewController.completionWithItemsHandler = { (activityType, completed, _, error) in
                            if let error
                            {
                                continuation.resume(throwing: error)
                            }
                            else
                            {
                                continuation.resume()
                            }
                        }
                        self.present(activityViewController, animated: true)
                    }
                }
            }
            catch
            {
                Logger.main.error("Failed to export OSLog entries. \(error.localizedDescription, privacy: .public)")
                
                await MainActor.run {
                    let alertController = UIAlertController(title: NSLocalizedString("Unable to Export Detailed Log", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(.ok)
                    self.present(alertController, animated: true)
                }
            }
            
            await MainActor.run {
                self.exportLogButton.isIndicatingActivity = false
            }
        }
    }
}

extension ErrorLogViewController
{
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
    {
        let deleteAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { _, _, completion in
            let loggedError = self.dataSource.item(at: indexPath)
            DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                do
                {
                    let loggedError = context.object(with: loggedError.objectID) as! LoggedError
                    context.delete(loggedError)
                    
                    try context.save()
                    completion(true)
                }
                catch
                {
                    print("[ALTLog] Failed to delete LoggedError \(loggedError.objectID):", error)
                    completion(false)
                }
            }
        }
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    {
        let indexPath = IndexPath(row: 0, section: section)
        let loggedError = self.dataSource.item(at: indexPath)
        
        if Calendar.current.isDateInToday(loggedError.date)
        {
            return NSLocalizedString("Today", comment: "")
        }
        else
        {
            return loggedError.localizedDateString
        }
    }
}

extension ErrorLogViewController
{
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView)
    {
        self.isScrolling = true
    }
    
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)
    {
        self.isScrolling = false
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)
    {
        guard !decelerate else { return }
        self.isScrolling = false
    }
    
    private func updateButtonInteractivity()
    {
        for case let cell as ErrorLogTableViewCell in self.tableView.visibleCells
        {
            if self.isScrolling
            {
                cell.menuButton.showsMenuAsPrimaryAction = false
            }
            else
            {
                cell.menuButton.showsMenuAsPrimaryAction = true
            }
        }
    }
}
