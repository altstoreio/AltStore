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

extension ToastView
{
    static let openErrorLogNotification = Notification.Name("ALTOpenErrorLogNotification")
}

class ToastView: RSTToastView
{
    var preferredDuration: TimeInterval
    
    var opensErrorLog: Bool = false
    
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
            stackView.alignment = .leading
        }
        
        self.addTarget(self, action: #selector(ToastView.showErrorLog), for: .touchUpInside)
    }
    
    convenience init(error: Error)
    {
        var error = error as NSError
        var underlyingError = error.underlyingError
        
        if
            let unwrappedUnderlyingError = underlyingError,
            error.domain == AltServerErrorDomain && error.code == ALTServerError.Code.underlyingError.rawValue
        {
            // Treat underlyingError as the primary error, but keep localized title + failure.
            
            let nsError = (error as NSError)
            error = (unwrappedUnderlyingError as NSError)
            
            if let localizedTitle = nsError.localizedTitle
            {
                error = error.withLocalizedTitle(localizedTitle)
            }
            
            if let localizedFailure = nsError.localizedFailure
            {
                error = error.withLocalizedFailure(localizedFailure)
            }
            
            underlyingError = nil
        }
        
        let text = error.localizedTitle ?? NSLocalizedString("Operation Failed", comment: "")
        let detailText = error.localizedDescription
        
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
    
    override func show(in view: UIView, duration: TimeInterval)
    {
        if self.opensErrorLog,
           case let configuration = UIImage.SymbolConfiguration(font: self.textLabel.font),
           let icon = UIImage(systemName: "chevron.right.circle", withConfiguration: configuration)
        {
            let tintedIcon = icon.withTintColor(.white, renderingMode: .alwaysOriginal)
            
            let moreIconImageView = UIImageView(image: tintedIcon)
            moreIconImageView.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(moreIconImageView)
            
            NSLayoutConstraint.activate([
                moreIconImageView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -self.layoutMargins.right),
                moreIconImageView.centerYAnchor.constraint(equalTo: self.textLabel.centerYAnchor),
                moreIconImageView.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: self.textLabel.trailingAnchor, multiplier: 1.0)
            ])
        }
        
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

private extension ToastView
{
    @objc func showErrorLog()
    {
        guard self.opensErrorLog else { return }
        
        NotificationCenter.default.post(name: ToastView.openErrorLogNotification, object: self)
    }
}
