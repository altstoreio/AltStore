//
//  ToastView.swift
//  AltStore
//
//  Created by Riley Testut on 7/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Roxas

class ToastView: RSTToastView
{
    var preferredDuration: TimeInterval
    
    override init(text: String, detailText detailedText: String?)
    {
        if detailedText == nil
        {
            self.preferredDuration = 2.0
        }
        else
        {
            self.preferredDuration = 8.0
        }
        
        super.init(text: text, detailText: detailedText)
        
        self.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        self.setNeedsLayout()
    }
    
    convenience init(error: Error)
    {
        if let error = error as? LocalizedError
        {
            self.init(text: error.localizedDescription, detailText: error.recoverySuggestion ?? error.failureReason)
        }
        else
        {
            self.init(text: error.localizedDescription, detailText: nil)
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.layer.cornerRadius = 16
    }
    
    func show(in viewController: UIViewController)
    {
        self.show(in: viewController.navigationController?.view ?? viewController.view, duration: self.preferredDuration)
    }
    
    override func show(in view: UIView)
    {
        self.show(in: view, duration: self.preferredDuration)
    }
}
