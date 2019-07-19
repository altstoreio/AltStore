//
//  PillButton.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class PillButton: UIButton
{
    var progress: Progress? {
        didSet {            
            self.progressView.progress = Float(self.progress?.fractionCompleted ?? 0)
            self.progressView.observedProgress = self.progress
            
            let isUserInteractionEnabled = self.isUserInteractionEnabled
            self.isIndicatingActivity = (self.progress != nil)
            self.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }
    
    var progressTintColor: UIColor? {
        get {
            return self.progressView.progressTintColor
        }
        set {
            self.progressView.progressTintColor = newValue
        }
    }
    
    var isInverted: Bool = false {
        didSet {
            self.update()
        }
    }
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 26
        size.height += 3
        return size
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.layer.masksToBounds = true
        
        self.activityIndicatorView.style = .white
        self.activityIndicatorView.isUserInteractionEnabled = false
        
        self.progressView.progress = 0
        self.progressView.trackImage = UIImage()
        self.progressView.isUserInteractionEnabled = false
        self.addSubview(self.progressView)
        
        self.update()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.progressView.bounds.size.width = self.bounds.width
        
        let scale = self.bounds.height / self.progressView.bounds.height
        
        self.progressView.transform = CGAffineTransform.identity.scaledBy(x: 1, y: scale)
        self.progressView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        
        self.layer.cornerRadius = self.bounds.midY
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
}

private extension PillButton
{
    func update()
    {
        if self.isInverted
        {
            self.setTitleColor(.white, for: .normal)
            self.backgroundColor = self.tintColor
            self.progressView.progressTintColor = self.tintColor.withAlphaComponent(0.15)
        }
        else
        {
            self.setTitleColor(self.tintColor, for: .normal)
            self.backgroundColor = self.tintColor.withAlphaComponent(0.15)
            self.progressView.progressTintColor = self.tintColor
        }
    }
}
