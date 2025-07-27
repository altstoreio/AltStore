//
//  CollapsingTextView.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class CollapsingTextView: UITextView
{
    var isCollapsed = true {
        didSet {
            guard self.isCollapsed != oldValue else { return }
            self.shouldResetLayout = true
            self.setNeedsLayout()
        }
    }
    
    var maximumNumberOfLines = 2 {
        didSet {
            self.shouldResetLayout = true
            self.setNeedsLayout()
        }
    }
    
    var lineSpacing: Double = 2 {
        didSet {
            self.shouldResetLayout = true
            
            if #available(iOS 16, *)
            {
                self.updateText()
            }
            else
            {
                self.setNeedsLayout()
            }
        }
    }
    
    override var text: String! {
        didSet {
            self.shouldResetLayout = true
            
            guard #available(iOS 16, *) else { return }
            self.updateText()
        }
    }
    
    let moreButton = UIButton(type: .system)
    
    private var shouldResetLayout: Bool = false
    private var previousSize: CGSize?
    
    override init(frame: CGRect, textContainer: NSTextContainer?)
    {
        super.init(frame: frame, textContainer: textContainer)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.initialize()
    }
    
    private func initialize()
    {
        if #available(iOS 16, *)
        {
            self.updateText()
        }
        else
        {
            self.layoutManager.delegate = self
        }
        
        self.textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        self.textContainer.lineBreakMode = .byTruncatingTail
        self.textContainer.heightTracksTextView = true
        self.textContainer.widthTracksTextView = true
        
        self.moreButton.setTitle(NSLocalizedString("More", comment: ""), for: .normal)
        self.moreButton.addTarget(self, action: #selector(CollapsingTextView.toggleCollapsed(_:)), for: .primaryActionTriggered)
        self.addSubview(self.moreButton)
        
        self.setNeedsLayout()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        guard let font = self.font else { return }
        
        let buttonFont = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
        self.moreButton.titleLabel?.font = buttonFont
        
        let buttonY = (font.lineHeight + self.lineSpacing) * CGFloat(self.maximumNumberOfLines - 1)
        let size = self.moreButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        
        let moreButtonFrame = CGRect(x: self.bounds.width - self.moreButton.bounds.width,
                                     y: buttonY,
                                     width: size.width,
                                     height: font.lineHeight)
        self.moreButton.frame = moreButtonFrame
        
        if self.shouldResetLayout || self.previousSize != self.bounds.size
        {
            if self.isCollapsed
            {
                let boundingSize = self.attributedText.boundingRect(with: CGSize(width: self.textContainer.size.width, height: .infinity), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                let maximumCollapsedHeight = font.lineHeight * Double(self.maximumNumberOfLines) + self.lineSpacing * Double(self.maximumNumberOfLines - 1)
                
                if boundingSize.height.rounded() > maximumCollapsedHeight.rounded()
                {
                    self.textContainer.maximumNumberOfLines = self.maximumNumberOfLines
                    
                    var exclusionFrame = moreButtonFrame
                    exclusionFrame.origin.y += self.moreButton.bounds.midY
                    exclusionFrame.size.width = self.bounds.width // Extra wide to make sure it wraps to next line.
                    self.textContainer.exclusionPaths = [UIBezierPath(rect: exclusionFrame)]
                    
                    self.moreButton.isHidden = false
                }
                else
                {
                    self.textContainer.maximumNumberOfLines = 0 // Fixes last line having slightly smaller line spacing.
                    self.textContainer.exclusionPaths = []
                    
                    self.moreButton.isHidden = true
                }
            }
            else
            {
                self.textContainer.maximumNumberOfLines = 0
                self.textContainer.exclusionPaths = []
                
                self.moreButton.isHidden = true
            }
            
            self.invalidateIntrinsicContentSize()
        }
        
        self.shouldResetLayout = false
        self.previousSize = self.bounds.size
    }
}

private extension CollapsingTextView
{
    @objc func toggleCollapsed(_ sender: UIButton)
    {
        self.isCollapsed.toggle()
    }
    
    @available(iOS 16, *)
    func updateText()
    {
        do
        {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = self.lineSpacing
            
            let container = AttributeContainer([.paragraphStyle: style])
            
            var attributedText = try AttributedString(self.attributedText, including: \.uiKit)
            attributedText.mergeAttributes(container, mergePolicy: .keepNew)
            self.attributedText = NSAttributedString(attributedText)
        }
        catch
        {
            print("[ALTLog] Failed to update CollapsingTextView line spacing:", error)
        }
    }
}

extension CollapsingTextView: NSLayoutManagerDelegate
{
    func layoutManager(_ layoutManager: NSLayoutManager, lineSpacingAfterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: CGRect) -> CGFloat
    {
        return self.lineSpacing
    }
}
