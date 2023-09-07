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
    }
    
    static func processNotRunning(_ process: AppProcess, file: StaticString = #file, line: Int = #line) -> JITError {
        JITError(code: .processNotRunning, process: process, sourceFile: file, sourceLine: UInt(line))
    }
}

struct JITError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue var process: AppProcess?
    
    var sourceFile: StaticString?
    var sourceLine: UInt?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .processNotRunning:
            let targetName = self.process?.description ?? NSLocalizedString("The target app", comment: "")
            return String(format: NSLocalizedString("%@ is not running.", comment: ""), targetName)
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .processNotRunning: return NSLocalizedString("Make sure the app is running in the foreground on your device then try again.", comment: "")
        }
    }
}
