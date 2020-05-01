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
            self.preferredDuration = 4.0
        }
        else
        {
            self.preferredDuration = 8.0
        }
        
        super.init(text: text, detailText: detailedText)
        
        self.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        self.setNeedsLayout()
        
        if let stackView = self.textLabel.superview as? UIStackView
        {
            // RSTToastView does not expose stack view containing labels,
            // so we access it indirectly as the labels' superview.
            stackView.spacing = (detailedText != nil) ? 4.0 : 0.0
        }
    }
    
    convenience init(error: Error)
    {
        let error = error as NSError
        
        let text: String
        let detailText: String?
        
        if let failure = error.localizedFailure
        {
            text = failure
            detailText = error.localizedFailureReason ?? error.localizedRecoverySuggestion ?? error.localizedDescription
        }
        else if let reason = error.localizedFailureReason
        {
            text = reason
            detailText = error.localizedRecoverySuggestion
        }
        else
        {
            text = error.localizedDescription
            detailText = nil
        }
        
        self.init(text: text, detailText: detailText)
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        // Rough calculation to determine height of ToastView with one-line textLabel.
        let minimumHeight = self.textLabel.font.lineHeight.rounded() + 18
        self.layer.cornerRadius = minimumHeight/2
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
