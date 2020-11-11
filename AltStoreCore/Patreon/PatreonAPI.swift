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

private let clientID = "ZMx0EGUWe4TVWYXNZZwK_fbIK5jHFVWoUf1Qb-sqNXmT-YzAGwDPxxq7ak3_W5Q2"
private let clientSecret = "1hktsZB89QyN69cB4R0tu55R4TCPQGXxvebYUUh7Y-5TLSnRswuxs6OUjdJ74IJt"

private let campaignID = "2863968"

extension PatreonAPI
{
    enum Error: LocalizedError
    {
        case unknown
        case notAuthenticated
        case invalidAccessToken
        
        var errorDescription: String? {
            switch self
            {
            case .unknown: return NSLocalizedString("An unknown error occurred.", comment: "")
            case .notAuthenticated: return NSLocalizedString("No connected Patreon account.", comment: "")
            case .invalidAccessToken: return NSLocalizedString("Invalid access token.", comment: "")
            }
        }
    }
    
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
        
        enum CodingKeys: String, CodingKey
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
                let tier = try TierResponse(from: decoder)
                self = .tier(tier)
                
            case "benefit":
                let benefit = try BenefitResponse(from: decoder)
                self = .benefit(benefit)
                
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unrecognized Patreon response type.")
            }
        }
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
    
    private override init()
    {
        super.init()
    }
}

public extension PatreonAPI
{
    func authenticate(completion: @escaping (Result<PatreonAccount, Swift.Error>) -> Void)
    {
        var components = URLComponents(string: "/oauth2/authorize")!
        components.queryItems = [URLQueryItem(name: "response_type", value: "code"),
                                 URLQueryItem(name: "client_id", value: clientID),
                                 URLQueryItem(name: "redirect_uri", value: "https://rileytestut.com/patreon/altstore")]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        
        self.authenticationSession = ASWebAuthenticationSession(url: requestURL, callbackURLScheme: "altstore") { (callbackURL, error) in
            do
            {
                let callbackURL = try Result(callbackURL, error).get()
                
                guard
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let codeQueryItem = components.queryItems?.first(where: { $0.name == "code" }),
                    let code = codeQueryItem.value
                else { throw Error.unknown }
                
                self.fetchAccessToken(oauthCode: code) { (result) in
                    switch result
                    {
                    case .failure(let error): completion(.failure(error))
                    case .success((let accessToken, let refreshToken)):
                        Keychain.shared.patreonAccessToken = accessToken
                        Keychain.shared.patreonRefreshToken = refreshToken
                        
                        self.fetchAccount(completion: completion)
                    }
                }
            }
            catch
            {
                completion(.failure(error))
            }
        }
        
        if #available(iOS 13.0, *)
        {
            self.authenticationSession?.presentationContextProvider = self
        }
        
        self.authenticationSession?.start()
    }
    
    func fetchAccount(completion: @escaping (Result<PatreonAccount, Swift.Error>) -> Void)
    {
        var components = URLComponents(string: "/api/oauth2/v2/identity")!
        components.queryItems = [URLQueryItem(name: "include", value: "memberships"),
                                 URLQueryItem(name: "fields[user]", value: "first_name,full_name"),
                                 URLQueryItem(name: "fields[member]", value: "full_name,patron_status")]
        
        let requestURL = components.url(relativeTo: self.baseURL)!
        let request = URLRequest(url: requestURL)
        
        self.send(request, authorizationType: .user) { (result: Result<AccountResponse, Swift.Error>) in
            switch result
            {
            case .failure(Error.notAuthenticated):
                self.signOut() { (result) in
                    completion(.failure(Error.notAuthenticated))
                }
                
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let account = PatreonAccount(response: response, context: context)
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
                        case .benefit: return nil
                        }
                    }
                    
                    let tiersByIdentifier = Dictionary(tiers.map { ($0.identifier, $0) }, uniquingKeysWith: { (a, b) in return a })
                    
                    let patrons = response.data.map { (response) -> Patron in
                        let patron = Patron(response: response)
                        
                        for tierID in response.relationships?.currently_entitled_tiers.data ?? []
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
                let accounts = PatreonAccount.all(in: context, requestProperties: [\FetchRequest.returnsObjectsAsFaults: true])
                accounts.forEach(context.delete(_:))
                
                self.deactivateBetaApps(in: context)
                
                try context.save()
                
                Keychain.shared.patreonAccessToken = nil
                Keychain.shared.patreonRefreshToken = nil
                
                completion(.success(()))
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
                
                if let context = account.managedObjectContext, !account.isPatron
                {
                    // Deactivate all beta apps now that we're no longer a patron.
                    self.deactivateBetaApps(in: context)
                }
                
                try account.managedObjectContext?.save()
            }
            catch
            {
                print("Failed to fetch Patreon account.", error)
            }
        }
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
            guard let creatorAccessToken = Keychain.shared.patreonCreatorAccessToken else { return completion(.failure(Error.invalidAccessToken)) }
            request.setValue("Bearer " + creatorAccessToken, forHTTPHeaderField: "Authorization")
            
        case .user:
            guard let accessToken = Keychain.shared.patreonAccessToken else { return completion(.failure(Error.notAuthenticated)) }
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
                    case .creator: completion(.failure(Error.invalidAccessToken))
                    case .none: completion(.failure(Error.notAuthenticated))
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
    
    func deactivateBetaApps(in context: NSManagedObjectContext)
    {
        let predicate = NSPredicate(format: "%K != %@ AND %K != nil AND %K == YES",
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID, #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))
        
        let installedApps = InstalledApp.all(satisfying: predicate, in: context)
        installedApps.forEach { $0.isActive = false }
    }
}

@available(iOS 13.0, *)
extension PatreonAPI: ASWebAuthenticationPresentationContextProviding
{
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
    {
        return UIApplication.alt_shared?.keyWindow ?? UIWindow()
    }
}
