//
//  AltTests.swift
//  AltTests
//
//  Created by Riley Testut on 10/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import XCTest
@testable import AltStore
@testable import AltStoreCore

import AltSign

extension String
{
    static let testLocalizedTitle = "AltTest Failed"
    static let testLocalizedFailure = "The AltTest failed to pass."
    
    static let testOriginalLocalizedFailure = "The AltServer operation could not be completed."
    
    static let testUnrecognizedFailureReason = "The alien invasion has begun."
    static let testUnrecognizedRecoverySuggestion = "Find your loved ones and pray the aliens are merciful."
    
    static let testDebugDescription = "The very specific operation could not be completed because a detailed error occured. Code=101."
}

extension URL
{
    static let testFileURL = URL(filePath: "~/Desktop/TestApp.ipa")
}

final class AltTests: XCTestCase
{
    override func setUpWithError() throws
    {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws
    {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
}

// Local Errors
extension AltTests
{
    func testToNSErrorBridging() async throws
    {
        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError)
            
            XCTAssertEqual(nsError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(nsError.localizedFailure, error.errorFailure)
            XCTAssertEqual(nsError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
            }
        }
    }
    
    func testToNSErrorAndBackBridging() async throws
    {
        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError)
            let unbridgedError = try XCTUnwrap(nsError as? any ALTLocalizedError)
            
            XCTAssertEqual(unbridgedError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(unbridgedError.errorFailure, error.errorFailure)
            XCTAssertEqual(unbridgedError.failureReason, error.errorFailureReason)
            XCTAssertEqual(unbridgedError.recoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(unbridgedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testDefaultErrorDomain()
    {
        for error in VerificationError.testErrors
        {
            let expectedErrorDomain = "AltStore.VerificationError"
            XCTAssertEqual(error._domain, expectedErrorDomain)
            
            let nsError = (error as NSError)
            XCTAssertEqual(nsError.domain, expectedErrorDomain)
        }
    }
    
    func testCustomErrorDomain() async throws
    {
        for error in allTestErrors
        {
            XCTAssertEqual(error._domain, TestError.errorDomain)
            
            let nsError = (error as NSError)
            XCTAssertEqual(nsError.domain, TestError.errorDomain)
        }
    }
    
    func testLocalizedDescriptionProvider() async throws
    {
        for error in AltTests.allRealErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            let expectedFailureReason = try XCTUnwrap((error as NSError).localizedFailureReason)
            
            if let localizedFailure = (error as NSError).localizedFailure
            {
                // Test localizedDescription == original localizedFailure + localizedFailureReason
                let expectedLocalizedDescription = localizedFailure + " " + expectedFailureReason
                XCTAssertEqual(error.localizedDescription, expectedLocalizedDescription)
            }
            else
            {
                // Test localizedDescription == localizedFailureReason
                XCTAssertEqual(error.localizedDescription, expectedFailureReason)
            }
            
            let expectedLocalizedDescription = String.testLocalizedFailure + " " + expectedFailureReason
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
        }
    }
    
    func testWithLocalizedFailure() async throws
    {
        for error in AltTests.allRealErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            let expectedFailureReason = try XCTUnwrap((error as NSError).localizedFailureReason)

            let expectedLocalizedDescription = String.testLocalizedFailure + " " + expectedFailureReason
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
            
            XCTAssertEqual(nsError.localizedFailure, .testLocalizedFailure)
            
            // Test remainder
            XCTAssertEqual(nsError.localizedFailureReason, expectedFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: error._domain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func ALTAssertErrorsEqual(_ error1: Error, _ error2: Error, overriding overideValues: [String: Any])
    {
        XCTAssertEqual(error1._domain, error2._domain)
        XCTAssertEqual(error1._code, error2._code)
        XCTAssertEqual(error1.localizedDescription, error2.localizedDescription)
        
        let nsError1 = error1 as NSError
        let nsError2 = error2 as NSError
        XCTAssertEqual(nsError1.localizedFailure, nsError2.localizedFailure)
        XCTAssertEqual(nsError1.localizedFailureReason, nsError2.localizedFailureReason)
        XCTAssertEqual(nsError1.localizedRecoverySuggestion, nsError2.localizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: error2._domain),
           let debugDescription = provider(error2, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(error1, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
        
    func testWithInitialLocalizedFailure() async throws
    {
        for error in OperationError.testErrors
        {
            var localizedError = OperationError(error, localizedFailure: .testLocalizedFailure)
            localizedError.sourceFile = error.sourceFile
            localizedError.sourceLine = error.sourceLine
            
            let nsError = localizedError as NSError
            
            let expectedLocalizedDescription = String.testLocalizedFailure + " " + error.errorFailureReason
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
            
            XCTAssertEqual(localizedError.errorFailure, .testLocalizedFailure)
            XCTAssertEqual(nsError.localizedFailure, .testLocalizedFailure)
            
            // Test remainder
            XCTAssertEqual(nsError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func testWithInitialLocalizedTitle() async throws
    {
        for error in OperationError.testErrors
        {
            var localizedError = OperationError(error, localizedTitle: .testLocalizedTitle)
            localizedError.sourceFile = error.sourceFile
            localizedError.sourceLine = error.sourceLine
            
            let nsError = localizedError as NSError
            
            XCTAssertEqual(nsError.localizedDescription, error.localizedDescription)
            
            XCTAssertEqual(localizedError.errorTitle, .testLocalizedTitle)
            XCTAssertEqual(nsError.localizedTitle, .testLocalizedTitle)
            
            // Test remainder
            XCTAssertEqual(nsError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func unbridge<T: ALTErrorCode>(_ error: NSError, to errorType: T) throws -> Error
    {
        let unbridgedError = try XCTUnwrap(error as? T.Error)
        return unbridgedError
    }

    func testWithLocalizedFailureAndBack() async throws
    {
        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            func test(_ unbridgedError: Error, against nsError: NSError)
            {
                let unbridgedNSError = (unbridgedError as NSError)
                
                let expectedLocalizedDescription = String.testLocalizedFailure + " " + error.errorFailureReason
                XCTAssertEqual(unbridgedError.localizedDescription, expectedLocalizedDescription)
                
                XCTAssertEqual(unbridgedNSError.localizedFailure, .testLocalizedFailure)
                
                
                // Test remainder
                XCTAssertEqual(nsError.localizedFailureReason, error.errorFailureReason)
                XCTAssertEqual(nsError.localizedRecoverySuggestion, error.recoverySuggestion)
                
                if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
                   let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
                {
                    XCTAssertEqual(debugDescription, nsError.debugDescription)
                }
            }
            
            do
            {
                throw nsError as NSError
            }
            catch let error as VerificationError
            {
                test(error, against: nsError)
            }
            catch let error as OperationError
            {
                test(error, against: nsError)
            }
            catch let error as ALTLocalizedError
            {
                // Make sure VerificationError and OperationError were caught by above handlers.
                XCTAssertNotEqual(error._domain, VerificationError.errorDomain)
                XCTAssertNotEqual(error._domain, OperationError.errorDomain)
                
                let unbridgedError = try self.unbridge(error as NSError, to: error.code)
                test(unbridgedError, against: nsError)
            }
        }
    }
    
    func testWithLocalizedTitle() async throws
    {
        let localizedTitle = "AltTest Failed"

        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(localizedTitle)
            
            XCTAssertEqual(nsError.localizedTitle, localizedTitle)
            
            
            // Test remainder
            XCTAssertEqual(nsError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(nsError.localizedFailure, error.errorFailure)
            XCTAssertEqual(nsError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func testWithLocalizedTitleAndBack() async throws
    {
        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            let unbridgedError = try self.unbridge(nsError, to: error.code)
            let unbridgedNSError = (unbridgedError as NSError)
            
            XCTAssertEqual(unbridgedNSError.localizedTitle, .testLocalizedTitle)
            
            XCTAssertEqual(unbridgedNSError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(unbridgedNSError.localizedFailure, error.errorFailure)
            XCTAssertEqual(unbridgedNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(unbridgedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, unbridgedNSError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func testWithLocalizedTitleAndFailure() async throws
    {
        for error in AltTests.allRealErrors
        {
            var nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
            nsError = nsError.withLocalizedFailure(.testLocalizedFailure)
            
            XCTAssertEqual(nsError.localizedTitle, .testLocalizedTitle)
            XCTAssertEqual(nsError.localizedFailure, .testLocalizedFailure)
            
            // Test remainder
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap((error as NSError).localizedFailureReason)
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
            
            XCTAssertEqual(nsError.localizedFailure, .testLocalizedFailure)
            XCTAssertEqual(nsError.localizedFailureReason, (error as NSError).localizedFailureReason)
            XCTAssertEqual(nsError.localizedRecoverySuggestion, (error as NSError).localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                XCTAssertEqual(debugDescription, nsError.debugDescription)
                XCTAssertNotNil(nil)
            }
        }
    }
    
    func testReceivingAltServerError() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = error as NSError
            
            let codableError = CodableError(error: error)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            XCTAssertEqual(receivedError._domain, error._domain)
            XCTAssertEqual(receivedError._code, error.code.rawValue)
            XCTAssertEqual(receivedError.localizedDescription, error.localizedDescription)
            
            XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)

            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailure() async throws
    {
        let localizedFailure = "The AltTest failed to pass."
        
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(localizedFailure)
            let altserverError = ALTServerError(nsError)
            
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            // Test domain and code match.
            XCTAssertEqual(receivedError._domain, error._domain)
            XCTAssertEqual(receivedError._code, error.code.rawValue)
            
            // Test localizedDescription contains localizedFailure.
            let expectedLocalizedDescription: String
            if let localizedFailureReason = nsError.localizedFailureReason
            {
                expectedLocalizedDescription = localizedFailure + " " + localizedFailureReason
            }
            else
            {
                expectedLocalizedDescription = localizedFailure + " " + error.localizedDescription
            }
            XCTAssertEqual(receivedError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, localizedFailure)
            
            // Test remaining properties match.
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)

            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedTitle() async throws
    {
        let localizedTitle = "AltTest Failed"
        
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(localizedTitle)
            let altserverError = ALTServerError(nsError)
            
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            // Test domain and code match.
            XCTAssertEqual(receivedError._domain, error._domain)
            XCTAssertEqual(receivedError._code, error.code.rawValue)
            XCTAssertEqual(receivedError.localizedDescription, error.localizedDescription)
            
            XCTAssertEqual(receivedNSError.localizedTitle, localizedTitle)
            
            XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingAltServerErrorThenAddingLocalizedFailure() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = error as NSError
            
            let codableError = CodableError(error: error)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            // Test domain and code match.
            XCTAssertEqual(receivedNSError.domain, error._domain)
            XCTAssertEqual(receivedNSError.code, error.code.rawValue)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingAltServerErrorThenAddingLocalizedTitle() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = error as NSError
            
            let codableError = CodableError(error: error)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            XCTAssertEqual(receivedNSError.domain, error._domain)
            XCTAssertEqual(receivedNSError.code, error.code.rawValue)
            XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
            
            XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
            
            XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
            
            let codableError = CodableError(error: nsError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            // Test domain and code match.
            XCTAssertEqual(receivedNSError.domain, error._domain)
            XCTAssertEqual(receivedNSError.code, error.code.rawValue)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            // Test that decoded error retains original localized failure.
            XCTAssertEqual((receivedError as NSError).localizedFailure, .testOriginalLocalizedFailure)
            
            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
//
//    func testReceivingAltServerErrorWithLocalizedFailureThenAddingLocalizedTitle() async throws
//    {
//        for error in ALTServerError.testErrors
//        {
//            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
//
//            let codableError = CodableError(error: nsError)
//            let jsonData = try JSONEncoder().encode(codableError)
//
//            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
//            let receivedError = decodedError.error
//            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
//
//            // Test domain and code match.
//            XCTAssertEqual(receivedNSError.domain, error._domain)
//            XCTAssertEqual(receivedNSError.code, error.code.rawValue)
//
//            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
//            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
//            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
//
//            // Test that decoded error retains original localized failure.
//            XCTAssertEqual((receivedError as NSError).localizedFailure, .testOriginalLocalizedFailure)
//
//            XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
//            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
//
//            if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
//               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
//            {
//                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
//                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
//            }
//        }
//    }
    
    func testReceivingNonAltServerSwiftError() async throws
    {
        for error in allTestErrors
        {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
            
            let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
            XCTAssertEqual(receivedUnderlyingError._domain, TestError.errorDomain)
            XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
            
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
            
            let receivedUnderlyingNSError = receivedUnderlyingError as NSError
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, error.errorFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, error.errorFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: TestError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingNonAltServerSwiftErrorWithLocalizedFailure() async throws
    {
        for error in allTestErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            let altserverError = ALTServerError(nsError)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedNSError = decodedError.error as NSError // Always NSError if decoded
            
            // Test receivedError == ALTServerError.underlyingError
            XCTAssertEqual(receivedNSError.domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedNSError.code, ALTServerError.underlyingError.rawValue)
            
            // Test receivedUnderlyingError has correct domain + code
            let receivedUnderlyingNSError = try XCTUnwrap(receivedNSError.underlyingError) as NSError // Always NSError if decoded
            XCTAssertEqual(receivedUnderlyingNSError.domain, type(of: error).errorDomain)
            XCTAssertEqual(receivedUnderlyingNSError.code, error.code.rawValue)
            
            // Test localizedDescription contains .testLocalizedFailure
            let expectedLocalizedDescription = String.testLocalizedFailure + " " + error.localizedDescription
            XCTAssertEqual(receivedUnderlyingNSError.localizedDescription, expectedLocalizedDescription)
            
            // Test remaining receivedUnderlyingNSError values match
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, .testLocalizedFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                //TODO: Shouldn't we just be comparing receivedNSError.debugDescription? Let's see
                XCTAssertEqual(debugDescription, receivedNSError.debugDescription)
            }
        }
    }
    
    func testReceivingNonAltServerSwiftErrorThenAddingLocalizedFailure() async throws
    {
        for error in allTestErrors
        {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
            
            let expectedLocalizedDescription = String.testLocalizedFailure + " " + error.localizedDescription
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            
            let receivedUnderlyingError = try XCTUnwrap(receivedNSError.underlyingError)
            XCTAssertEqual(receivedUnderlyingError._domain, TestError.errorDomain)
            XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
            
            let receivedUnderlyingNSError = receivedUnderlyingError as NSError
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, error.errorFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: TestError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingNonAltServerSwiftErrorThenAddingLocalizedTitle() async throws
    {
        for error in allTestErrors
        {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
            
            XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
            XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
            
            let receivedUnderlyingError = try XCTUnwrap(receivedNSError.underlyingError)
            XCTAssertEqual(receivedUnderlyingError._domain, TestError.errorDomain)
            XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
            
            let receivedUnderlyingNSError = receivedUnderlyingError as NSError
            XCTAssertNil(receivedUnderlyingNSError.localizedTitle)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, error.errorFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.errorFailureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: TestError.errorDomain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingUnrecognizedNonAltServerSwiftError() async throws
    {
        enum MyError: Int, LocalizedError, CaseIterable
        {
            case strange
            case nothing
            
            var errorDescription: String? {
                switch self
                {
                case .strange: return "A strange error occured."
                case .nothing: return nil
                }
            }
            
            var recoverySuggestion: String? {
                return "Have you tried turning it off and on again?"
            }
        }
        
        for error in MyError.allCases
        {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try self.mockUserInfoValueProvider(for: error, failureReason: nil, recoverySuggestion: nil) {
                try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            }
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
            
            XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
            XCTAssertNil(receivedNSError.localizedFailure)
            
            let receivedUnderlyingError = try XCTUnwrap(receivedNSError.underlyingError)
            XCTAssertEqual(receivedUnderlyingError._domain, error._domain)
            XCTAssertEqual(receivedUnderlyingError._code, error.rawValue)
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
                        
            let receivedUnderlyingNSError = receivedUnderlyingError as NSError
            XCTAssertNil(receivedUnderlyingNSError.localizedFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.failureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.failureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: error._domain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingUnrecognizedNonAltServerSwiftErrorThenAddingLocalizedFailure() async throws
    {
        enum MyError: Int, LocalizedError, CaseIterable
        {
            case strange
            case nothing
            
            var errorDescription: String? {
                switch self
                {
                case .strange: return "A strange error occured."
                case .nothing: return nil
                }
            }
            
            var recoverySuggestion: String? {
                return "Have you tried turning it off and on again?"
            }
        }
        
        for error in MyError.allCases
        {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try self.mockUserInfoValueProvider(for: error, failureReason: nil, recoverySuggestion: nil) {
                try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            }
            let receivedError = decodedError.error
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
            
            let expectedLocalizedDescription = String.testLocalizedFailure + " " + error.localizedDescription
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            // Make sure we didn't lose the error message due to adding localized failure.
            XCTAssertNotEqual(receivedNSError.localizedDescription, .testLocalizedFailure)
            
            let receivedUnderlyingError = try XCTUnwrap(receivedNSError.underlyingError)
            XCTAssertEqual(receivedUnderlyingError._domain, error._domain)
            XCTAssertEqual(receivedUnderlyingError._code, error.rawValue)
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
            
            let receivedUnderlyingNSError = receivedUnderlyingError as NSError
            XCTAssertNil(receivedUnderlyingNSError.localizedFailure)
            XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, error.failureReason)
            XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            // Test ALTServerError forwards all properties to receivedUnderlyingError
            XCTAssertEqual(receivedNSError.localizedFailureReason, error.failureReason)
            XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, error.recoverySuggestion)
            
            if let provider = NSError.userInfoValueProvider(forDomain: error._domain),
               let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
            {
                let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
                XCTAssertEqual(debugDescription, unbridgedDebugDescription)
            }
        }
    }
    
    func testReceivingNonAltServerCocoaError() async throws
    {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "~/Desktop/TestFile"])
        let nsError = error as NSError
        
        let altserverError = ALTServerError(error)
        let codableError = CodableError(error: altserverError)
        let jsonData = try JSONEncoder().encode(codableError)
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, CocoaError.errorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        
        if let provider = NSError.userInfoValueProvider(forDomain: TestError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingNonAltServerCocoaErrorWithLocalizedFailure() async throws
    {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "~/Desktop/TestFile"])
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let altserverError = ALTServerError(nsError)
        let codableError = CodableError(error: altserverError)
        let jsonData = try JSONEncoder().encode(codableError)
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, CocoaError.errorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        
        let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, expectedLocalizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, .testLocalizedFailure)
        
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        
        if let provider = NSError.userInfoValueProvider(forDomain: TestError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingAltServerConnectionError() async throws
    {
        let error = ALTServerConnectionError(.deviceLocked, userInfo: [ALTDeviceNameErrorKey: "Riley's iPhone"])
        let nsError = error as NSError
        
        let altserverError = ALTServerError(error)
        let codableError = CodableError(error: altserverError)
        let jsonData = try JSONEncoder().encode(codableError)
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.connectionFailed.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, type(of: error).errorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        
        let connectionFailedNSError = ALTServerError(.connectionFailed) as NSError
        let expectedLocalizedDescription = try XCTUnwrap(connectionFailedNSError.localizedFailureReason) + " " + error.localizedDescription
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        
        let expectedLocalizedFailure = connectionFailedNSError.localizedFailureReason
        XCTAssertEqual(receivedNSError.localizedFailure, expectedLocalizedFailure)
        
        XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingAppleAPIError() async throws
    {
        let error = ALTAppleAPIError(.incorrectCredentials)
        let nsError = error as NSError
        
        // Mock user info provider for entire test.
        let jsonData = try self.mockUserInfoValueProvider(for: error, failureReason: nsError.localizedFailureReason, recoverySuggestion: nsError.localizedRecoverySuggestion, debugDescription: .testDebugDescription) {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, type(of: error).errorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        XCTAssertEqual(receivedUnderlyingNSError.localizedDebugDescription, .testDebugDescription)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        XCTAssertEqual(receivedNSError.localizedDescription, nsError.localizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
        XCTAssertEqual(receivedNSError.localizedDebugDescription, .testDebugDescription)
    }
    
//    func testReceivingCodableError() async throws
//    {
//        let json = "{'name2': 'riley'}"
//        
//        struct Test: Decodable
//        {
//            var name: String
//        }
//        
//        let rawData = json.data(using: .utf8)!
//        let error: DecodingError
//        
//        do
//        {
//            _ = try Foundation.JSONDecoder().decode(Test.self, from: rawData)
//            return
//        }
//        catch let decodingError as DecodingError
//        {
//            error = decodingError
//        }
//        catch
//        {
//            XCTFail("Only DecodingErrors should be thrown.")
//            return
//        }
//        
//        let nsError = error as NSError
//        
//        let altserverError = ALTServerError(error)
//        let codableError = CodableError(error: altserverError)
//        let jsonData = try JSONEncoder().encode(codableError)
//        
//        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
//        let receivedError = decodedError.error
//        let receivedNSError = receivedError as NSError
//        
//        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
//        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
//        
//        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
//        XCTAssertEqual(receivedUnderlyingError._domain, error._domain)
//        XCTAssertEqual(receivedUnderlyingError._code, error._code)
//        XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.localizedDescription)
//        
//        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
//        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, nsError.localizedFailure)
//        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, nsError.localizedFailureReason)
//        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
//        
//        let expectedDebugDescription = try XCTUnwrap(nsError.localizedDebugDescription)
//        XCTAssertEqual(receivedUnderlyingNSError.localizedDebugDescription, expectedDebugDescription)
//        
//        // Test ALTServerError forwards all properties to receivedUnderlyingError
//        XCTAssertEqual(receivedNSError.localizedDescription, error.localizedDescription)
//        XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
//        XCTAssertEqual(receivedNSError.localizedFailureReason, nsError.localizedFailureReason)
//        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
//        XCTAssertEqual(receivedNSError.localizedDebugDescription, expectedDebugDescription)
//    }
    
    func testReceivingUnrecognizedAppleAPIError() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = error as NSError
        
        let (jsonData, expectedLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion) = try self.mockUserInfoValueProvider(for: error) {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let expectedLocalizedDescription = error.localizedDescription
            let expectedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
            let expectedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
            
            return (jsonData, expectedLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, ALTAppleAPIErrorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, expectedLocalizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertNil(receivedUnderlyingNSError.localizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        XCTAssertNil(receivedNSError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAppleAPIErrorWithLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let (jsonData, expectedLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion) = try self.mockUserInfoValueProvider(for: error) {
            let altserverError = ALTServerError(nsError)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let expectedLocalizedDescription = nsError.localizedDescription
            let expectedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
            let expectedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
            
            return (jsonData, expectedLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, ALTAppleAPIErrorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, expectedLocalizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAppleAPIErrorThenAddingLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = error as NSError
        
        let (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion) = try self.mockUserInfoValueProvider(for: error) {
            let altserverError = ALTServerError(error)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let originalLocalizedDescription = error.localizedDescription
            let expectedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
            let expectedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
            
            return (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, ALTAppleAPIErrorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, originalLocalizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertNil(receivedUnderlyingNSError.localizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        let expectedLocalizedDescription = String.testLocalizedFailure + " " + originalLocalizedDescription
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAppleAPIErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
        
        let (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion) = try self.mockUserInfoValueProvider(for: error) {
            let altserverError = ALTServerError(nsError)
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let originalLocalizedDescription = nsError.localizedDescription
            let expectedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
            let expectedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
            
            return (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
        
        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
        XCTAssertEqual(receivedUnderlyingError._domain, ALTAppleAPIErrorDomain)
        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, originalLocalizedDescription)
        
        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, .testOriginalLocalizedFailure)
        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
        
        // Test ALTServerError forwards all properties to receivedUnderlyingError
        let expectedLocalizedDescription = String.testLocalizedFailure + " " + expectedFailureReason
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    // Flesh this out
//    func testReceivingUnrecognizedObjCErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
//    {
//        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
//        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
//
//        let (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion) = try self.mockUserInfoValueProvider(for: error) {
//            let altserverError = ALTServerError(nsError)
//            let codableError = CodableError(error: altserverError)
//            let jsonData = try JSONEncoder().encode(codableError)
//
//            let originalLocalizedDescription = nsError.localizedDescription
//            let expectedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
//            let expectedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
//
//            return (jsonData, originalLocalizedDescription, expectedFailureReason, expectedRecoverySuggestion)
//        }
//
//        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
//        let receivedError = decodedError.error
//        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
//
//        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain)
//        XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue)
//
//        let receivedUnderlyingError = try XCTUnwrap(receivedError.underlyingError)
//        XCTAssertEqual(receivedUnderlyingError._domain, ALTAppleAPIErrorDomain)
//        XCTAssertEqual(receivedUnderlyingError._code, error.code.rawValue)
//        XCTAssertEqual(receivedUnderlyingError.localizedDescription, originalLocalizedDescription)
//
//        let receivedUnderlyingNSError = receivedUnderlyingError as NSError
//        XCTAssertEqual(receivedUnderlyingNSError.localizedFailure, .testOriginalLocalizedFailure)
//        XCTAssertEqual(receivedUnderlyingNSError.localizedFailureReason, expectedFailureReason)
//        XCTAssertEqual(receivedUnderlyingNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
//
//        // Test ALTServerError forwards all properties to receivedUnderlyingError
//        let expectedLocalizedDescription = String.testLocalizedFailure + " " + expectedFailureReason
//        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
//        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
//        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedFailureReason)
//        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedRecoverySuggestion)
//
//        if let provider = NSError.userInfoValueProvider(forDomain: type(of: error).errorDomain),
//           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
//        {
//            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
//            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
//        }
//    }
}

//TODO: test mac vs ios error messages

extension AltTests
{
    func mockUserInfoValueProvider<T, Error: Swift.Error>(for error: Error,
                                                          failureReason: String? = .testUnrecognizedFailureReason,
                                                          recoverySuggestion: String? = .testUnrecognizedRecoverySuggestion,
                                                          debugDescription: String? = nil,
                                                          closure: () throws -> T) rethrows -> T
    {
        let provider = NSError.userInfoValueProvider(forDomain: error._domain)
        NSError.setUserInfoValueProvider(forDomain: error._domain) { (error, key) in
            let nsError = error as NSError
            guard nsError.code == error._code else { return provider?(nsError, key) }

            switch key
            {
            case NSLocalizedDescriptionKey:
                guard nsError.localizedFailure == nil else {
                    // Error has localizedFailure, so return nil to construct localizedDescription from it + localizedFailureReason.
                    return nil
                }

                // Otherwise, return failureReason for localizedDescription to avoid system prepending "Operation Failed" message.
                fallthrough

            case NSLocalizedFailureReasonErrorKey: return failureReason
            case NSLocalizedRecoverySuggestionErrorKey: return recoverySuggestion
            case NSDebugDescriptionErrorKey: return debugDescription
            default: return nil
            }
        }

        defer {
            NSError.setUserInfoValueProvider(forDomain: error._domain) { (error, key) in
                provider?(error, key)
            }
        }
        
        let value = try closure()
        return value
    }
    
    func testReceivingUnrecognizedAltServerError() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: error)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        XCTAssertEqual(receivedError.localizedDescription, String.testUnrecognizedFailureReason)
        
        XCTAssertNil(receivedNSError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, String.testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, String.testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: nsError)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        let expectedLocalizedDescription = String.testLocalizedFailure + " " + .testUnrecognizedFailureReason
        XCTAssertEqual(receivedError.localizedDescription, expectedLocalizedDescription)
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedTitle() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: nsError)
            return try JSONEncoder().encode(codableError)
        }

        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        XCTAssertEqual(receivedError.localizedDescription, .testUnrecognizedFailureReason)
        
        XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
        
        XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAltServerErrorThenAddingLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: error)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        // We *can't* change the localized failure for unrecognized errors, so test that localizedDescription == failure reason.
        // *Technically* we could if we remove the NSLocalizedDescription check from
        // NVM, we did that
        let expectedLocalizedDescription = String.testLocalizedFailure + " " + .testUnrecognizedFailureReason
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        
        XCTAssertEqual(receivedNSError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAltServerErrorThenAddingLocalizedTitle() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: error)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        XCTAssertEqual(receivedNSError.localizedDescription, String.testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
        
        XCTAssertNil(receivedNSError.localizedFailure)
        XCTAssertEqual(receivedNSError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: nsError)
            return try JSONEncoder().encode(codableError)
        }
        
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        // We *can't* change the localized failure for unrecognized errors, so test that localizedDescription == original failure + failure reason.
        // NVM, above no longer true
        // NVMx2, back to first thought...idk
        let expectedLocalizedDescription = String.testLocalizedFailure + " " + receivedError.localizedDescription
        XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
        
        // Test that localizedFailure did in fact change.
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        
        // Test that decoded error retains original localized failure.
        XCTAssertEqual((receivedError as NSError).localizedFailure, .testOriginalLocalizedFailure)
        
        XCTAssertEqual(receivedNSError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
}

extension AltTests
{
    func testReceivingAltServerErrorWithDifferentErrorMessages() async throws
    {
        let error = ALTServerError(.pluginNotFound)
        let nsError = error as NSError
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: error)
            return try JSONEncoder().encode(codableError)
        }
                
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        let expectedLocalizedDescription = try XCTUnwrap(nsError.localizedFailureReason)
        XCTAssertEqual(receivedError.localizedDescription, expectedLocalizedDescription)
        
        let expectedLocalizedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedLocalizedFailureReason)
        
        let expectedLocalizedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedLocalizedRecoverySuggestion)
        
        XCTAssertEqual(receivedNSError.localizedFailure, nsError.localizedFailure)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailureAndDifferentErrorMessages() async throws
    {
        let error = ALTServerError(.pluginNotFound)
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let jsonData = try self.mockUserInfoValueProvider(for: error) {
            let codableError = CodableError(error: nsError)
            return try JSONEncoder().encode(codableError)
        }
                
        let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        let receivedError = decodedError.error
        let receivedNSError = receivedError as NSError
        
        XCTAssertEqual(receivedError._domain, error._domain)
        XCTAssertEqual(receivedError._code, error.code.rawValue)
        
        let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
        XCTAssertEqual(receivedError.localizedDescription, expectedLocalizedDescription)
        
        let expectedLocalizedFailureReason = try XCTUnwrap(nsError.localizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedFailureReason, expectedLocalizedFailureReason)
        
        let expectedLocalizedRecoverySuggestion = try XCTUnwrap(nsError.localizedRecoverySuggestion)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, expectedLocalizedRecoverySuggestion)
        
        XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)

        if let provider = NSError.userInfoValueProvider(forDomain: ALTServerError.errorDomain),
           let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
        {
            let unbridgedDebugDescription = provider(receivedError, NSDebugDescriptionErrorKey) as? String
            XCTAssertEqual(debugDescription, unbridgedDebugDescription)
        }
    }
}

//TODO: Test userinfo parameters are transferred correctly from altserver to altstore

//public protocol RSTErrorCode: RawRepresentable where RawValue == Int
//{
//    associatedtype Error = RSTLocalizedError<Self>
//
//    static var errorDomain: String { get }
//    func error() -> Swift.Error
//
//    var errorFailureReason: String { get } // Required
//}
//
//extension RSTErrorCode
//{
//    public static var errorDomain: String {
//        return "\(type(of: self))"
//    }
//
//    func error() -> Swift.Error
//    {
//        return RSTLocalizedError(self)
//    }
//}
//
//public struct RSTLocalizedError<Code: RSTErrorCode>: LocalizedError, CustomNSError
//{
//    public var code: Code
//
//    var errorFailure: String?
//    var errorTitle: String?
//
//    init(_ code: Code)
//    {
//        self.code = code
//    }
//}
//
//extension RSTLocalizedError
//{
//    public static var errorDomain: String {
//        return Code.errorDomain
//    }
//
//    public var errorCode: Int { self.code.rawValue }
//
//    public var errorUserInfo: [String : Any] {
//        var userInfo: [String: Any] = [
//            NSLocalizedFailureErrorKey: self.errorFailure,
//            ALTLocalizedTitleErrorKey: self.errorTitle
//        ].compactMapValues { $0 }
//
//        userInfo[ALTWrappedErrorKey] = RSTBox(wrappedError: self)
//
//        return userInfo
//    }
//
//    public var errorDescription: String? {
//        guard (self as NSError).localizedFailure == nil else {
//            // Error has localizedFailure, so return nil to construct localizedDescription from it + localizedFailureReason.
//            return nil
//        }
//
//        if let altLocalizedDescription = (self as NSError).userInfo[ErrorUserInfoKey.altLocalizedDescription] as? String
//        {
//            // Use cached localized description, since this is only called if localizedDescription couldn't be constructed from user info
//            return altLocalizedDescription
//        }
//
//        // Otherwise, return failureReason for localizedDescription to avoid system prepending "Operation Failed" message.
//        return self.failureReason
//    }
//
//    public var failureReason: String? {
//        return self.code.errorFailureReason
//    }
//}
//
//extension RSTLocalizedError: _ObjectiveCBridgeableError
//{
//    public init?(_bridgedNSError error: NSError)
//    {
//        guard error.domain == Code.errorDomain else { return nil }
//
//        if let wrappedError = error.userInfo["ALTWrappedError"] as? Self
//        {
//            self = wrappedError
//        }
//        else
//        {
//            let code = Code(rawValue: error.code)!
//            self = RSTLocalizedError(code)
//        }
//
//        self.errorFailure = error.userInfo[NSLocalizedFailureErrorKey] as? String
//        self.errorTitle = error.userInfo[ALTLocalizedTitleErrorKey] as? String
//    }
//}

//enum EmergencyError: Int, RSTErrorCode, CaseIterable
//{
//    case alienInvasion
//    case vacuumDecay
//    
//    var errorFailureReason: String {
//        switch self
//        {
//        case .alienInvasion: return "The alien invasion has begun."
//        case .vacuumDecay: return "The universe has began to decay."
//        }
//    }
//}
//
//enum MundaneError: Int, RSTErrorCode, CaseIterable
//{
//    case dogAteHomework
//    case noInternet
//    
//    var errorFailureReason: String {
//        switch self
//        {
//        case .dogAteHomework: return "The dog ate my homework."
//        case .noInternet: return "The Internet is down."
//        }
//    }
//}

//extension AltTests
//{
//    func testRefactoredWithLocalizedFailureAndBack() async throws
//    {
//        let errors: [Swift.Error] = EmergencyError.allCases.map { $0.error() } + MundaneError.allCases.map { $0.error() }
//
//        for error in errors
//        {
//            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
//
//            func test(_ unbridgedError: Error, against nsError: NSError)
//            {
//                let unbridgedNSError = (unbridgedError as NSError)
//
//                let expectedLocalizedDescription = String.testLocalizedFailure + " " + nsError.localizedFailureReason!
//                XCTAssertEqual(unbridgedError.localizedDescription, expectedLocalizedDescription)
//                XCTAssertEqual(unbridgedNSError.localizedFailure, .testLocalizedFailure)
//
//                // Test remainder
//                XCTAssertEqual(unbridgedNSError.localizedFailureReason, nsError.localizedFailureReason)
//                XCTAssertEqual(unbridgedNSError.localizedRecoverySuggestion, nsError.localizedRecoverySuggestion)
//
//                if let provider = NSError.userInfoValueProvider(forDomain: OperationError.errorDomain),
//                   let debugDescription = provider(error, NSDebugDescriptionErrorKey) as? String
//                {
//                    XCTAssertEqual(debugDescription, nsError.debugDescription)
//                }
//            }
//
//            do
//            {
//                throw nsError as NSError
//            }
//            catch let error as VerificationError
//            {
//                test(error, against: nsError)
//            }
//            catch let error as OperationError
//            {
//                test(error, against: nsError)
//            }
//            catch let error as EmergencyError.Error
//            {
//                test(error, against: nsError)
//            }
//            catch let error as MundaneError.Error
//            {
//                test(error, against: nsError)
//            }
//            catch
//            {
//                test(error, against: nsError)
//            }
//        }
//    }
//}
