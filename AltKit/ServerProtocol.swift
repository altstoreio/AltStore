//
//  ServerProtocol.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

public let ALTServerServiceType = "_altserver._tcp"

// Can only automatically conform ALTServerError.Code to Codable, not ALTServerError itself
extension ALTServerError.Code: Codable {}

protocol ServerMessage: Codable
{
    var version: Int { get }
    var identifier: String { get }
}

public struct PrepareAppRequest: ServerMessage
{
    public var version = 1
    public var identifier = "PrepareApp"
    
    public var udid: String
    public var contentSize: Int
    
    public init(udid: String, contentSize: Int)
    {
        self.udid = udid
        self.contentSize = contentSize
    }
}

public struct BeginInstallationRequest: ServerMessage
{
    public var version = 1
    public var identifier = "BeginInstallation"
    
    public init()
    {
    }
}

public struct ServerResponse: ServerMessage
{
    public var version = 1
    public var identifier = "ServerResponse"
    
    public var progress: Double
    
    public var error: ALTServerError? {
        get {
            guard let code = self.errorCode else { return nil }
            return ALTServerError(code)
        }
        set {
            self.errorCode = newValue?.code
        }
    }
    private var errorCode: ALTServerError.Code?
    
    public init(progress: Double, error: ALTServerError?)
    {
        self.progress = progress
        self.error = error
    }
}
