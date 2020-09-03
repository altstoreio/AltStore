//
//  ToastView.swift
//  AltStore
//
//  Created by Riley Testut on 7/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Roxas

import AltStoreCore

extension TimeInterval
{
    static let shortToastViewDuration = 4.0
    static let longToastViewDuration = 8.0
}

class ToastView: RSTToastView
{
    var preferredDuration: TimeInterval
    
    override init(text: String, detailText detailedText: String?)
    {
        if detailedText == nil
        {
            self.preferredDuration = .shortToastViewDuration
        }
        else
        {
            self.preferredDuration = .longToastViewDuration
        }
        
        super.init(text: text, detailText: detailedText)
        
        self.isAccessibilityElement = true
        
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
        var error = error as NSError
        var underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError
        
        var preferredDuration: TimeInterval?
        
        if
            let unwrappedUnderlyingError = underlyingError,
            error.domain == AltServerErrorDomain && error.code == ALTServerError.Code.underlyingError.rawValue
        {
            // Treat underlyingError as the primary error.
            
            error = unwrappedUnderlyingError
            underlyingError = nil
            
            preferredDuration = .longToastViewDuration
        }
        
        let text: String
        let detailText: String?
        
        if let failure = error.localizedFailure
        {
            text = failure
            detailText = error.localizedFailureReason ?? error.localizedRecoverySuggestion ?? underlyingError?.localizedDescription ?? error.localizedDescription
        }
        else if let reason = error.localizedFailureReason
        {
            text = reason
            detailText = error.localizedRecoverySuggestion ?? underlyingError?.localizedDescription
        }
        else
        {
            text = error.localizedDescription
            detailText = underlyingError?.localizedDescription ?? error.localizedRecoverySuggestion
        }
        
        self.init(text: text, detailText: detailText)
        
        if let preferredDuration = preferredDuration
        {
            self.preferredDuration = preferredDuration
        }
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
    
    override func show(in view: UIView, duration: TimeInterval)
    {
        super.show(in: view, duration: duration)
        
        let announcement = (self.textLabel.text ?? "") + ". " + (self.detailTextLabel.text ?? "")
        self.accessibilityLabel = announcement
        
        // Minimum 0.75 delay to prevent announcement being cut off by VoiceOver.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
    
    override func show(in view: UIView)
    {
        self.show(in: view, duration: self.preferredDuration)
    }
}
