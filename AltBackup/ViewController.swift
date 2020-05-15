//
//  ViewController.swift
//  AltBackup
//
//  Created by Riley Testut on 5/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{
    private let backupController = BackupController()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?)
    {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.backup), name: AppDelegate.startBackupNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.restore), name: AppDelegate.startRestoreNotification, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = .altstoreBackground
        
        let textLabel = UILabel(frame: .zero)
        textLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        textLabel.textColor = .altstoreText
        textLabel.text = NSLocalizedString("Backing up app data…", comment: "")
        
        let activityIndicatorView = UIActivityIndicatorView(style: .whiteLarge)
        activityIndicatorView.color = .altstoreText
        activityIndicatorView.startAnimating()
        
        #if DEBUG
        let button1 = UIButton(type: .system)
        button1.setTitle("Backup", for: .normal)
        button1.setTitleColor(.white, for: .normal)
        button1.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button1.addTarget(self, action: #selector(ViewController.backup), for: .primaryActionTriggered)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Restore", for: .normal)
        button2.setTitleColor(.white, for: .normal)
        button2.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button2.addTarget(self, action: #selector(ViewController.restore), for: .primaryActionTriggered)
        
        let arrangedSubviews = [textLabel, activityIndicatorView, button1, button2]
        #else
        let arrangedSubviews = [textLabel, activityIndicatorView]
        #endif
        
        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 22
        stackView.axis = .vertical
        stackView.alignment = .center
        self.view.addSubview(stackView)
        
        NSLayoutConstraint.activate([stackView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                                     stackView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)])
    }
}

private extension ViewController
{
    @objc func backup()
    {
        self.backupController.performBackup { (result) in
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ??
                NSLocalizedString("App", comment: "")

            let title = String(format: NSLocalizedString("%@ could not be backed up.", comment: ""), appName)
            self.process(result, errorTitle: title)
        }
    }
    
    @objc func restore()
    {
        self.backupController.restoreBackup { (result) in
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ??
                NSLocalizedString("App", comment: "")

            let title = String(format: NSLocalizedString("%@ could not be restored.", comment: ""), appName)
            self.process(result, errorTitle: title)
        }
    }
}

private extension ViewController
{
    func process(_ result: Result<Void, Error>, errorTitle: String)
    {
        DispatchQueue.main.async {
            switch result
            {
            case .success: break
            case .failure(let error as NSError):
                let message: String

                if let sourceDescription = error.sourceDescription
                {
                    message = error.localizedDescription + "\n\n" + sourceDescription
                }
                else
                {
                    message = error.localizedDescription
                }

                let alertController = UIAlertController(title: errorTitle, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                self.present(alertController, animated: true, completion: nil)
            }
            
            NotificationCenter.default.post(name: AppDelegate.operationDidFinishNotification, object: nil, userInfo: [AppDelegate.operationResultKey: result])
        }
    }
}
