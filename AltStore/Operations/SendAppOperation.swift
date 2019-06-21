//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit

@objc(SendAppOperation)
class SendAppOperation: ResultOperation<NWConnection>
{
    let context: AppOperationContext
    
    private let dispatchQueue = DispatchQueue(label: "com.altstore.SendAppOperation")
    
    private var connection: NWConnection?
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let fileURL = self.context.resignedFileURL, let server = self.context.group.server else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // Connect to server.
        self.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let connection):
                self.connection = connection
                
                // Send app to server.
                self.sendApp(at: fileURL, via: connection, server: server) { (result) in
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success:
                        self.progress.completedUnitCount += 1
                        self.finish(.success(connection))
                    }
                }
            }
        }
    }
}

private extension SendAppOperation
{
    func connect(to server: Server, completionHandler: @escaping (Result<NWConnection, Error>) -> Void)
    {
        let connection = NWConnection(to: .service(name: server.service.name, type: server.service.type, domain: server.service.domain, interface: nil), using: .tcp)
        
        connection.stateUpdateHandler = { [unowned connection] (state) in
            switch state
            {
            case .failed(let error):
                print("Failed to connect to service \(server.service.name).", error)
                completionHandler(.failure(ConnectionError.connectionFailed))
               
            case .cancelled:
                completionHandler(.failure(OperationError.cancelled))
                
            case .ready:
                completionHandler(.success(connection))
            
            case .waiting: break
            case .setup: break
            case .preparing: break
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func sendApp(at fileURL: URL, via connection: NWConnection, server: Server, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            guard let appData = try? Data(contentsOf: fileURL) else { throw OperationError.invalidApp }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
            
            let request = PrepareAppRequest(udid: udid, contentSize: appData.count)
            
            print("Sending request \(request)")
            server.send(request, via: connection) { (result) in
                switch result
                {
                case .failure(let error): completionHandler(.failure(error))
                case .success:
                    
                    print("Sending app data (\(appData.count) bytes)")
                    server.send(appData, via: connection, prependSize: false) { (result) in
                        switch result
                        {
                        case .failure(let error): completionHandler(.failure(error))
                        case .success: completionHandler(.success(()))
                        }
                    }
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
}
