//
//  JITError.swift
//  AltJIT
//
//  Created by Riley Testut on 9/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

extension JITError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = JITError
        
        case processNotRunning
        case dependencyNotFound
    }
    
    static func processNotRunning(_ process: AppProcess, file: StaticString = #file, line: Int = #line) -> JITError {
        JITError(code: .processNotRunning, process: process, sourceFile: file, sourceLine: UInt(line))
    }
    
    static func dependencyNotFound(_ dependency: String?, file: StaticString = #file, line: Int = #line) -> JITError {
        let errorFailure = NSLocalizedString("AltServer requires additional dependencies to enable JIT on iOS 17.", comment: "")
        return JITError(code: .dependencyNotFound, errorFailure: errorFailure, dependency: dependency, faq: "https://faq.altstore.io/how-to-use-altstore/altjit", sourceFile: file, sourceLine: UInt(line))
    }
}

struct JITError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue var process: AppProcess?
    
    @UserInfoValue var dependency: String?
    @UserInfoValue var faq: String? // Show user FAQ URL in AltStore error log.
    
    var sourceFile: StaticString?
    var sourceLine: UInt?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .processNotRunning:
            let targetName = self.process?.description ?? NSLocalizedString("The target app", comment: "")
            return String(format: NSLocalizedString("%@ is not running.", comment: ""), targetName)
            
        case .dependencyNotFound:
            let dependencyName = self.dependency.map { "'\($0)'" } ?? NSLocalizedString("A required dependency", comment: "")
            return String(format: NSLocalizedString("%@ is not installed.", comment: ""), dependencyName)
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .processNotRunning: return NSLocalizedString("Make sure the app is running in the foreground on your device then try again.", comment: "")
        case .dependencyNotFound: return NSLocalizedString("Please follow the instructions on the AltStore FAQ to install all required dependencies, then try again.", comment: "")
        }
    }
}
