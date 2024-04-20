//
//  AltTests+Sources.swift
//  AltTests
//
//  Created by Riley Testut on 10/10/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import XCTest

@testable import AltStoreCore

extension AltTests
{
    func testSourceID() throws
    {
        let url = Source.altStoreSourceURL
        
        let sourceID = try Source.sourceID(from: url)
        XCTAssertEqual(sourceID, "apps.altstore.io")
    }
    
    @available(iOS 17, *)
    func testSourceIDWithPercentEncoding() throws
    {
        let url = URL(string: "apple.com/MY invalid•path/")!
        
        let sourceID = try Source.sourceID(from: url)
        XCTAssertEqual(sourceID, "apple.com/my invalid•path")
    }
    
    func testSourceIDWithDifferentSchemes() throws
    {
        let url1 = URL(string: "http://rileytestut.com")!
        let url2 = URL(string: "https://rileytestut.com")!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "rileytestut.com")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithNonDefaultPort() throws
    {
        let url = URL(string: "http://localhost:8008/apps.json")!
        
        let sourceID = try Source.sourceID(from: url)
        XCTAssertEqual(sourceID, "localhost:8008/apps.json")
    }
    
    func testSourceIDWithFragmentsAndQueries() throws
    {
        var components = URLComponents(string: "https://disney.com/altstore/apps")!
        components.fragment = "get started"
        
        components.queryItems = [URLQueryItem(name: "id", value: "1234")]
        let url1 = components.url!
        
        components.queryItems = [URLQueryItem(name: "id", value: "5678")]
        let url2 = components.url!
        
        XCTAssertNotEqual(url1, url2)
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "disney.com/altstore/apps")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithDuplicateSlashes() throws
    {
        let url1 = URL(string: "http://rileytestut.co.nz//secret/altstore//apps.json")!
        let url2 = URL(string: "http://rileytestut.co.nz/secret/altstore/apps.json//")!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "rileytestut.co.nz/secret/altstore/apps.json")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithMixedCase() throws
    {
        let href = "https://rileyTESTUT.co.nz/test/PATH/ApPs.json"
        
        let url1 = URL(string: href)!
        let url2 = URL(string: href.lowercased())!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "rileytestut.co.nz/test/path/apps.json")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithTrailingSlash() throws
    {
        let url1 = URL(string: "http://apps.altstore.io/")!
        let url2 = URL(string: "http://apps.altstore.io")!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "apps.altstore.io")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithLeadingWWW() throws
    {
        let url1 = URL(string: "http://www.GBA4iOSApp.com")!
        let url2 = URL(string: "http://gba4iosapp.com")!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "gba4iosapp.com")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithAllRules() throws
    {
        let url1 = URL(string: "fTp://WWW.apps.APPLE.com:4004//altstore apps/source.JSON?user=test@altstore.io#welcome//")!
        let url2 = URL(string: "ftp://apps.apple.com:4004/altstore apps/source.json?user=anothertest@altstore.io#welcome")!
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "apps.apple.com:4004/altstore apps/source.json")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
    
    func testSourceIDWithEmoji() throws
    {
        let url1 = URL(string: "http://xn--g5h5981o.com")! // 🤷‍♂️.com
        let sourceID1 = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID1, "🤷♂.com")
        
        let url2 = URL(string: "http://www.xn--7r8h.io")! // www.💜.io
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID2, "💜.io")
    }
    
    func testSourceIDWithRelativeURL() throws
    {
        let baseURL = URL(string: "https://rileytestut.com")!
        let path = "altstore/apps.json"
        
        let url1 = URL(string: path, relativeTo: baseURL)!
        let url2 = baseURL.appendingPathComponent(path)
        
        let sourceID = try Source.sourceID(from: url1)
        XCTAssertEqual(sourceID, "rileytestut.com/altstore/apps.json")
        
        let sourceID2 = try Source.sourceID(from: url2)
        XCTAssertEqual(sourceID, sourceID2)
    }
}
