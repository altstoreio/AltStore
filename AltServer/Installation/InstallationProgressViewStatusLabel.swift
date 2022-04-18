//
//  InstallationProgressViewStatusLabel.swift
//  AltServer
//
//  Created by royal on 10/01/2022.
//

import Cocoa

@IBDesignable
class InstallationProgressViewStatusLabel: NSView {

    @IBInspectable var string: String = "Label" {
        didSet { labelView.stringValue = string }
    }

    var progress: Double? {
        didSet {
            if let progress = progress {
                progressView.isIndeterminate = false
                progressView.doubleValue = progress
            } else {
                progressView.isIndeterminate = true
            }
        }
    }

    private let labelView = NSTextField()
    private let progressView = NSProgressIndicator()
    private let doneCheckmarkView = NSImageView()

//    private let pendingFont = NSFont.preferredFont(for: .body, weight: .medium)
//    private let currentFont = NSFont.preferredFont(for: .body, weight: .semibold)
//    private let doneFont = NSFont.preferredFont(for: .body, weight: .medium)
    private let pendingFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private let currentFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    private let doneFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

    private let pendingColor = NSColor.tertiaryLabelColor
    private let currentColor = NSColor.labelColor
    private let doneColor = NSColor.secondaryLabelColor

    private let statusViewWidth: CGFloat = 16

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        setupLabel(in: dirtyRect)
        setupProgressView(in: dirtyRect)
        setupDoneCheckmarkView(in: dirtyRect)

        setupConstraints(in: dirtyRect)
    }

    private func setupLabel(in dirtyRect: NSRect) {
        labelView.textColor = pendingColor
        labelView.font = pendingFont

        labelView.isEditable = false
        labelView.isSelectable = false
        labelView.isEnabled = false
        labelView.isBordered = false

        labelView.drawsBackground = false
        labelView.maximumNumberOfLines = 0

        labelView.stringValue = string

        addSubview(labelView)
    }

    private func setupProgressView(in dirtyRect: NSRect) {
        progressView.controlSize = .small
        progressView.frame = NSRect(x: 0, y: 0, width: statusViewWidth, height: statusViewWidth)

        progressView.isIndeterminate = true
        progressView.isDisplayedWhenStopped = false

        progressView.style = .spinning

        progressView.minValue = 0
        progressView.maxValue = 1

        addSubview(progressView)
    }

    private func setupDoneCheckmarkView(in dirtyRect: NSRect) {
        doneCheckmarkView.frame = NSRect(x: 0, y: 0, width: statusViewWidth, height: statusViewWidth)
        doneCheckmarkView.image = createSuccessImage(success: true)

        doneCheckmarkView.isEditable = false
        doneCheckmarkView.isHidden = true

        addSubview(doneCheckmarkView)
    }

    private func setupConstraints(in dirtyRect: NSRect) {
        labelView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        doneCheckmarkView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -statusViewWidth),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: labelView.centerYAnchor),

            doneCheckmarkView.centerYAnchor.constraint(equalTo: progressView.centerYAnchor),
            doneCheckmarkView.centerXAnchor.constraint(equalTo: progressView.centerXAnchor)
        ])
    }
    
    internal func createSuccessImage(success: Bool) -> NSImage? {
        let image = NSImage(named: success ? NSImage.menuOnStateTemplateName : NSImage.stopProgressTemplateName)
        return image
    }
}

extension InstallationProgressViewStatusLabel {
    enum Status {
        case pending, current, done, failed
    }

    public func update(status: Status) {
        switch status {
            case .pending:
                labelView.font = pendingFont
                labelView.textColor = pendingColor

                progressView.isHidden = true
                progressView.stopAnimation(self)

                doneCheckmarkView.isHidden = true
            case .current:
                labelView.font = currentFont
                labelView.textColor = currentColor

                progressView.isHidden = false
                progressView.startAnimation(self)

                doneCheckmarkView.isHidden = true
            case .done:
                labelView.font = doneFont
                labelView.textColor = doneColor

                progressView.isHidden = true
                progressView.stopAnimation(self)

                doneCheckmarkView.contentTintColor = doneColor
                doneCheckmarkView.isHidden = false
            case .failed:
                labelView.font = doneFont
                labelView.textColor = doneColor
                
                progressView.isHidden = true
                progressView.stopAnimation(self)
                
                doneCheckmarkView.image = createSuccessImage(success: false)
                doneCheckmarkView.contentTintColor = doneColor
                doneCheckmarkView.isHidden = false
        }
    }
}
