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

import SafariServices
private let clientID = "ZMx0EGUWe4TVWYXNZZwK_fbIK5jHFVWoUf1Qb-sqNXmT-YzAGwDPxxq7ak3_W5Q2"
private let clientSecret = "1hktsZB89QyN69cB4R0tu55R4TCPQGXxvebYUUh7Y-5TLSnRswuxs6OUjdJ74IJt"

private let campaignID = "2863968"

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
    enum AuthorizationType
    {
        case none
        case user
        case creator
    }
    
    enum AnyResponse: Decodable
    {
        case tier(TierResponse)
        case benefit(BenefitResponse)
        case patron(PatronResponse)
        case campaign(CampaignResponse)
        case unknown(UnknownResponse)
        
        var id: String {
            switch self
            {
            case .tier(let response): return response.id
            case .benefit(let response): return response.id
            case .patron(let response): return response.id
            case .campaign(let response): return response.id
            case .unknown(let response): return response.id
            }
        }
        
//        var type: String {
//            switch self
//            {
//            case .tier(let response): return response.type
//            case .benefit(let response): return response.id
//            case .patron(let response): return response.id
//            case .campaign(let response): return response.id
//            case .unknown(let response): return response.id
//            }
//        }
        
        private enum CodingKeys: String, CodingKey
        {
            case type
        }
        
        init(from decoder: Decoder) throws
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            let type = try container.decode(String.self, forKey: .type)
            switch type
            {
            case "tier":
                let response = try TierResponse(from: decoder)
                self = .tier(response)
                
            case "benefit":
                let response = try BenefitResponse(from: decoder)
                self = .benefit(response)
                
            case "member":
                let response = try PatronResponse(from: decoder)
                self = .patron(response)
                
            case "campaign":
                let response = try CampaignResponse(from: decoder)
                self = .campaign(response)
                
            default:
                Logger.main.error("Unrecognized PatreonAPI response type: \(type, privacy: .public).")
                
                let response = try UnknownResponse(from: decoder)
                self = .unknown(response)
            }
        }
    }
    
    struct UnknownResponse: Decodable
    {
        var id: String
        var type: String
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
    private weak var safariViewController: SFSafariViewController?
    
    private override init()
    {
        super.init()
    }
}

public extension PatreonAPI
{
    func authenticate(presentingViewController: UIViewController, completion: @escaping (Result<PatreonAccount, Swift.Error>) -> Void)
    {
        DispatchQueue.main.async {
            guard self.authHandlers.isEmpty else {
                self.authHandlers.append(completion)
                return
            }
            
            self.authHandlers.append(completion)
            
            var components = URLComponents(string: "/oauth2/authorize")!
            components.queryItems = [URLQueryItem(name: "response_type", value: "code"),
                                     URLQueryItem(name: "client_id", value: clientID),
                                     URLQueryItem(name: "redirect_uri", value: "https://rileytestut.com/patreon/altstore"),
                                     URLQueryItem(name: "scope", value: "identity identity[email] identity.memberships campaigns.posts")
            ]
            
            let requestURL = components.url(relativeTo: self.baseURL)!
            
            let safariViewController = SFSafariViewController(url: requestURL)
            safariViewController.delegate = self
            safariViewController.preferredControlTintColor = .altPrimary
            safariViewController.dismissButtonStyle = .cancel
            presentingViewController.present(safariViewController, animated: true)
            
            self.safariViewController = safariViewController
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
        
        self.send(request, authorizationType: .user) { (result: Result<AccountResponse, Swift.Error>) in
            switch result
            {
            case .failure(~PatreonAPIErrorCode.notAuthenticated):
                self.signOut() { (result) in
                    completion(.failure(PatreonAPIError(.notAuthenticated)))
                }
                
            case .failure(let error as NSError):
                Logger.main.error("Failed to load account. \(error.localizedDebugDescription ?? error.localizedDescription, privacy: .public)")
                completion(.failure(error))
                
            case .success(let response):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let account = PatreonAccount(response: response, context: context)
                    Keychain.shared.patreonAccountID = account.identifier
                    completion(.success(account))
                }
            }
        }
    }
    
    func fetchPatrons(completion: @escaping (Result<[Patron], Swift.Error>) -> Void)
    {
        var components = URLComponents(string: "/api/oauth2/v2/campaigns/\(campaignID)/members")!
        components.queryItems = [URLQueryItem(name: "include", value: "currently_entitled_tiers,currently_entitled_tiers.benefits"),
                                 URLQueryItem(name: "fields[tier]", value: "title"),
                                 URLQueryItem(name: "fields[member]", value: "full_name,patron_status"),
                                 URLQueryItem(name: "page[size]", value: "1000")]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        
        struct Response: Decodable
        {
            var data: [PatronResponse]
            var included: [AnyResponse]
            var links: [String: URL]?
        }
        
        var allPatrons = [Patron]()
        
        func fetchPatrons(url: URL)
        {
            let request = URLRequest(url: url)
            
            self.send(request, authorizationType: .creator) { (result: Result<Response, Swift.Error>) in
                switch result
                {
                case .failure(let error): completion(.failure(error))
                case .success(let response):
                    let tiers = response.included.compactMap { (response) -> Tier? in
                        switch response
                        {
                        case .tier(let tierResponse): return Tier(response: tierResponse)
                        case .benefit, .campaign, .patron, .unknown: return nil
                        }
                    }
                    
                    let tiersByIdentifier = Dictionary(tiers.map { ($0.identifier, $0) }, uniquingKeysWith: { (a, b) in return a })
                    
                    let patrons = response.data.map { (response) -> Patron in
                        let patron = Patron(response: response)
                        
                        for tierID in response.relationships?.currently_entitled_tiers?.data ?? []
                        {
                            guard let tier = tiersByIdentifier[tierID.id] else { continue }
                            patron.benefits.formUnion(tier.benefits)
                        }
                        
                        return patron
                    }.filter { $0.benefits.contains(where: { $0.type == .credits }) }
                    
                    allPatrons.append(contentsOf: patrons)
                    
                    if let nextURL = response.links?["next"]
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
                
                if #available(iOS 16, *)
                {
                    //TODO: Unify implementation w/ logging
                    SFSafariViewController.DataStore.default.clearWebsiteData {
                        completion(.success(()))
                    }
                }
                else
                {
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

public extension PatreonAPI
{
    func handleOAuthCallbackURL(_ callbackURL: URL)
    {
        do
        {
            guard
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                let codeQueryItem = components.queryItems?.first(where: { $0.name == "code" }),
                let code = codeQueryItem.value
            else { throw PatreonAPIError(.unknown) }
            
            self.fetchAccessToken(oauthCode: code) { (result) in
                switch result
                {
                case .failure(let error): self.finishAuthentication(.failure(error))
                case .success((let accessToken, let refreshToken)):
                    Keychain.shared.patreonAccessToken = accessToken
                    Keychain.shared.patreonRefreshToken = refreshToken
                    
                    self.fetchAccount(completion: self.finishAuthentication)
                }
            }
        }
        catch
        {
            self.finishAuthentication(.failure(error))
        }
    }
    
    private func finishAuthentication(_ result: Result<PatreonAccount, Swift.Error>)
    {
        for callback in self.authHandlers
        {
            callback(result)
        }
        
        self.authHandlers = []
        
        DispatchQueue.main.async {
            self.safariViewController?.dismiss(animated: true)
            self.safariViewController = nil
        }
    }
}

extension PatreonAPI: SFSafariViewControllerDelegate
{
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) 
    {
        self.finishAuthentication(.failure(CancellationError()))
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
