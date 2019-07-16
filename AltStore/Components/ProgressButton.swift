//
//  ProgressButton.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class ProgressButton: UIButton
{
    var progress: Progress? {
        didSet {
            self.progressView.progress = Float(self.progress?.fractionCompleted ?? 0)
            self.progressView.observedProgress = self.progress
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
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 32
        size.height += 4
        return size
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.layer.masksToBounds = true
        
        self.progressView.progress = 0
        self.progressView.trackImage = UIImage()
        self.progressView.isUserInteractionEnabled = false
        self.addSubview(self.progressView)
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
}
