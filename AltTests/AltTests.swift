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
    static let testDomain = "TestErrorDomain"
    
    static let testLocalizedTitle = "AltTest Failed"
    static let testLocalizedFailure = "The AltTest failed to pass."
    
    static let testOriginalLocalizedFailure = "The AltServer operation could not be completed."
    
    static let testUnrecognizedFailureReason = "The alien invasion has begun."
    static let testUnrecognizedRecoverySuggestion = "Find your loved ones and pray the aliens are merciful."
    
    static let testDescription = "The operation could not be completed because an error occured."
    static let testDebugDescription = "The very specific operation could not be completed because a detailed error occured. Code=101."
}

extension [String: String]
{
    static let unrecognizedProvider: Self = [
        NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
        NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
    ]
}

extension Error
{
    func serialized(provider: [String: String]?) -> NSError
    {
        AltTests.mockUserInfoValueProvider(for: self, values: provider) {
            return (self as NSError).sanitizedForSerialization()
        }
    }
}

extension URL
{
    static let testFileURL = URL(fileURLWithPath: "~/Desktop/TestApp.ipa")
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

// Helper Methods
extension AltTests
{
    func unbridge<T: ALTLocalizedError>(_ error: NSError, to errorType: T) throws -> Error
    {
        let unbridgedError = try XCTUnwrap(error as? T)
        return unbridgedError
    }
    
    func send(_ error: Error, serverProvider: [String: String]? = nil, clientProvider: [String: String]? = nil) throws -> NSError
    {
        let altserverError = ALTServerError(error)
        
        let codableError = CodableError(error: altserverError)
        
        let jsonData: Data
        if let serverProvider
        {
            jsonData = try AltTests.mockUserInfoValueProvider(for: error, values: serverProvider) {
                return try JSONEncoder().encode(codableError)
            }
        }
        else
        {
            jsonData = try JSONEncoder().encode(codableError)
        }
        
        let decodedError: CodableError
        if let clientProvider
        {
            decodedError = try AltTests.mockUserInfoValueProvider(for: error, values: clientProvider) {
                return try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            }
        }
        else
        {
            decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
        }
        
        let receivedError = decodedError.error
        return receivedError as NSError
    }
    
    static func mockUserInfoValueProvider<T, Error: Swift.Error>(for error: Error, values: [String: String]?, closure: () throws -> T) rethrows -> T
    {
        let provider = NSError.userInfoValueProvider(forDomain: error._domain)
        NSError.setUserInfoValueProvider(forDomain: error._domain) { (error, key) -> Any? in
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
                return values?[NSLocalizedFailureReasonErrorKey]
                
            default:
                return values?[key]
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
    
    func ALTAssertErrorsEqual(_ error1: Error, _ error2: Error, ignoring ignoredValues: Set<String> = [], ignoreExtraUserInfoValues: Bool = false, file: StaticString = #file, line: UInt = #line)
    {
        if !ignoredValues.contains(ALTUnderlyingErrorDomainErrorKey)
        {
            XCTAssertEqual(error1._domain, error2._domain, file: file, line: line)
        }
        
        if !ignoredValues.contains(ALTUnderlyingErrorCodeErrorKey)
        {
            XCTAssertEqual(error1._code, error2._code, file: file, line: line)
        }
        
        if !ignoredValues.contains(NSLocalizedDescriptionKey)
        {
            XCTAssertEqual(error1.localizedDescription, error2.localizedDescription, "Localized Descriptions don't match.", file: file, line: line)
        }
        
        let nsError1 = error1 as NSError
        let nsError2 = error2 as NSError
        
        if !ignoredValues.contains(ALTLocalizedTitleErrorKey)
        {
            XCTAssertEqual(nsError1.localizedTitle, nsError2.localizedTitle, "Titles don't match.", file: file, line: line)
        }
        
        if !ignoredValues.contains(NSLocalizedFailureErrorKey)
        {
            XCTAssertEqual(nsError1.localizedFailure, nsError2.localizedFailure, "Failures don't match.", file: file, line: line)
        }
        
        if !ignoredValues.contains(NSLocalizedFailureReasonErrorKey)
        {
            XCTAssertEqual(nsError1.localizedFailureReason, nsError2.localizedFailureReason, "Failure reasons don't match.", file: file, line: line)
        }
        
        if !ignoredValues.contains(NSLocalizedRecoverySuggestionErrorKey)
        {
            XCTAssertEqual(nsError1.localizedRecoverySuggestion, nsError2.localizedRecoverySuggestion, file: file, line: line)
        }
        
        if !ignoredValues.contains(NSDebugDescriptionErrorKey)
        {
            XCTAssertEqual(nsError1.localizedDebugDescription, nsError2.localizedDebugDescription, file: file, line: line)
        }
        
        if !ignoreExtraUserInfoValues
        {
            // Ensure remaining user info values match.
            let standardKeys: Set<String> = [NSLocalizedDescriptionKey, ALTLocalizedTitleErrorKey, NSLocalizedFailureErrorKey, NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSUnderlyingErrorKey, NSDebugDescriptionErrorKey]
            let filteredUserInfo1 = nsError1.userInfo.filter { !standardKeys.contains($0.key) }
            let filteredUserInfo2 = nsError2.userInfo.filter { !standardKeys.contains($0.key) }
            XCTAssertEqual(filteredUserInfo1 as NSDictionary, filteredUserInfo2 as NSDictionary, file: file, line: line)
        }
    }
    
    @discardableResult
    func ALTAssertUnderlyingErrorEqualsError(_ receivedError: Error, _ error: Error, ignoring ignoredValues: Set<String> = [], ignoreExtraUserInfoValues: Bool = false, file: StaticString = #file, line: UInt = #line) throws -> NSError
    {
        // Test receivedError == ALTServerError.underlyingError
        XCTAssertEqual(receivedError._domain, ALTServerError.errorDomain, file: file, line: line)
        
        if !ignoredValues.contains(ALTUnderlyingErrorCodeErrorKey)
        {
            XCTAssertEqual(receivedError._code, ALTServerError.underlyingError.rawValue, file: file, line: line)
        }
        
        // Test underlyingError == error
        let underlyingError = try XCTUnwrap(receivedError.underlyingError)
        ALTAssertErrorsEqual(underlyingError, error, ignoring: ignoredValues, ignoreExtraUserInfoValues: ignoreExtraUserInfoValues, file: file, line: line)
        
        // Test receivedError forwards all properties to underlyingError.
        var ignoredValues = ignoredValues
        ignoredValues.formUnion([ALTUnderlyingErrorDomainErrorKey, ALTUnderlyingErrorCodeErrorKey])
        ALTAssertErrorsEqual(receivedError, underlyingError, ignoring: ignoredValues, ignoreExtraUserInfoValues: true, file: file, line: line) // Always ignore extra user info values.
        
        return underlyingError as NSError
    }
    
    func ALTAssertErrorFailureAndDescription(_ error: Error, failure: String?, baseDescription: String, file: StaticString = #file, line: UInt = #line)
    {
        let localizedDescription: String
        if let failure
        {
            localizedDescription = failure + " " + baseDescription
        }
        else
        {
            localizedDescription = baseDescription
        }
        
        XCTAssertEqual(error.localizedDescription, localizedDescription, file: file, line: line)
        XCTAssertEqual((error as NSError).localizedFailure, failure, file: file, line: line)
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
                // Test localizedDescription does not start with "The operation couldn't be completed."
                XCTAssert(!error.localizedDescription.starts(with: "The operation couldn’t be completed."), error.localizedDescription)
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
            
            ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
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
            ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
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
            ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, ALTLocalizedTitleErrorKey])
        }
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
                
                // Test dynamic type matches original error type
                XCTAssert(type(of: unbridgedError) == type(of: error))
                
                // Test remainder
                ALTAssertErrorsEqual(unbridgedNSError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
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
                
                let unbridgedError = try self.unbridge(error as NSError, to: error)
                test(unbridgedError, against: nsError)
            }
        }
    }
    
    func testPatternMatchingErrorCode() async throws
    {
        do
        {
            // ALTLocalizedError
            throw OperationError.serverNotFound
        }
        catch ~OperationError.Code.serverNotFound
        {
            // Success
        }
        catch
        {
            XCTFail("Failed to catch error as OperationError.Code.serverNotFound: \(error)")
        }
        
        do
        {
            // ALTErrorEnum
            throw AuthenticationError(.noTeam)
        }
        catch ~AuthenticationErrorCode.noTeam
        {
            // Success
        }
        catch
        {
            XCTFail("Failed to catch error as AuthenticationErrorCode.noTeam: \(error)")
        }
    }
    
    func testWithLocalizedTitle() async throws
    {
        let localizedTitle = "AltTest Failed"

        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(localizedTitle)
            
            XCTAssertEqual(nsError.localizedTitle, localizedTitle)
            
            ALTAssertErrorsEqual(nsError, error, ignoring: [ALTLocalizedTitleErrorKey])
        }
    }
    
    func testWithLocalizedTitleAndBack() async throws
    {
        for error in AltTests.allLocalErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            let unbridgedError = try self.unbridge(nsError, to: error)
            let unbridgedNSError = (unbridgedError as NSError)
            
            XCTAssertEqual(unbridgedNSError.localizedTitle, .testLocalizedTitle)
            
            ALTAssertErrorsEqual(unbridgedNSError, error, ignoring: [ALTLocalizedTitleErrorKey])
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
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap((error as NSError).localizedFailureReason)
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
            
            // Test remainder
            ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, ALTLocalizedTitleErrorKey, NSLocalizedFailureErrorKey])
        }
    }
    
    func testSwiftErrorWithLocalizedFailure() async throws
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
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
            ALTAssertErrorFailureAndDescription(nsError, failure: .testLocalizedFailure, baseDescription: error.localizedDescription)
        }
    }
    
    func testNSErrorWithLocalizedFailure() async throws
    {
        let error = NSError(domain: .testDomain, code: 14, userInfo: [NSLocalizedDescriptionKey: String.testDescription])
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        ALTAssertErrorsEqual(nsError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        ALTAssertErrorFailureAndDescription(nsError, failure: .testLocalizedFailure, baseDescription: .testDescription)
    }
    
    func testReceivingAltServerError() async throws
    {
        for error in ALTServerError.testErrors
        {
            let codableError = CodableError(error: error)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            
            ALTAssertErrorsEqual(receivedError, error)
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailure() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            let altserverError = ALTServerError(nsError)
            
            let codableError = CodableError(error: altserverError)
            let jsonData = try JSONEncoder().encode(codableError)
            
            let decodedError = try Foundation.JSONDecoder().decode(CodableError.self, from: jsonData)
            let receivedError = decodedError.error
            let receivedNSError = receivedError as NSError
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap((error as NSError).localizedFailureReason)
            XCTAssertEqual(nsError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            ALTAssertErrorsEqual(receivedError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedTitle() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
            let receivedError = try self.send(nsError)
            
            XCTAssertEqual(receivedError.localizedTitle, .testLocalizedTitle)
            ALTAssertErrorsEqual(receivedError, error, ignoring: [ALTLocalizedTitleErrorKey])
        }
    }
    
    func testReceivingAltServerErrorThenAddingLocalizedFailure() async throws
    {
        for error in ALTServerError.testErrors
        {
            let receivedError = try self.send(error)
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap((error as NSError).localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            ALTAssertErrorsEqual(receivedNSError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        }
    }
    
    func testReceivingAltServerErrorThenAddingLocalizedTitle() async throws
    {
        for error in ALTServerError.testErrors
        {
            let receivedError = try self.send(error)
            let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
            
            ALTAssertErrorsEqual(receivedNSError, error, ignoring: [ALTLocalizedTitleErrorKey])
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
            let receivedError = try self.send(nsError)
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            
            // Test that decoded error retains original localized failure.
            XCTAssertEqual((receivedError as NSError).localizedFailure, .testOriginalLocalizedFailure)
            
            ALTAssertErrorsEqual(receivedNSError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        }
    }
    
    func testReceivingAltServerErrorWithLocalizedFailureThenAddingLocalizedTitle() async throws
    {
        for error in ALTServerError.testErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            let receivedError = try self.send(nsError)
            let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
            XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
            
            ALTAssertErrorsEqual(receivedNSError, error, ignoring: [NSLocalizedDescriptionKey, ALTLocalizedTitleErrorKey, NSLocalizedFailureErrorKey])
        }
    }
    
    func testReceivingNonAltServerSwiftError() async throws
    {
        for error in allTestErrors
        {
            let receivedError = try self.send(error)
            try ALTAssertUnderlyingErrorEqualsError(receivedError, error)
        }
    }
    
    func testReceivingNonAltServerSwiftErrorWithSourceLocation() async throws
    {
        let file = #fileID
        let line = #line as UInt
        
        let error = OperationError.unknown(file: file, line: line)
        let receivedError = try self.send(error)
        
        XCTAssertEqual(receivedError.userInfo[ALTSourceFileErrorKey] as? String, file)
        
        if let uint = receivedError.userInfo[ALTSourceLineErrorKey] as? UInt
        {
            XCTAssertEqual(uint, line)
        }
        else if let int = receivedError.userInfo[ALTSourceLineErrorKey] as? Int
        {
            XCTAssertEqual(int, Int(line))
        }
        
        try ALTAssertUnderlyingErrorEqualsError(receivedError, error)
    }
    
    func testReceivingNonAltServerSwiftErrorWithLocalizedFailure() async throws
    {
        for error in allTestErrors
        {
            let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
            let receivedError = try self.send(nsError)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap(nsError.localizedFailureReason)
            XCTAssertEqual(receivedError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedError.localizedFailure, .testLocalizedFailure)
            
            let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedUnderlyingError.localizedFailure, .testLocalizedFailure)
        }
    }
    
    func testReceivingNonAltServerSwiftErrorThenAddingLocalizedFailure() async throws
    {
        for error in allTestErrors
        {
            let receivedError = try self.send(error)
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
            
            let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
            XCTAssertEqual(receivedUnderlyingError.localizedDescription, error.errorFailureReason)
            XCTAssertNil(receivedUnderlyingError.localizedFailure)
            
            let expectedLocalizedDescription = try String.testLocalizedFailure + " " + XCTUnwrap((error as NSError).localizedFailureReason)
            XCTAssertEqual(receivedNSError.localizedDescription, expectedLocalizedDescription)
            XCTAssertEqual(receivedNSError.localizedFailure, .testLocalizedFailure)
        }
    }
    
    func testReceivingNonAltServerSwiftErrorThenAddingLocalizedTitle() async throws
    {
        for error in allTestErrors
        {
            let receivedError = try self.send(error)
            let receivedNSError = (receivedError as NSError).withLocalizedTitle(.testLocalizedTitle)
            
            XCTAssertNil(error.errorTitle)
            XCTAssertEqual(receivedNSError.localizedTitle, .testLocalizedTitle)
            
            let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, error, ignoring: [ALTLocalizedTitleErrorKey])
            XCTAssertNil(receivedUnderlyingError.localizedTitle)
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
            let receivedError = try self.send(error, clientProvider: [:])
            try ALTAssertUnderlyingErrorEqualsError(receivedError, error)
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
            let receivedError = try self.send(error, clientProvider: [:])
            let receivedNSError = receivedError.withLocalizedFailure(.testLocalizedFailure)
            
            let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, error, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
            ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: error.localizedDescription)
            ALTAssertErrorFailureAndDescription(receivedUnderlyingError, failure: nil, baseDescription: error.localizedDescription)
        }
    }
    
    func testReceivingNonAltServerCocoaError() async throws
    {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "~/Desktop/TestFile"])
        
        let receivedError = try self.send(error)
        try ALTAssertUnderlyingErrorEqualsError(receivedError, error)
    }
    
    func testReceivingNonAltServerCocoaErrorWithLocalizedFailure() async throws
    {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "~/Desktop/TestFile"])
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let receivedError = try self.send(nsError)
        try ALTAssertUnderlyingErrorEqualsError(receivedError, nsError)
        
        // Description == .testLocalizedFailure + failureReason ?? description
        ALTAssertErrorFailureAndDescription(receivedError, failure: .testLocalizedFailure, baseDescription: nsError.localizedFailureReason ?? error.localizedDescription)
    }
    
    func testReceivingAltServerConnectionError() async throws
    {
        let error = ALTServerConnectionError(.deviceLocked, userInfo: [ALTDeviceNameErrorKey: "Riley's iPhone"])
        let nsError = error as NSError
        
        let receivedError = try self.send(nsError)
        let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, nsError, ignoring: [ALTUnderlyingErrorCodeErrorKey, NSLocalizedFailureErrorKey, NSLocalizedDescriptionKey])
        
        // Code == ALTServerError.connectionFailed
        XCTAssertEqual(receivedError.code, ALTServerError.connectionFailed.rawValue)
        
        // Underlying Code == ALTServerConnectionError.deviceLocked
        XCTAssertEqual(receivedUnderlyingError.code, ALTServerConnectionError.deviceLocked.rawValue)
        
        // Description == defaultFailure + error.localizedDescription
        let defaultFailure = try XCTUnwrap((ALTServerError(.connectionFailed) as NSError).localizedFailureReason)
        ALTAssertErrorFailureAndDescription(receivedError, failure: defaultFailure, baseDescription: error.localizedDescription)
        
        // Underlying Description = error.localizedDescription
        ALTAssertErrorFailureAndDescription(receivedUnderlyingError, failure: nil, baseDescription: error.localizedDescription)
    }
    
    func testReceivingAppleAPIError() async throws
    {
        let error = ALTAppleAPIError(.incorrectCredentials)
        let nsError = error as NSError
        
        let receivedError = try self.send(nsError, serverProvider: [NSDebugDescriptionErrorKey: .testDebugDescription])

        // Debug Description == .testDebugDescription
        XCTAssertEqual(receivedError.localizedDebugDescription, .testDebugDescription)
        
        let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, error, ignoring: [NSDebugDescriptionErrorKey])
        
        // Debug Description == .testDebugDescription
        XCTAssertEqual(receivedUnderlyingError.localizedDebugDescription, .testDebugDescription)
    }
    
    func testReceivingCodableError() async throws
    {
        let json = "{'name2': 'riley'}"
        
        struct Test: Decodable
        {
            var name: String
        }
        
        let rawData = json.data(using: .utf8)!
        let error: DecodingError
        
        do
        {
            _ = try Foundation.JSONDecoder().decode(Test.self, from: rawData)
            return
        }
        catch let decodingError as DecodingError
        {
            error = decodingError
        }
        catch
        {
            XCTFail("Only DecodingErrors should be thrown.")
            return
        }
        
        let nsError = error as NSError
        
        let receivedError = try self.send(nsError)
        
        // Code == ALTServerError.invalidRequest
        // Description == CocoaError.coderReadCorrupt.localizedDescription
        XCTAssertEqual(receivedError.code, ALTServerError.invalidRequest.rawValue)
        XCTAssertEqual(receivedError.localizedDescription, CocoaError(.coderReadCorrupt).localizedDescription)
        
        let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, nsError, ignoring: [ALTUnderlyingErrorCodeErrorKey, NSLocalizedDescriptionKey])
        
        // Underlying Code == CocoaError.coderReadCorrupt
        // Underlying Description == CocoaError.coderReadCorrupt.localizedDescription
        XCTAssertEqual(receivedUnderlyingError.code, CocoaError.coderReadCorrupt.rawValue)
        XCTAssertEqual(receivedUnderlyingError.localizedDescription, CocoaError(.coderReadCorrupt).localizedDescription)
    }
    
    func testReceivingUnrecognizedAppleAPIError() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let cachedError = error.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(error, serverProvider: .unrecognizedProvider)
        
        // Description == .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(receivedError, failure: nil, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        
        let underlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, cachedError)
        
        // Underlying Description == .testUnrecognizedFailureReason
        // Underlying Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(underlyingError, failure: nil, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(underlyingError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
    }
    
    func testReceivingUnrecognizedAppleAPIErrorWithLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let receivedError = try self.send(nsError, serverProvider: [
            NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
            NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
        ])
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(receivedError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        
        let underlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, nsError, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSLocalizedDescriptionKey])
        
        // Underlying Failure == .testLocalizedFailure
        // Underlying Description == Failure + .testUnrecognizedFailureReason
        // Underlying Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(underlyingError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(underlyingError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
    }
    
    func testReceivingUnrecognizedAppleAPIErrorThenAddingLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let receivedError = try self.send(error, serverProvider: [
            NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
            NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
        ])
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        
        let underlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, error, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        
        // Underlying Failure == nil
        // Underlying Description == .testUnrecognizedFailureReason
        // Underlying Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(underlyingError, failure: nil, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(underlyingError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
    }
    
    func testReceivingUnrecognizedAppleAPIErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        let error = ALTAppleAPIError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
        
        let receivedError = try self.send(nsError, serverProvider: [
            NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
            NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
        ])
        
        // Failure == .testOriginalLocalizedFailure
        XCTAssertEqual(receivedError.localizedFailure, .testOriginalLocalizedFailure)
        
        let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedNSError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        
        let underlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, nsError, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
        
        // Underlying Failure == .testOriginalLocalizedFailure
        // Underlying Description == Underlying Failure + .testUnrecognizedFailureReason
        // Underlying Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(underlyingError, failure: .testOriginalLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(underlyingError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
    }
    
    func testReceivingUnrecognizedObjCErrorsWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        // User Info = nil
        var nsErrorWithNoUserInfo = NSError(domain: .testDomain, code: 14)
        nsErrorWithNoUserInfo = nsErrorWithNoUserInfo.withLocalizedFailure(.testOriginalLocalizedFailure)
        
        // User Info = Failure Reason
        var nsErrorWithUserInfoFailureReason = NSError(domain: .testDomain, code: 14, userInfo: [
            NSLocalizedFailureReasonErrorKey: String.testUnrecognizedFailureReason
        ])
        nsErrorWithUserInfoFailureReason = nsErrorWithUserInfoFailureReason.withLocalizedFailure(.testOriginalLocalizedFailure)
        
        // User Info = Description
        var nsErrorWithUserInfoDescription = NSError(domain: .testDomain, code: 14, userInfo: [
            NSLocalizedDescriptionKey: String.testDebugDescription
        ])
        nsErrorWithUserInfoDescription = nsErrorWithUserInfoDescription.withLocalizedFailure(.testOriginalLocalizedFailure)
        
        // User Info = Failure
        let nsErrorWithUserInfoFailure = NSError(domain: .testDomain, code: 14, userInfo: [
            NSLocalizedFailureErrorKey: String.testOriginalLocalizedFailure
        ])
        
        // User Info = Failure, Failure Reason
        let nsErrorWithUserInfoFailureAndFailureReason = NSError(domain: .testDomain, code: 14, userInfo: [
            NSLocalizedFailureErrorKey: String.testOriginalLocalizedFailure,
            NSLocalizedFailureReasonErrorKey: String.testUnrecognizedFailureReason
        ])
                
        // User Info = Failure, Description
        let nsErrorWithUserInfoFailureAndDescription = NSError(domain: .testDomain, code: 14, userInfo: [
            NSLocalizedFailureErrorKey: String.testOriginalLocalizedFailure,
            NSLocalizedDescriptionKey: String.testDebugDescription
        ])
        
        let errors = [nsErrorWithNoUserInfo, nsErrorWithUserInfoFailureReason, nsErrorWithUserInfoDescription, nsErrorWithUserInfoFailure, nsErrorWithUserInfoFailureAndFailureReason, nsErrorWithUserInfoFailureAndDescription]
        for nsError in [errors[0]]
        {
            let provider = [NSLocalizedFailureReasonErrorKey: String.testUnrecognizedFailureReason]
            
            // Use provider only if user info doesn't contain failure reason or localized description.
            let serverProvider = (nsError.userInfo.keys.contains(NSLocalizedFailureReasonErrorKey) || nsError.userInfo.keys.contains(NSLocalizedDescriptionKey)) ? nil : provider
            let baseDescription = serverProvider?[NSLocalizedFailureReasonErrorKey] ?? nsError.localizedFailureReason ?? .testDebugDescription
            
            let receivedError = try self.send(nsError, serverProvider: serverProvider)
            
            // Failure == .testOriginalLocalizedFailure
            XCTAssertEqual(receivedError.localizedFailure, .testOriginalLocalizedFailure)
            
            let receivedNSError = (receivedError as NSError).withLocalizedFailure(.testLocalizedFailure)
                        
            // Failure == .testLocalizedFailure
            // Description == Failure + baseDescription
            ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: baseDescription)
            
            let underlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedNSError, nsError, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey])
            
            // Underlying Failure == .testOriginalLocalizedFailure
            // Underlying Description == Underlying Failure + baseDescription
            ALTAssertErrorFailureAndDescription(underlyingError, failure: .testOriginalLocalizedFailure, baseDescription: serverProvider?[NSLocalizedFailureReasonErrorKey] ?? nsError.localizedFailureReason ?? .testDebugDescription)
        }
    }
}

extension AltTests
{
    func testReceivingUnrecognizedAltServerError() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let receivedError = try self.send(error, serverProvider: [
            NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
            NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
        ])
        
        // Description == .testUnrecognizedFailureReason
        // Failure Reason == .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        XCTAssertEqual(receivedError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        ALTAssertErrorFailureAndDescription(receivedError, failure: nil, baseDescription: .testUnrecognizedFailureReason)
        ALTAssertErrorsEqual(receivedError, error, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSLocalizedDescriptionKey])
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        
        let receivedError = try self.send(nsError, serverProvider: [
            NSLocalizedFailureReasonErrorKey: .testUnrecognizedFailureReason,
            NSLocalizedRecoverySuggestionErrorKey: .testUnrecognizedRecoverySuggestion
        ])
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        // Failure Reason == .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorFailureAndDescription(receivedError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedError.localizedFailureReason, .testUnrecognizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, .testUnrecognizedRecoverySuggestion)
        ALTAssertErrorsEqual(receivedError, nsError, ignoring: [NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey, NSLocalizedDescriptionKey])
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedTitle() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedTitle(.testLocalizedTitle)
        let referenceError = nsError.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(nsError, serverProvider: .unrecognizedProvider)
        
        // Title == .testLocalizedTitle
        XCTAssertEqual(receivedError.localizedTitle, .testLocalizedTitle)
        
        ALTAssertErrorsEqual(receivedError, referenceError)
    }
    
    func testReceivingUnrecognizedAltServerErrorThenAddingLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let serializedError = (error as NSError).serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(error, serverProvider: .unrecognizedProvider)
        
        // Failure == nil
        XCTAssertEqual(receivedError.localizedFailure, nil)
        
        let receivedNSError = receivedError.withLocalizedFailure(.testLocalizedFailure)
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        ALTAssertErrorsEqual(receivedNSError, serializedError, ignoring: [NSLocalizedFailureErrorKey, NSLocalizedDescriptionKey])
    }
    
    func testReceivingUnrecognizedAltServerErrorThenAddingLocalizedTitle() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let serializedError = error.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(error, serverProvider: .unrecognizedProvider)
        
        // Title == nil
        XCTAssertEqual(receivedError.localizedTitle, nil)
        
        let receivedNSError = receivedError.withLocalizedTitle(.testLocalizedTitle)
        
        // Title == .testLocalizedTitle
        ALTAssertErrorsEqual(receivedNSError, serializedError, ignoring: [ALTLocalizedTitleErrorKey])
    }
    
    func testReceivingUnrecognizedAltServerErrorWithLocalizedFailureThenChangingLocalizedFailure() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)
        let serializedError = nsError.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(nsError, serverProvider: .unrecognizedProvider)
        
        // Failure == .testOriginalLocalizedFailure
        XCTAssertEqual(receivedError.localizedFailure, .testOriginalLocalizedFailure)
        
        let receivedNSError = receivedError.withLocalizedFailure(.testLocalizedFailure)
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        ALTAssertErrorFailureAndDescription(receivedNSError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        ALTAssertErrorsEqual(receivedNSError, serializedError, ignoring: [NSLocalizedFailureErrorKey, NSLocalizedDescriptionKey])
    }
}

extension AltTests
{
    func testReceivingAltServerErrorWithDifferentErrorMessages() async throws
    {
        let error = ALTServerError(.pluginNotFound)
        let serializedError = error.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(error, serverProvider: .unrecognizedProvider)
        
        // Description == error.localizedDescription (not .testUnrecognizedFailureReason)
        // Failure Reason == error.localizedFailureReason (not .testUnrecognizedFailureReason)
        // Recovery Suggestion == error.recoverySuggestion (not .testUnrecognizedRecoverySuggestion)
        XCTAssertEqual(receivedError.localizedDescription, error.localizedDescription)
        XCTAssertEqual(receivedError.localizedFailureReason, (error as NSError).localizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, (error as NSError).localizedRecoverySuggestion)
        ALTAssertErrorsEqual(receivedError, serializedError, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey])
    }
    
    func testReceivingAltServerErrorWithLocalizedFailureAndDifferentErrorMessages() async throws
    {
        let error = ALTServerError(.pluginNotFound)
        let nsError = (error as NSError).withLocalizedFailure(.testLocalizedFailure)
        let serializedError = nsError.serialized(provider: .unrecognizedProvider)
        
        let receivedError = try self.send(nsError, serverProvider: .unrecognizedProvider)
        
        // Failure == .testLocalizedFailure
        // Description == Failure + error.localizedFailureReason (not .testUnrecognizedFailureReason)
        // Failure Reason == error.localizedFailureReason (not .testUnrecognizedFailureReason)
        // Recovery Suggestion == error.recoverySuggestion (not .testUnrecognizedRecoverySuggestion)
        ALTAssertErrorFailureAndDescription(receivedError, failure: .testLocalizedFailure, baseDescription: try XCTUnwrap(nsError.localizedFailureReason))
        XCTAssertEqual(receivedError.localizedFailureReason, (error as NSError).localizedFailureReason)
        XCTAssertEqual(receivedError.localizedRecoverySuggestion, (error as NSError).localizedRecoverySuggestion)
        ALTAssertErrorsEqual(receivedError, serializedError, ignoring: [NSLocalizedDescriptionKey, NSLocalizedFailureErrorKey, NSLocalizedFailureReasonErrorKey, NSLocalizedRecoverySuggestionErrorKey])
    }
}

extension AltTests
{
    func testReceivingUnrecognizedAltServerErrorThenAddingLocalizedFailureBeforeSerializing() async throws
    {
        let error = ALTServerError(.init(rawValue: -27)!) /* Alien Invasion */
        
        let receivedError = try self.send(error, serverProvider: .unrecognizedProvider)
        let receivedNSError = receivedError.withLocalizedFailure(.testLocalizedFailure)
        
        let serializedError = receivedNSError.sanitizedForSerialization()
        
        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        ALTAssertErrorFailureAndDescription(serializedError, failure: .testLocalizedFailure, baseDescription: .testUnrecognizedFailureReason)
        
        // Failure Reason == .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorsEqual(serializedError, receivedNSError, ignoring: [])
    }
    
    func testAddingLocalizedFailureThenSerializing() async throws
    {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: URL(fileURLWithPath: "~/Users/rileytestut/delta")])
        let nsError = (error as NSError).withLocalizedFailure(.testOriginalLocalizedFailure)

        let receivedError = try self.send(nsError)
        let receivedNSError = receivedError.withLocalizedFailure(.testLocalizedFailure)

        let serializedError = receivedNSError.sanitizedForSerialization()

        // Failure == .testLocalizedFailure
        // Description == Failure + .testUnrecognizedFailureReason
        ALTAssertErrorFailureAndDescription(serializedError, failure: .testLocalizedFailure, baseDescription: try XCTUnwrap(nsError.localizedFailureReason))

        // Failure Reason == .testUnrecognizedFailureReason
        // Recovery Suggestion == .testUnrecognizedRecoverySuggestion
        ALTAssertErrorsEqual(serializedError, receivedNSError, ignoring: [])
    }
    
    func testSerializingUserInfoValues() async throws
    {
        let userInfo = [
            "RSTString": "test",
            "RSTNumber": -1 as Int,
            "RSTUnsignedNumber": 2 as UInt,
            // "RSTURL": URL(string: "https://rileytestut.com")!, // URLs get converted to Strings
            "RSTArray": [1, "test"],
            "RSTDictionary": ["key1": 11, "key2": "string"]
        ] as [String: Any]
                
        let error = NSError(domain: .testDomain, code: 17, userInfo: userInfo)

        let receivedError = try self.send(error)
        let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, error)
        
        let receivedUserInfo = receivedUnderlyingError.userInfo.filter { $0.key != NSLocalizedDescriptionKey } // Remove added NSLocalizedDescription value for unrecognized error.

//        let receivedURLString = try XCTUnwrap(receivedUserInfo["RSTURL"] as? String)
//        receivedUserInfo["RSTURL"] = URL(string: receivedURLString)
        
        XCTAssertEqual(receivedUserInfo as NSDictionary, userInfo as NSDictionary)
    }
    
    func testSerializingNonCodableUserInfoValues() async throws
    {
        struct MyStruct
        {
            var property = 1
        }
        
        let userInfo = [
            "MyStruct": MyStruct(),
            "RSTDictionary": ["key": MyStruct()],
            "RSTArray": [MyStruct()],
        ] as [String : Any]
                
        let error = NSError(domain: .testDomain, code: 17, userInfo: userInfo)

        let receivedError = try self.send(error)
        let receivedUnderlyingError = try ALTAssertUnderlyingErrorEqualsError(receivedError, error, ignoreExtraUserInfoValues: true)
        
        XCTAssertNil(receivedUnderlyingError.userInfo["MyStruct"])
        XCTAssertFalse(receivedUnderlyingError.userInfo.keys.contains("MyStruct"))
        
        let dictionary = try XCTUnwrap(receivedUnderlyingError.userInfo["RSTDictionary"] as? [String: Any])
        XCTAssertNil(dictionary["key"])
        XCTAssertFalse(dictionary.keys.contains("key"))
        
        let array = try XCTUnwrap(receivedUnderlyingError.userInfo["RSTArray"] as? [Any])
        XCTAssert(array.isEmpty)
    }
}
