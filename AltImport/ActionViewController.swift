//
//  ActionViewController.swift
//  AltImport
//
//  Created by Riley Testut on 6/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import MobileCoreServices
import Roxas
import AltSign

class ActionViewController: UIViewController
{
    private var ipaURL: URL?
    
    @IBOutlet var progressView: UIProgressView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if UserDefaults.standard.firstLaunch == nil
        {
            Keychain.shared.reset()
            UserDefaults.standard.firstLaunch = Date()
        }
        
        ServerManager.shared.startDiscovering()
    
        // Get the item[s] we're handling from the extension context.
        
        // For example, look for an image and place it into an image view.
        // Replace this with something appropriate for the type[s] your extension supports.
        var imageFound = false
        for item in self.extensionContext!.inputItems as! [NSExtensionItem] {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                    // This is an image. We'll load it, then place it in our image view.
                    
                    provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (imageURL, error) in
                        if let imageURL = imageURL as? URL {
                            print(imageURL)
                            self.ipaURL = imageURL
                        }
                    })
                    
                    imageFound = true
                    break
                }
            }
            
            if (imageFound) {
                // We only handle one image, so stop looking for more.
                break
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.install()
        }
    }
    
    @IBAction func install()
    {
        guard let ipaURL = self.ipaURL else {
            let alertController = UIAlertController(title: "No URL Found", message: nil, preferredStyle: .alert)
            alertController.addAction(.cancel)
            self.present(alertController, animated: true, completion: nil)
            
            return
        }
        
        func finish(_ result: Result<InstalledApp, Error>)
        {
            switch result
            {
            case .failure(let error):
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "Failed to install app.", message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default) { (action) in
                        self.extensionContext!.completeRequest(returningItems: self.extensionContext!.inputItems, completionHandler: nil)
                    })
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .success(let app):                
                self.extensionContext!.completeRequest(returningItems: self.extensionContext!.inputItems, completionHandler: nil)
            }
        }
        
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                finish(.failure(error))
            }
            else
            {
                print("Started DatabaseManager")
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    do
                    {
                        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
                        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                        
                        let appBundleURL = try FileManager.default.unzipAppBundle(at: ipaURL, toDirectory: temporaryDirectory)
                        
                        guard let application = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                        
                        let app = App(context: context)
                        app.name = application.name
                        app.identifier = application.bundleIdentifier
                        app.developerName = ""
                        app.localizedDescription = ""
                        app.iconName = ""
                        app.screenshotNames = []
                        app.version = "1.0"
                        app.versionDate = Date()
                        app.downloadURL = ipaURL
                        
                        try! context.save()
                        
                        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                            
                            let app = App.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(App.identifier), application.bundleIdentifier), in: context)
                            
                            let progress = AppManager.shared.install(app!, presentingViewController: self) { (result) in
                                try? context.save()
                                finish(result)
                            }
                            
                            self.progressView.observedProgress = progress
                        }
                    }
                    catch
                    {
                        finish(.failure(error))
                    }
                }
            }
        }
    }
}
