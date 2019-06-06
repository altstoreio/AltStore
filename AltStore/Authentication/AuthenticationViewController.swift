//
//  AuthenticationViewController.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltSign
import Roxas

class AuthenticationViewController: UITableViewController
{
    var authenticationHandler: (((ALTAccount, String)?) -> Void)?
    
    private var _didLayoutSubviews = false
    
    @IBOutlet private var emailAddressTextField: UITextField!
    @IBOutlet private var passwordTextField: UITextField!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.update()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if !_didLayoutSubviews
        {
            self.emailAddressTextField.becomeFirstResponder()
        }
        
        _didLayoutSubviews = true
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        self.navigationItem.rightBarButtonItem?.isIndicatingActivity = false
    }
}

private extension AuthenticationViewController
{
    func update()
    {
        if let _ = self.validate()
        {
            self.navigationItem.rightBarButtonItem?.isEnabled = true
        }
        else
        {
            self.navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }
    
    func validate() -> (String, String)?
    {
        guard
            let emailAddress = self.emailAddressTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !emailAddress.isEmpty,
            let password = self.passwordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
        else { return nil }
        
        return (emailAddress, password)
    }
    
    func authenticate(emailAddress: String, password: String, completionHandler: @escaping (Result<(ALTAccount, [ALTTeam]), Error>) -> Void)
    {
        ALTAppleAPI.shared.authenticate(appleID: emailAddress, password: password) { (account, error) in
            switch Result(account, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let account):
                
                ALTAppleAPI.shared.fetchTeams(for: account) { (teams, error) in
                    let result = Result(teams, error).map { (account, $0) }
                    completionHandler(result)
                }
            }
        }
    }
}

private extension AuthenticationViewController
{
    @IBAction func authenticate()
    {
        guard let (emailAddress, password) = self.validate() else { return }
        
        self.emailAddressTextField.resignFirstResponder()
        self.passwordTextField.resignFirstResponder()
        
        self.navigationItem.rightBarButtonItem?.isIndicatingActivity = true
        
        ALTAppleAPI.shared.authenticate(appleID: emailAddress, password: password) { (account, error) in
            do
            {
                let account = try Result(account, error).get()
                self.authenticationHandler?((account, password))
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = RSTToastView(text: NSLocalizedString("Failed to Log In", comment: ""), detailText: error.localizedDescription)
                    toastView.tintColor = .altPurple
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    
                    self.navigationItem.rightBarButtonItem?.isIndicatingActivity = false
                }
            }
        }
    }
    
    @IBAction func cancel()
    {
        self.authenticationHandler?(nil)
    }
}

extension AuthenticationViewController: UITextFieldDelegate
{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        switch textField
        {
        case self.emailAddressTextField: self.passwordTextField.becomeFirstResponder()
        case self.passwordTextField: self.authenticate()
        default: break
        }
        
        self.update()
        
        return false
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    {
        DispatchQueue.main.async {
            self.update()
        }
        
        return true
    }
}
