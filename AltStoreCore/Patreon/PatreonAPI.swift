//
//  PatreonAPI.swift
//  AltStore
//
//  Created by Riley Testut on 8/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AuthenticationServices
import CoreData
import WebKit

private let clientID = "ZMx0EGUWe4TVWYXNZZwK_fbIK5jHFVWoUf1Qb-sqNXmT-YzAGwDPxxq7ak3_W5Q2"
private let clientSecret = "1hktsZB89QyN69cB4R0tu55R4TCPQGXxvebYUUh7Y-5TLSnRswuxs6OUjdJ74IJt"

typealias PatreonAPIError = PatreonAPIErrorCode.Error
enum PatreonAPIErrorCode: Int, ALTErrorEnum, CaseIterable
{
    case unknown
    case notAuthenticated
    case invalidAccessToken
    
    var errorFailureReason: String {
        switch self
        {
        case .unknown: return NSLocalizedString("An unknown error occurred.", comment: "")
        case .notAuthenticated: return NSLocalizedString("No connected Patreon account.", comment: "")
        case .invalidAccessToken: return NSLocalizedString("Invalid access token.", comment: "")
        }
    }
}

extension PatreonAPI
{
    static let altstoreCampaignID = "2863968"
    
    typealias FetchAccountResponse = Response<UserAccountResponse>
    typealias FriendZonePatronsResponse = Response<[PatronResponse]>
    
    enum AuthorizationType
    {
        case none
        case user
        case creator
    }
}

public class PatreonAPI: NSObject
{
    public static let shared = PatreonAPI()
    
    public var isAuthenticated: Bool {
        return Keychain.shared.patreonAccessToken != nil
    }
    
    private var authenticationSession: ASWebAuthenticationSession?
    
    private let session = URLSession(configuration: .ephemeral)
    private let baseURL = URL(string: "https://www.patreon.com/")!
    
    private var authHandlers = [(Result<PatreonAccount, Swift.Error>) -> Void]()
    private var authContinuation: CheckedContinuation<URL, Error>?
    private weak var webViewController: WebViewController?
    
    private override init()
    {
        super.init()
    }
}

public extension PatreonAPI
{
    func authenticate(presentingViewController: UIViewController, completion: @escaping (Result<PatreonAccount, Swift.Error>) -> Void)
    {
        Task<Void, Never>.detached { @MainActor in
            guard self.authHandlers.isEmpty else {
                self.authHandlers.append(completion)
                return
            }
            
            self.authHandlers.append(completion)
            
            do
            {
                var components = URLComponents(string: "/oauth2/authorize")!
                components.queryItems = [URLQueryItem(name: "response_type", value: "code"),
                                         URLQueryItem(name: "client_id", value: clientID),
                                         URLQueryItem(name: "redirect_uri", value: "https://rileytestut.com/patreon/altstore"),
                                         URLQueryItem(name: "scope", value: "identity identity[email] identity.memberships campaigns.posts")]
                
                let requestURL = components.url(relativeTo: self.baseURL)
                
                let configuration = WKWebViewConfiguration()
                configuration.setURLSchemeHandler(self, forURLScheme: "altstore")
                configuration.websiteDataStore = .default()
                
                let webViewController = WebViewController(url: requestURL, configuration: configuration)
                webViewController.delegate = self
                self.webViewController = webViewController
                
                let callbackURL = try await withCheckedThrowingContinuation { continuation in
                    self.authContinuation = continuation
                    
                    let navigationController = UINavigationController(rootViewController: webViewController)
                    presentingViewController.present(navigationController, animated: true)
                }
                
                guard
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let codeQueryItem = components.queryItems?.first(where: { $0.name == "code" }),
                    let code = codeQueryItem.value
                else { throw PatreonAPIError(.unknown) }
                
                let (accessToken, refreshToken) = try await withCheckedThrowingContinuation { continuation in
                    self.fetchAccessToken(oauthCode: code) { result in
                        continuation.resume(with: result)
                    }
                }
                Keychain.shared.patreonAccessToken = accessToken
                Keychain.shared.patreonRefreshToken = refreshToken
                
                let patreonAccount = try await withCheckedThrowingContinuation { continuation in
                    self.fetchAccount { result in
                        let result = result.map { AsyncManaged(wrappedValue: $0) }
                        continuation.resume(with: result)
                    }
                }
                
                await self.saveAuthCookies()
                
                await patreonAccount.perform { patreonAccount in
                    for callback in self.authHandlers
                    {
                        callback(.success(patreonAccount))
                    }
                }
            }
            catch
            {
                for callback in self.authHandlers
                {
                    callback(.failure(error))
                }
            }
            
            self.authHandlers = []
            
            await MainActor.run {
                self.webViewController?.dismiss(animated: true)
                self.webViewController = nil
            }
        }
    }
    
    func fetchAccount(completion: @escaping (Result<PatreonAccount, Swift.Error>) -> Void)
    {
        var components = URLComponents(string: "/api/oauth2/v2/identity")!
        components.queryItems = [URLQueryItem(name: "include", value: "memberships.campaign.tiers,memberships.currently_entitled_tiers.benefits"),
                                 URLQueryItem(name: "fields[user]", value: "first_name,full_name"),
                                 URLQueryItem(name: "fields[tier]", value: "title,amount_cents"),
                                 URLQueryItem(name: "fields[benefit]", value: "title"),
                                 URLQueryItem(name: "fields[campaign]", value: "url"),
                                 URLQueryItem(name: "fields[member]", value: "full_name,patron_status,currently_entitled_amount_cents")]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        let request = URLRequest(url: requestURL)
        
        self.send(request, authorizationType: .user) { (result: Result<FetchAccountResponse, Swift.Error>) in
            switch result
            {
            case .failure(~PatreonAPIErrorCode.notAuthenticated):
                self.signOut() { (result) in
                    completion(.failure(PatreonAPIError(.notAuthenticated)))
                }
                
            case .failure(let error as NSError):
                Logger.main.error("Failed to fetch Patreon account. \(error.localizedDebugDescription ?? error.localizedDescription, privacy: .public)")
                completion(.failure(error))
                
            case .success(let response):
                let account = PatreonAPI.UserAccount(response: response.data, including: response.included)
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let account = PatreonAccount(account: account, context: context)
                    Keychain.shared.patreonAccountID = account.identifier
                    completion(.success(account))
                }
            }
        }
    }
    
    func fetchPatrons(completion: @escaping (Result<[Patron], Swift.Error>) -> Void)
    {
        var components = URLComponents(string: "/api/oauth2/v2/campaigns/\(PatreonAPI.altstoreCampaignID)/members")!
        components.queryItems = [URLQueryItem(name: "include", value: "currently_entitled_tiers,currently_entitled_tiers.benefits"),
                                 URLQueryItem(name: "fields[tier]", value: "title,amount_cents"),
                                 URLQueryItem(name: "fields[benefit]", value: "title"),
                                 URLQueryItem(name: "fields[member]", value: "full_name,patron_status,currently_entitled_amount_cents"),
                                 URLQueryItem(name: "page[size]", value: "1000")]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        
        var allPatrons = [Patron]()
        
        func fetchPatrons(url: URL)
        {
            let request = URLRequest(url: url)
            
            self.send(request, authorizationType: .creator) { (result: Result<FriendZonePatronsResponse, Swift.Error>) in
                switch result
                {
                case .failure(let error): completion(.failure(error))
                case .success(let patronsResponse):
                    let patrons = patronsResponse.data.map { (response) -> Patron in
                        let patron = Patron(response: response, including: patronsResponse.included)
                        return patron
                    }.filter { $0.benefits.contains(where: { $0.identifier == .credits }) }
                    
                    allPatrons.append(contentsOf: patrons)
                    
                    if let nextURL = patronsResponse.links?["next"]
                    {
                        fetchPatrons(url: nextURL)
                    }
                    else
                    {
                        completion(.success(allPatrons))
                    }
                }
            }
        }
        
        fetchPatrons(url: requestURL)
    }
    
    func signOut(completion: @escaping (Result<Void, Swift.Error>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            do
            {
                let accounts = PatreonAccount.all(in: context, requestProperties: [\.returnsObjectsAsFaults: true])
                accounts.forEach(context.delete(_:))
                
                let pledgeRequiredApps = StoreApp.all(satisfying: NSPredicate(format: "%K == YES", #keyPath(StoreApp.isPledgeRequired)), in: context)
                pledgeRequiredApps.forEach { $0.isPledged = false }
                
                try context.save()
                
                Keychain.shared.patreonAccessToken = nil
                Keychain.shared.patreonRefreshToken = nil
                Keychain.shared.patreonAccountID = nil
                
                Task<Void, Never>.detached {
                    await self.deleteAuthCookies()
                    completion(.success(()))
                }
            }
            catch
            {
                completion(.failure(error))
            }
        }
    }
    
    func refreshPatreonAccount()
    {
        guard PatreonAPI.shared.isAuthenticated else { return }
        
        PatreonAPI.shared.fetchAccount { (result: Result<PatreonAccount, Swift.Error>) in
            do
            {
                let account = try result.get()
                try account.managedObjectContext?.save()
            }
            catch
            {
                print("Failed to fetch Patreon account.", error)
            }
        }
    }
}

extension PatreonAPI
{
    private func saveAuthCookies() async
    {
        let cookieStore = await MainActor.run { WKWebsiteDataStore.default().httpCookieStore } // Must access from main actor
        
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where cookie.domain.lowercased().hasSuffix("patreon.com")
        {
            Logger.main.debug("Saving Patreon cookie \(cookie.name, privacy: .public): \(cookie.value, privacy: .private(mask: .hash)) (Expires: \(cookie.expiresDate?.description ?? "nil", privacy: .public))")
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
    
    public func deleteAuthCookies() async
    {
        Logger.main.info("Clearing Patreon cookie cache...")
        
        let cookieStore = await MainActor.run { WKWebsiteDataStore.default().httpCookieStore } // Must access from main actor
                        
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.patreon.com")!)
        {
            for cookie in cookies
            {
                Logger.main.debug("Deleting Patreon cookie \(cookie.name, privacy: .public) (Expires: \(cookie.expiresDate?.description ?? "nil", privacy: .public))")
                
                await cookieStore.deleteCookie(cookie)
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            
            Logger.main.info("Cleared Patreon cookie cache!")
        }
        else
        {
            Logger.main.info("No Patreon cookies to clear.")
        }
    }
}

extension PatreonAPI: WebViewControllerDelegate
{
    public func webViewControllerDidFinish(_ webViewController: WebViewController)
    {
        guard let authContinuation else { return }
        self.authContinuation = nil
        
        authContinuation.resume(throwing: CancellationError())
    }
}

private extension PatreonAPI
{
    func fetchAccessToken(oauthCode: String, completion: @escaping (Result<(String, String), Swift.Error>) -> Void)
    {
        let encodedRedirectURI = ("https://rileytestut.com/patreon/altstore" as NSString).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let encodedOauthCode = (oauthCode as NSString).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        
        let body = "code=\(encodedOauthCode)&grant_type=authorization_code&client_id=\(clientID)&client_secret=\(clientSecret)&redirect_uri=\(encodedRedirectURI)"
        
        let requestURL = URL(string: "/api/oauth2/token", relativeTo: self.baseURL)!
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        struct Response: Decodable
        {
            var access_token: String
            var refresh_token: String
        }
        
        self.send(request, authorizationType: .none) { (result: Result<Response, Swift.Error>) in
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success(let response): completion(.success((response.access_token, response.refresh_token)))
            }
        }
    }
    
    func refreshAccessToken(completion: @escaping (Result<Void, Swift.Error>) -> Void)
    {
        guard let refreshToken = Keychain.shared.patreonRefreshToken else { return }
        
        var components = URLComponents(string: "/api/oauth2/token")!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"),
                                 URLQueryItem(name: "refresh_token", value: refreshToken),
                                 URLQueryItem(name: "client_id", value: clientID),
                                 URLQueryItem(name: "client_secret", value: clientSecret)]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        
        struct Response: Decodable
        {
            var access_token: String
            var refresh_token: String
        }
        
        self.send(request, authorizationType: .none) { (result: Result<Response, Swift.Error>) in
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                Keychain.shared.patreonAccessToken = response.access_token
                Keychain.shared.patreonRefreshToken = response.refresh_token
                
                completion(.success(()))
            }
        }
    }
    
    func send<ResponseType: Decodable>(_ request: URLRequest, authorizationType: AuthorizationType, completion: @escaping (Result<ResponseType, Swift.Error>) -> Void)
    {
        var request = request
        
        switch authorizationType
        {
        case .none: break
        case .creator:
            guard let creatorAccessToken = Keychain.shared.patreonCreatorAccessToken else { return completion(.failure(PatreonAPIError(.invalidAccessToken))) }
            request.setValue("Bearer " + creatorAccessToken, forHTTPHeaderField: "Authorization")
            
        case .user:
            guard let accessToken = Keychain.shared.patreonAccessToken else { return completion(.failure(PatreonAPIError(.notAuthenticated))) }
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        }
        
        let task = self.session.dataTask(with: request) { (data, response, error) in
            do
            {
                let data = try Result(data, error).get()
                
                if let response = response as? HTTPURLResponse, response.statusCode == 401
                {
                    switch authorizationType
                    {
                    case .creator: completion(.failure(PatreonAPIError(.invalidAccessToken)))
                    case .none: completion(.failure(PatreonAPIError(.notAuthenticated)))
                    case .user:
                        self.refreshAccessToken() { (result) in
                            switch result
                            {
                            case .failure(let error): completion(.failure(error))
                            case .success: self.send(request, authorizationType: authorizationType, completion: completion)
                            }
                        }
                    }
                    
                    return
                }
                
                let response = try JSONDecoder().decode(ResponseType.self, from: data)
                completion(.success(response))
            }
            catch let error
            {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
}

extension PatreonAPI: WKURLSchemeHandler
{
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask)
    {
        guard let authContinuation else { return }
        self.authContinuation = nil
                
        if let callbackURL = urlSchemeTask.request.url
        {
            authContinuation.resume(returning: callbackURL)
        }
        else
        {
            authContinuation.resume(throwing: URLError(.badURL))
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask)
    {
        Logger.main.debug("WKWebView stopped handling url scheme.")
    }
}
