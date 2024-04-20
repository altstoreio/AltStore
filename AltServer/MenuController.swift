//
//  MenuController.swift
//  AltServer
//
//  Created by Riley Testut on 3/3/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import Foundation
import AppKit

protocol MenuDisplayable
{
    var name: String { get }
}

class MenuController<T: MenuDisplayable & Hashable>: NSObject, NSMenuDelegate
{
    let menu: NSMenu
    
    var items: [T] {
        didSet {
            self.submenus.removeAll()
            self.updateMenu()
        }
    }
    
    var placeholder: String? {
        didSet {
            self.updateMenu()
        }
    }
    
    var action: ((T) -> Void)?
    
    var submenuHandler: ((T) -> NSMenu)?
    private var submenus = [T: NSMenu]()
    
    init(menu: NSMenu, items: [T])
    {
        self.menu = menu
        self.items = items
        
        super.init()
        
        self.menu.delegate = self
    }
    
    @objc
    private func performAction(_ menuItem: NSMenuItem)
    {
        guard case let index = self.menu.index(of: menuItem), index != -1 else { return }
        
        let item = self.items[index]
        self.action?(item)
    }
    
    @objc
    func numberOfItems(in menu: NSMenu) -> Int
    {
        let numberOfItems = (self.items.isEmpty && self.placeholder != nil) ? 1 : self.items.count
        return numberOfItems
    }
    
    @objc
    func menu(_ menu: NSMenu, update menuItem: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool
    {
        if let text = self.placeholder, self.items.isEmpty
        {
            menuItem.title = text
            menuItem.isEnabled = false
            menuItem.target = nil
            menuItem.action = nil
        }
        else
        {
            let item = self.items[index]
            
            menuItem.title = item.name
            menuItem.isEnabled = true
            menuItem.target = self
            menuItem.action = #selector(MenuController.performAction(_:))
            menuItem.tag = index
            
            if let submenu = self.submenus[item] ?? self.submenuHandler?(item)
            {
                menuItem.submenu = submenu
                
                // Cache submenu to prevent duplicate calls to submenuHandler.
                self.submenus[item] = submenu
            }
        }
        
        return true
    }
}

private extension MenuController
{
    func updateMenu()
    {        
        self.menu.removeAllItems()
        
        let numberOfItems = self.numberOfItems(in: self.menu)
        for index in 0 ..< numberOfItems
        {
            let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            guard self.menu(self.menu, update: menuItem, at: index, shouldCancel: false) else { break }
            
            self.menu.addItem(menuItem)
        }
        
        self.menu.update()
    }
}
