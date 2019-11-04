//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

class LaunchViewController: RSTLaunchViewController
{
    private var didFinishLaunching = false
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { (completionHandler) in
            DatabaseManager.shared.start(completionHandler: completionHandler)
        }

        return [isDatabaseStarted]
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return self.children.first
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.children.first
    }
}

extension LaunchViewController
{
    override func handleLaunchError(_ error: Error)
    {
        do
        {
            throw error
        }
        catch let error as NSError
        {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch AltStore", comment: "")
            
            let alertController = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default, handler: { (action) in
                self.handleLaunchConditions()
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func finishLaunching()
    {
        super.finishLaunching()
        
        guard !self.didFinishLaunching else { return }
        
        AppManager.shared.update()
        PatreonAPI.shared.refreshPatreonAccount()
        
        // Add view controller as child (rather than presenting modally)
        // so tint adjustment + card presentations works correctly.
        let viewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as! TabBarController
        viewController.view.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        viewController.view.alpha = 0.0
        self.addChild(viewController)
        self.view.addSubview(viewController.view, pinningEdgesWith: .zero)
        viewController.didMove(toParent: self)
        
        UIView.animate(withDuration: 0.2) {
            viewController.view.alpha = 1.0
        }
        
        self.didFinishLaunching = true
    }
}
