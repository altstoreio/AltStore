//
//  CreditsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

extension CreditsViewController
{
    struct Section: Decodable
    {
        var name: String
        var credits: [Credit]
    }

    struct Credit: Decodable
    {
        var name: String
        var credit: String
    }
}

class Box<T>
{
    let value: T
    
    init(_ value: T)
    {
        self.value = value
    }
}

class CreditsViewController: UITableViewController
{
    private lazy var sections: [Section] = self.loadCredits()
    private lazy var dataSource = self.makeDataSource()
    
    private var prototypeHeaderFooterView: SettingsHeaderFooterView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        
        let nib = UINib(nibName: "SettingsHeaderFooterView", bundle: nil)
        self.prototypeHeaderFooterView = nib.instantiate(withOwner: nil, options: nil)[0] as? SettingsHeaderFooterView
        
        self.tableView.register(nib, forHeaderFooterViewReuseIdentifier: "HeaderFooterView")
    }
}

private extension CreditsViewController
{
    func makeDataSource() -> RSTCompositeTableViewDataSource<Box<Credit>>
    {
        var dataSources: [RSTArrayTableViewDataSource<Box<Credit>>] = []
        
        for (index, section) in self.sections.enumerated()
        {
            let dataSource = RSTArrayTableViewDataSource<Box<Credit>>(items: section.credits.map(Box.init))
            dataSource.cellConfigurationHandler = { (cell, credit, indexPath) in
                let cell = cell as! InsetGroupTableViewCell
                cell.nameLabel?.text = credit.value.name
                cell.creditLabel?.text = credit.value.credit
                
                let numberOfItems = self.tableView.numberOfRows(inSection: index)
                switch (numberOfItems, indexPath.row)
                {
                case (1, _): cell.style = .single
                case (_, 0): cell.style = .top
                case (_, _) where indexPath.row == numberOfItems - 1: cell.style = .bottom
                case (_, _): cell.style = .middle
                }
            }
            dataSources.append(dataSource)
        }
        
        let dataSource = RSTCompositeTableViewDataSource(dataSources: dataSources)
        dataSource.proxy = self
        return dataSource
    }
    
    func loadCredits() -> [Section]
    {
        do
        {
            let fileURL = Bundle.main.url(forResource: "Credits", withExtension: "plist")!
            let data = try Data(contentsOf: fileURL)
            
            let sections = try PropertyListDecoder().decode([Section].self, from: data)
            return sections
        }
        catch
        {
            print("Failed to load credits:", error)
            return []
        }
    }
    
    func preferredHeight(for settingsHeaderFooterView: SettingsHeaderFooterView, in section: Section) -> CGFloat
    {
        let widthConstraint = settingsHeaderFooterView.contentView.widthAnchor.constraint(equalToConstant: tableView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.prepare(settingsHeaderFooterView, for: section)
        
        let size = settingsHeaderFooterView.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return size.height
    }
    
    func prepare(_ settingsHeaderFooterView: SettingsHeaderFooterView, for section: Section)
    {
        settingsHeaderFooterView.primaryLabel.isHidden = false
        settingsHeaderFooterView.secondaryLabel.isHidden = true
        settingsHeaderFooterView.button.isHidden = true
        settingsHeaderFooterView.layoutMargins.bottom = 0
        
        settingsHeaderFooterView.primaryLabel.text = section.name.uppercased()
    }
}

extension CreditsViewController
{
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        let section = self.sections[section]
        
        let height = self.preferredHeight(for: self.prototypeHeaderFooterView, in: section)
        return height
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        let section = self.sections[section]
        
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HeaderFooterView") as! SettingsHeaderFooterView
        self.prepare(headerView, for: section)
        return headerView
    }
}
