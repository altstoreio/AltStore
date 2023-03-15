//
//  SourceAboutViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/15/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore

class SourceAboutViewController: UIViewController
{
    let source: Source
    
    @IBOutlet private var textView: UITextView!
    
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
//        self.title = self.source.name
        
        self.textView.text = """
Lorem ipsum dolizzle sit amizzle, gangster adipiscing elit. Nullam sapizzle velizzle, things volutpizzle, suscipit brizzle, hizzle vel, that's the shizzle. Pellentesque eget tortizzle. Sizzle erizzle. Check it out at dolor dapibus daahng dawg tempizzle shizzlin dizzle. Fo shizzle pellentesque nibh et break it down. Vestibulum izzle shiz. Pellentesque mofo rhoncus dang. In dang sizzle platea dope. Shizzle my nizzle crocodizzle dapibizzle. We gonna chung sure urna, pretizzle the bizzle, mattis dizzle, dang hizzle, nunc. Rizzle suscipizzle. Its fo rizzle semper pimpin' sizzle the bizzle.

Etizzle fo shizzle urna for sure nisl. Mammasay mammasa mamma oo sa quis izzle. Maecenas pulvinar, ipsizzle malesuada malesuada scelerisque, check out this purus euismizzle funky fresh, fo shizzle mah nizzle fo rizzle, mah home g-dizzle luctus metus stuff izzle izzle. Vivamizzle ullamcorper, tortizzle et varizzle shiz, crunk fo shizzle mah nizzle fo rizzle, mah home g-dizzle owned pizzle, izzle sheezy leo elizzle in pizzle. Boofron we gonna chung, orci break yo neck, yall volutpizzle black, sizzle phat luctizzle mah nizzle, for sure bibendizzle enizzle own yo' ut sure. Nullam a izzle izzle shiz hizzle viverra. Phasellus get down get down boofron. Curabitizzle nizzle shit i saw beyonces tizzles and my pizzle went crizzle pede sodalizzle facilisizzle. Hizzle sapizzle boofron, daahng dawg vel, molestie rizzle, yo a, erizzle. Shut the shizzle up vitae owned quis bibendizzle boofron. Nizzle fo shizzle my nizzle consectetuer . Aliquizzle dawg volutpat. Fo shizzle ut leo izzle dang pretizzle faucibus. Cras stuff lacus dui izzle ultricies. Fo shizzle my nizzle nisl. Fo shizzle et own yo'. Integer things rizzle mammasay mammasa mamma oo sa mi. Fo shizzle my nizzle izzle boofron.
"""
        
        self.navigationController?.navigationBar.tintColor = self.source.tintColor
        
        if #available(iOS 15, *), let sheetController = self.navigationController?.sheetPresentationController
        {
            sheetController.detents = [.medium(), .large()]
            sheetController.selectedDetentIdentifier = .medium
            sheetController.prefersGrabberVisible = true
        }
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.textView.textContainerInset.left = self.view.layoutMargins.left
        self.textView.textContainerInset.right = self.view.layoutMargins.right
    }
}
