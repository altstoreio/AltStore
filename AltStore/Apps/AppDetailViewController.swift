//
//  AppDetailViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

@objc(ScreenshotCollectionViewCell)
private class ScreenshotCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var imageView: UIImageView!
}

extension AppDetailViewController
{
    private enum Row: Int
    {
        case general
        case screenshots
        case description
    }
}

class AppDetailViewController: UITableViewController
{
    var app: App!
    
    private lazy var screenshotsDataSource = self.makeScreenshotsDataSource()
    
    @IBOutlet private var nameLabel: UILabel!
    @IBOutlet private var developerButton: UIButton!
    @IBOutlet private var appIconImageView: UIImageView!
    
    @IBOutlet private var downloadButton: UIButton!
    
    @IBOutlet private var screenshotsCollectionView: UICollectionView!
    
    @IBOutlet private var descriptionLabel: UILabel!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.delegate = self
        self.screenshotsCollectionView.dataSource = self.screenshotsDataSource
        
        self.downloadButton.activityIndicatorView.style = .white
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.update()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        guard let image = self.screenshotsDataSource.items.first else { return }
        
        let aspectRatio = image.size.width / image.size.height
        
        let height = self.screenshotsCollectionView.bounds.height
        let width = self.screenshotsCollectionView.bounds.height * aspectRatio
        
        let layout = self.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = CGSize(width: width, height: height)
    }
}

private extension AppDetailViewController
{
    func update()
    {
        self.nameLabel.text = self.app.name
        self.developerButton.setTitle(self.app.developerName, for: .normal)
        self.appIconImageView.image = UIImage(named: self.app.iconName)
        
        self.descriptionLabel.text = self.app.localizedDescription
        
        if self.app.installedApp == nil
        {
            let text = String(format: NSLocalizedString("Download %@", comment: ""), self.app.name)
            self.downloadButton.setTitle(text, for: .normal)
            self.downloadButton.isEnabled = true
        }
        else
        {
            self.downloadButton.setTitle(NSLocalizedString("Installed", comment: ""), for: .normal)
            self.downloadButton.isEnabled = false
        }
    }
    
    func makeScreenshotsDataSource() -> RSTArrayCollectionViewDataSource<UIImage>
    {
        let screenshots = self.app.screenshotNames.compactMap(UIImage.init(named:))
        
        let dataSource = RSTArrayCollectionViewDataSource(items: screenshots)
        dataSource.cellConfigurationHandler = { (cell, screenshot, indexPath) in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.image = screenshot
        }
        
        return dataSource
    }
}

private extension AppDetailViewController
{
    @IBAction func downloadApp(_ sender: UIButton)
    {
        guard self.app.installedApp == nil else { return }
        
        let appURL = Bundle.main.url(forResource: "App", withExtension: "ipa")!
        
        do
        {
            try FileManager.default.copyItem(at: appURL, to: self.app.ipaURL, shouldReplace: true)
        }
        catch
        {
            print("Failed to copy .ipa", error)
        }
        
        if let server = ServerManager.shared.discoveredServers.first
        {
            sender.isIndicatingActivity = true
            
            server.install(self.app) { (result) in
                DispatchQueue.main.async {
                    switch result
                    {
                    case .success:
                        let toastView = RSTToastView(text: "Installed \(self.app.name)!", detailText: nil)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController!.view, duration: 2)
                        
                        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                            let app = context.object(with: self.app.objectID) as! App
                            
                            _ = InstalledApp(app: app,
                                             bundleIdentifier: app.identifier,
                                             signedDate: Date(),
                                             expirationDate: Date().addingTimeInterval(60 * 60 * 24 * 7),
                                             context: context)
                            
                            do
                            {
                                try context.save()
                            }
                            catch
                            {
                                print("Failed to save context for downloaded app app.", error)
                            }
                            
                            DispatchQueue.main.async {
                                self.update()
                            }
                        }
                        
                    case .failure(let error):
                        let toastView = RSTToastView(text: "Failed to install \(self.app.name)", detailText: error.localizedDescription)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController!.view, duration: 2)
                    }
                    
                    sender.isIndicatingActivity = false
                }
            }
        }
        else
        {
            let toastView = RSTToastView(text: "Could not find AltServer", detailText: nil)
            toastView.tintColor = .altPurple
            toastView.show(in: self.navigationController!.view, duration: 2)
        }
    }
}

extension AppDetailViewController
{
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        guard indexPath.row == Row.screenshots.rawValue else { return super.tableView(tableView, heightForRowAt: indexPath) }
        guard !self.screenshotsDataSource.items.isEmpty else { return 0.0 }
        
        let height = self.view.bounds.height * 0.67
        return height
    }
}
