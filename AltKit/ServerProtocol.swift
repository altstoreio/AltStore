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

// Can only automatically conform ALTServerError.Code to Codable, not ALTServerError itself
extension ALTServerError.Code: Codable {}

private struct CodableServerError: Codable
{
    var error: ALTServerError
    
    private enum CodingKeys: String, CodingKey
    {
        case errorCode
        case localizedDescription
    }

    init(error: ALTServerError)
    {
        self.error = error
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
        let userInfo = [NSLocalizedDescriptionKey: localizedDescription].compactMapValues { $0 }
        
        let errorCode = try container.decode(Int.self, forKey: .errorCode)
        if let errorCode = ALTServerError.Code(rawValue: errorCode)
        {
            self.error = ALTServerError(errorCode, userInfo: userInfo)
        }
        else
        {
            self.error = ALTServerError(.unknown, userInfo: userInfo)
        }
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.error.code.rawValue, forKey: .errorCode)
        
        let localizedDescription = (self.error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
        try container.encodeIfPresent(localizedDescription, forKey: .localizedDescription)
    }
}

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
    case replaceProvisioningProfiles(ReplaceProvisioningProfilesRequest)
    case unknown(identifier: String, version: Int)
    
    var identifier: String {
        switch self
        {
        case .anisetteData(let request): return request.identifier
        case .prepareApp(let request): return request.identifier
        case .beginInstallation(let request): return request.identifier
        case .replaceProvisioningProfiles(let request): return request.identifier
        case .unknown(let identifier, _): return identifier
        }
    }
    
    var version: Int {
        switch self
        {
        case .anisetteData(let request): return request.version
        case .prepareApp(let request): return request.version
        case .beginInstallation(let request): return request.version
        case .replaceProvisioningProfiles(let request): return request.version
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
            
        case "ReplaceProvisioningProfilesRequest":
            let request = try ReplaceProvisioningProfilesRequest(from: decoder)
            self = .replaceProvisioningProfiles(request)
            
        default:
            self = .unknown(identifier: identifier, version: version)
        }
    }
}

public enum ServerResponse: Decodable
{
    case anisetteData(AnisetteDataResponse)
    case installationProgress(InstallationProgressResponse)
    case replaceProvisioningProfiles(ReplaceProvisioningProfilesResponse)
    case error(ErrorResponse)
    case unknown(identifier: String, version: Int)
    
    var identifier: String {
        switch self
        {
        case .anisetteData(let response): return response.identifier
        case .installationProgress(let response): return response.identifier
        case .replaceProvisioningProfiles(let response): return response.identifier
        case .error(let response): return response.identifier
        case .unknown(let identifier, _): return identifier
        }
    }
    
    var version: Int {
        switch self
        {
        case .anisetteData(let response): return response.version
        case .installationProgress(let response): return response.version
        case .replaceProvisioningProfiles(let response): return response.version
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
            
        case "ReplaceProvisioningProfilesResponse":
            let response = try ReplaceProvisioningProfilesResponse(from: decoder)
            self = .replaceProvisioningProfiles(response)
            
        case "ErrorResponse":
            let response = try ErrorResponse(from: decoder)
            self = .error(response)
            
        default:
            self = .unknown(identifier: identifier, version: version)
        }
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
    
    public init(udid: String, contentSize: Int)
    {
        self.udid = udid
        self.contentSize = contentSize
    }
}

public struct BeginInstallationRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "BeginInstallationRequest"
    
    public init()
    {
    }
}

public struct ReplaceProvisioningProfilesRequest: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "ReplaceProvisioningProfilesRequest"
    
    public var udid: String
    public var provisioningProfiles: Set<ALTProvisioningProfile>
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
        case udid
        case provisioningProfiles
    }
    
    public init(udid: String, provisioningProfiles: Set<ALTProvisioningProfile>)
    {
        self.udid = udid
        self.provisioningProfiles = provisioningProfiles
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.udid = try container.decode(String.self, forKey: .udid)
        
        let rawProvisioningProfiles = try container.decode([Data].self, forKey: .provisioningProfiles)
        let provisioningProfiles = rawProvisioningProfiles.compactMap { ALTProvisioningProfile(data: $0) }
        self.provisioningProfiles = Set(provisioningProfiles)
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.identifier, forKey: .identifier)
        try container.encode(self.udid, forKey: .udid)
        
        let rawProvisioningProfiles = self.provisioningProfiles.map { $0.data }
        try container.encode(rawProvisioningProfiles, forKey: .provisioningProfiles)
    }
}

public struct ReplaceProvisioningProfilesResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "ReplaceProvisioningProfilesResponse"
    
    public var errors: [ALTProvisioningProfile: ALTServerError]
        
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case version
        case errors
    }
    
    public init(errors: [ALTProvisioningProfile: ALTServerError])
    {
        self.errors = errors
    }
    
    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        
        let rawErrors = try container.decode([Data: CodableServerError].self, forKey: .errors)
        let errors = Dictionary(rawErrors.compactMap { (data, error) in ALTProvisioningProfile(data: data).map { ($0, error.error) } },
                                uniquingKeysWith: { (a, b) in a })
        self.errors = errors
    }
    
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.identifier, forKey: .identifier)
        
        let rawErrors = Dictionary(self.errors.compactMap { ($0.data, CodableServerError(error: $1)) }, uniquingKeysWith: { (a, b) in a })
        try container.encode(rawErrors, forKey: .errors)
    }
}

public struct ErrorResponse: ServerMessageProtocol
{
    public var version = 1
    public var identifier = "ErrorResponse"
    
    public var error: ALTServerError {
        return ALTServerError(self.errorCode)
    }
    private var errorCode: ALTServerError.Code
    
    public init(error: ALTServerError)
    {
        self.errorCode = error.code
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
