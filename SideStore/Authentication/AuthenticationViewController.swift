//
//  AuthenticationViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltSign

class AuthenticationViewController: UIViewController
{
    var authenticationHandler: ((String, String, @escaping (Result<(ALTAccount, ALTAppleAPISession), Error>) -> Void) -> Void)?
    var completionHandler: (((ALTAccount, ALTAppleAPISession, String)?) -> Void)?
    
    private weak var toastView: ToastView?
    
    @IBOutlet private var appleIDTextField: UITextField!
    @IBOutlet private var passwordTextField: UITextField!
    @IBOutlet private var signInButton: UIButton!
    
    @IBOutlet private var appleIDBackgroundView: UIView!
    @IBOutlet private var passwordBackgroundView: UIView!
    
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentStackView: UIStackView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.signInButton.activityIndicatorView.style = .white
        
        for view in [self.appleIDBackgroundView!, self.passwordBackgroundView!, self.signInButton!]
        {
            view.clipsToBounds = true
            view.layer.cornerRadius = 16
        }

        if UIScreen.main.isExtraCompactHeight
        {
            self.contentStackView.spacing = 20
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(AuthenticationViewController.textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: self.appleIDTextField)
        NotificationCenter.default.addObserver(self, selector: #selector(AuthenticationViewController.textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: self.passwordTextField)
        
        self.update()
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        self.signInButton.isIndicatingActivity = false
        self.toastView?.dismiss()
    }
}

private extension AuthenticationViewController
{
    func update()
    {
        if let _ = self.validate()
        {
            self.signInButton.isEnabled = true
            self.signInButton.alpha = 1.0
        }
        else
        {
            self.signInButton.isEnabled = false
            self.signInButton.alpha = 0.6
        }
    }
    
    func validate() -> (String, String)?
    {
        guard
            let emailAddress = self.appleIDTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !emailAddress.isEmpty,
            let password = self.passwordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
        else { return nil }
        
        return (emailAddress, password)
    }
}

private extension AuthenticationViewController
{
    @IBAction func authenticate()
    {
        guard let (emailAddress, password) = self.validate() else { return }
        
        self.appleIDTextField.resignFirstResponder()
        self.passwordTextField.resignFirstResponder()
        
        self.signInButton.isIndicatingActivity = true
        
        self.authenticationHandler?(emailAddress, password) { (result) in
            switch result
            {
            case .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                // Ignore
                DispatchQueue.main.async {
                    self.signInButton.isIndicatingActivity = false
                }
                
            case .failure(let error as NSError):
                DispatchQueue.main.async {
                    let error = error.withLocalizedFailure(NSLocalizedString("Failed to Log In", comment: ""))
                    
                    let toastView = ToastView(error: error)
                    toastView.textLabel.textColor = .altPink
                    toastView.detailTextLabel.textColor = .altPink
                    toastView.show(in: self)
                    self.toastView = toastView
                    
                    self.signInButton.isIndicatingActivity = false
                }
                
            case .success((let account, let session)):
                self.completionHandler?((account, session, password))
            }
            
            DispatchQueue.main.async {
                self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.view.safeAreaInsets.top), animated: true)
            }
        }
    }
    
    @IBAction func cancel(_ sender: UIBarButtonItem)
    {
        self.completionHandler?(nil)
    }
}

extension AuthenticationViewController: UITextFieldDelegate
{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        switch textField
        {
        case self.appleIDTextField: self.passwordTextField.becomeFirstResponder()
        case self.passwordTextField: self.authenticate()
        default: break
        }
        
        self.update()
        
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField)
    {
        guard UIScreen.main.isExtraCompactHeight else { return }
        
        // Position all the controls within visible frame.
        var contentOffset = self.scrollView.contentOffset
        contentOffset.y = 44
        self.scrollView.setContentOffset(contentOffset, animated: true)
    }
}

extension AuthenticationViewController
{
    @objc func textFieldDidChangeText(_ notification: Notification)
    {
        self.update()
    }
}
