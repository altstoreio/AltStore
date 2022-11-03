//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine
import minimuxer

import AltStoreCore

@available(iOS 14, *)
protocol EnableJITContext
{
    var installedApp: InstalledApp? { get }
    
    var error: Error? { get }
}

@available(iOS 14, *)
class EnableJITOperation<Context: EnableJITContext>: ResultOperation<Void>
{
    let context: Context
    
    private var cancellable: AnyCancellable?
    
    init(context: Context)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        installedApp.managedObjectContext?.perform {
            let v = minimuxer_to_operation(code: 1)
                        
            do {
                var x = try debug_app(app_id: installedApp.resignedBundleIdentifier)
                switch x {
                case .Good:
                    self.finish(.success(()))
                case .Bad(let code):
                    self.finish(.failure(minimuxer_to_operation(code: code)))
                }
            } catch Uhoh.Bad(let code) {
                self.finish(.failure(minimuxer_to_operation(code: code)))
            } catch {
                self.finish(.failure(OperationError.unknown))
            }
            
            
        }
    }
}
