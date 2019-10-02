//
//  LicensesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class LicensesViewController: UITableViewController
{
    private var licenses: [[String: String]] = []

    override func viewDidLoad()
    {
        super.viewDidLoad()
        loadLicenses()
    }

    private func loadLicenses()
    {
        guard let path = Bundle.main.path(forResource: "licenses", ofType: "json") else {
            dismiss(animated: true)
            return
        }

        let url = URL(fileURLWithPath: path)

        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            dismiss(animated: true)
            return
        }

        licenses = json
    }
}

extension LicensesViewController
{
    override func numberOfSections(in tableView: UITableView) -> Int
    {
        return licenses.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "licenseListCell", for: indexPath) as! LicenseTableViewCell
        let license = licenses[indexPath.section]

//        switch indexPath.row {
//        case 0:
//            cell.style = .top
//            break
//        case licenses.count - 1:
//            cell.style = .bottom
//            break
//        default:
//            cell.style = .middle
//        }

        cell.productLabel.text = license["product"]
        cell.authorLabel.text = license["author"]

        return cell
    }
}
