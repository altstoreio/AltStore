//
//  ServerProtocol.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

public let ALTServerServiceType = "_altserver._tcp"

protocol ServerMessageProtocol: Codable
{
    var version: Int { get }
    var identifier: String { get }
}

public enum ServerRequest: Decodable
{
    case anisetteData(AnisetteDataRequest)
    case prepareApp(PrepareAppRequest)
    case beginInstallation(BeginInstallationRequest)
    case installProvisioningProfiles(InstallProvisioningProfilesRequest)
    case removeProvisioningProfiles(RemoveProvisioningProfilesRequest)
    case removeApp(RemoveAppRequest)
    case unknown(identifier: String, version: Int)
    
    var identifier: String {
        switch self
        {
        case .anisetteData(let request): return request.identifier
        case .prepareApp(let request): return request.identifier
        case .beginInstallation(let request): return request.identifier
        case .installProvisioningProfiles(let request): return request.identifier
        case .removeProvisioningProfiles(let request): return request.identifier
        case .removeApp(let request): return request.identifier
        case .unknown(let identifier, _): return identifier
        }
    }
    
    var version: Int {
        switch self
        {
        case .anisetteData(let request): return request.version
        case .prepareApp(let request): return request.version
        case .beginInstallation(let request): return request.version
        case .installProvisioningProfiles(let request): return request.version
        case .removeProvisioningProfiles(let request): return request.version
        case .removeApp(let request): return request.version
        case .unknown(_, let version): return version
        }
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let version = try container.decode(Int.self, forKey: .version)
        
        let identifier = try container.decode(String.self, forKey: .identifier)
        switch identifier
        {
        case "AnisetteDataRequest":
            let request = try AnisetteDataRequest(from: decoder)
            self = .anisetteData(request)
            
        case "PrepareAppRequest":
            let request = try PrepareAppRequest(from: decoder)
            self = .prepareApp(request)
            
        case "BeginInstallationRequest":
            let request = try BeginInstallationRequest(from: decoder)
            self = .beginInstallation(request)
          
        case "InstallProvisioningProfilesRequest":
            let request = try InstallProvisioningProfilesRequest(from: decoder)
            self = .installProvisioningProfiles(request)
            
        case "RemoveProvisioningProfilesRequest":
            let request = try RemoveProvisioningProfilesRequest(from: decoder)
            self = .removeProvisioningProfiles(request)
            
        case "RemoveAppRequest":
            let request = try RemoveAppRequest(from: decoder)
            self = .removeApp(request)
            
        default:
            self = .unknown(identifier: identifier, version: version)
        }
    }
}

public enum ServerResponse: Decodable
{
    case anisetteData(AnisetteDataResponse)
    case installationProgress(InstallationProgressResponse)
    case installProvisioningProfiles(InstallProvisioningProfilesResponse)
    case removeProvisioningProfiles(RemoveProvisioningProfilesResponse)
    case removeApp(RemoveAppResponse)
    case error(ErrorResponse)
    case unknown(identifier: String, version: Int)
    
    var identifier: String {
        switch self
        {
        case .anisetteData(let response): return response.identifier
        case .installationProgress(let response): return response.identifier
        case .installProvisioningProfiles(let response): return response.identifier
        case .removeProvisioningProfiles(let response): return response.identifier
        case .removeApp(let response): return response.identifier
        case .error(let response): return response.identifier
        case .unknown(let identifier, _): return identifier
        }
    }
    
    var version: Int {
        switch self
        {
        case .anisetteData(let response): return response.version
        case .installationProgress(let response): return response.version
        case .installProvisioningProfiles(let response): return response.version
        case .removeProvisioningProfiles(let response): return response.version
        case .removeApp(let response): return response.version
        case .error(let response): return response.version
        case .unknown(_, let version): return version
        }
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let version = try container.decode(Int.self, forKey: .version)
        
        let identifier = try container.decode(String.self, forKey: .identifier)
        switch identifier
        {
        case "AnisetteDataResponse":
            let response = try AnisetteDataResponse(from: decoder)
            self = .anisetteData(response)
            
        case "InstallationProgressResponse":
            let response = try InstallationProgressResponse(from: decoder)
            self = .installationProgress(response)
           
        case "InstallProvisioningProfilesResponse":
            let response = try InstallProvisioningProfilesResponse(from: decoder)
            self = .installProvisioningProfiles(response)
            
        case "RemoveProvisioningProfilesResponse":
            let response = try RemoveProvisioningProfilesResponse(from: decoder)
            self = .removeProvisioningProfiles(response)
            
        case "RemoveAppResponse":
            let response = try RemoveAppResponse(from: decoder)
            self = .removeApp(response)
            
        case "ErrorResponse":
            let response = try ErrorResponse(from: decoder)
            self = .error(response)
            
        default:
            self = .unknown(identifier: identifier, version: version)
        }
    }
}

// _Don't_ provide generic SuccessResponse, as that would prevent us
// from easily changing response format for a request in the future.
public struct ErrorResponse: ServerMessageProtocol
{
    public var version = 2
    public var identifier = "ErrorResponse"
    
    public var error: ALTServerError {
        return self.serverError?.error ?? ALTServerError(self.errorCode)
    }
    private var serverError: CodableServerError?
    
    // Legacy (v1)
    private var errorCode: ALTServerError.Code
    
    public init(error: ALTServerError)
    {
        self.serverError = CodableServerError(error: error)
        self.errorCode = error.code
    }
}

public struct AnisetteDataRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "AnisetteDataRequest"
    
    public init()
    {
    }
}

public struct AnisetteDataResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "AnisetteDataResponse"
    
    public var anisetteData: ALTAnisetteData
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
        case anisetteData
    }

    public init(anisetteData: ALTAnisetteData)
    {
        self.anisetteData = anisetteData
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        
        let json = try container.decode([String: String].self, forKey: .anisetteData)
        
        if let anisetteData = ALTAnisetteData(json: json)
        {
            self.anisetteData = anisetteData
        }
        else
        {
            throw DecodingError.dataCorruptedError(forKey: CodingKeys.anisetteData, in: container, debugDescription: "Couuld not parse anisette data from JSON")
        }
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.identifier, forKey: .identifier)
        
        let json = self.anisetteData.json()
        try container.encode(json, forKey: .anisetteData)
    }
}

public struct PrepareAppRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "PrepareAppRequest"
    
    public var udid: String
    public var contentSize: Int
    
    public var fileURL: URL?
    
    public init(udid: String, contentSize: Int, fileURL: URL? = nil)
    {
        self.udid = udid
        self.contentSize = contentSize
        self.fileURL = fileURL
    }
}

public struct BeginInstallationRequest: ServerMessageProtocol
{
    public var version = 3
    public var identifier = "BeginInstallationRequest"
    
    // If activeProfiles is non-nil, then AltServer should remove all profiles except active ones.
    public var activeProfiles: Set<String>?
    
    public var bundleIdentifier: String?
    
    public init(activeProfiles: Set<String>?, bundleIdentifier: String?)
    {
        self.activeProfiles = activeProfiles
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct InstallationProgressResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "InstallationProgressResponse"
    
    public var progress: Double
    
    public init(progress: Double)
    {
        self.progress = progress
    }
}

public struct InstallProvisioningProfilesRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "InstallProvisioningProfilesRequest"
    
    public var udid: String
    public var provisioningProfiles: Set<ALTProvisioningProfile>
    
    // If activeProfiles is non-nil, then AltServer should remove all profiles except active ones.
    public var activeProfiles: Set<String>?
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
        case udid
        case provisioningProfiles
        case activeProfiles
    }
    
    public init(udid: String, provisioningProfiles: Set<ALTProvisioningProfile>, activeProfiles: Set<String>?)
    {
        self.udid = udid
        self.provisioningProfiles = provisioningProfiles
        self.activeProfiles = activeProfiles
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.udid = try container.decode(String.self, forKey: .udid)
        
        let rawProvisioningProfiles = try container.decode([Data].self, forKey: .provisioningProfiles)
        let provisioningProfiles = try rawProvisioningProfiles.map { (data) -> ALTProvisioningProfile in
            guard let profile = ALTProvisioningProfile(data: data) else {
                throw DecodingError.dataCorruptedError(forKey: CodingKeys.provisioningProfiles, in: container, debugDescription: "Could not parse provisioning profile from data.")
            }
            return profile
        }
        
        self.provisioningProfiles = Set(provisioningProfiles)
        self.activeProfiles = try container.decodeIfPresent(Set<String>.self, forKey: .activeProfiles)
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.identifier, forKey: .identifier)
        try container.encode(self.udid, forKey: .udid)
        
        try container.encode(self.provisioningProfiles.map { $0.data }, forKey: .provisioningProfiles)
        try container.encodeIfPresent(self.activeProfiles, forKey: .activeProfiles)
    }
}

public struct InstallProvisioningProfilesResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "InstallProvisioningProfilesResponse"
    
    public init()
    {
    }
}

public struct RemoveProvisioningProfilesRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "RemoveProvisioningProfilesRequest"
    
    public var udid: String
    public var bundleIdentifiers: Set<String>

    public init(udid: String, bundleIdentifiers: Set<String>)
    {
        self.udid = udid
        self.bundleIdentifiers = bundleIdentifiers
    }
}

public struct RemoveProvisioningProfilesResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "RemoveProvisioningProfilesResponse"
    
    public init()
    {
    }
}

public struct RemoveAppRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "RemoveAppRequest"
    
    public var udid: String
    public var bundleIdentifier: String

    public init(udid: String, bundleIdentifier: String)
    {
        self.udid = udid
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct RemoveAppResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "RemoveAppResponse"
    
    public init()
    {
    }
}
