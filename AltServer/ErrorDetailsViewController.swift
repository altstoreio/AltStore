//
//  ErrorDetailsViewController.swift
//  AltServer
//
//  Created by Riley Testut on 10/4/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import AppKit

class ErrorDetailsViewController: NSViewController
{
    var error: NSError? {
        didSet {
            self.update()
        }
    }
    
    @IBOutlet private var errorCodeLabel: NSTextField!
    @IBOutlet private var detailedDescriptionLabel: NSTextField!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.detailedDescriptionLabel.preferredMaxLayoutWidth = 800
    }
}

private extension ErrorDetailsViewController
{
    func update()
    {
        if !self.isViewLoaded
        {
            self.loadView()
        }
        
        guard let error = self.error else { return }
        
        self.errorCodeLabel.stringValue = error.localizedErrorCode
        
        let font = self.detailedDescriptionLabel.font ?? NSFont.systemFont(ofSize: 12)
        let detailedDescription = error.formattedDetailedDescription(with: font)
        self.detailedDescriptionLabel.attributedStringValue = detailedDescription
    }
    
    @IBAction func searchFAQ(_ sender: NSButton)
    {
        guard let error else { return }
        
        let baseURL = URL(string: "https://faq.altstore.io/getting-started/error-codes")!
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        let nsError = error as NSError
        let query = [nsError.domain, "\(error.displayCode)"].joined(separator: "+")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        
        let url = components.url ?? baseURL
        NSWorkspace.shared.open(url)
    }
}

