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

import QuickLook

final class ErrorLogViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    private var expandedErrorIDs = Set<NSManagedObjectID>()
    
    private lazy var timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        self.tableView.prefetchDataSource = self.dataSource
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
            
            switch loggedError.domain
            {
            case AltServerErrorDomain: cell.errorCodeLabel?.text = String(format: NSLocalizedString("AltServer Error %@", comment: ""), NSNumber(value: loggedError.code))
            case OperationError.domain: cell.errorCodeLabel?.text = String(format: NSLocalizedString("AltStore Error %@", comment: ""), NSNumber(value: loggedError.code))
            default: cell.errorCodeLabel?.text = loggedError.error.localizedErrorCode
            }
            
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
                        
            if #available(iOS 14, *)
            {
                let menu = UIMenu(title: "", children: [
                    UIAction(title: NSLocalizedString("Copy Error Message", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                        self?.copyErrorMessage(for: loggedError)
                    },
                    UIAction(title: NSLocalizedString("Copy Error Code", comment: ""), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                        self?.copyErrorCode(for: loggedError)
                    },
                    UIAction(title: NSLocalizedString("Search FAQ", comment: ""), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                        self?.searchFAQ(for: loggedError)
                    }
                ])

                cell.menuButton.menu = menu
            }
            
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
                        ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { (response, error) in
                            guard !operation.isCancelled else { return operation.finish() }
                            
                            if let image = response?.image
                            {
                                completion(image, nil)
                            }
                            else
                            {
                                completion(nil, error)
                            }
                        }
                    }
                    else
                    {
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
    
    @IBAction func showMinimuxerLogs(_ sender: UIBarButtonItem)
    {
        // Show minimuxer.log
        let previewController = QLPreviewController()
        previewController.dataSource = self
        let navigationController = UINavigationController(rootViewController: previewController)
        present(navigationController, animated: true, completion: nil)
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
        let baseURL = URL(string: "https://faq.altstore.io/getting-started/troubleshooting-guide")!
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        let query = [loggedError.domain, "\(loggedError.code)"].joined(separator: "+")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        
        let safariViewController = SFSafariViewController(url: components.url ?? baseURL)
        safariViewController.preferredControlTintColor = .altPrimary
        self.present(safariViewController, animated: true)
    }
}

extension ErrorLogViewController
{
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let loggedError = self.dataSource.item(at: indexPath)
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
            tableView.deselectRow(at: indexPath, animated: true)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Copy Error Message", comment: ""), style: .default) { [weak self] _ in
            self?.copyErrorMessage(for: loggedError)
            tableView.deselectRow(at: indexPath, animated: true)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Copy Error Code", comment: ""), style: .default) { [weak self] _ in
            self?.copyErrorCode(for: loggedError)
            tableView.deselectRow(at: indexPath, animated: true)
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Search FAQ", comment: ""), style: .default) { [weak self] _ in
            self?.searchFAQ(for: loggedError)
            tableView.deselectRow(at: indexPath, animated: true)
        })
        self.present(alertController, animated: true)
    }
    
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

extension ErrorLogViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let fileURL = FileManager.default.documentsDirectory.appendingPathComponent("minimuxer.log")
        return fileURL as QLPreviewItem
    }
}
