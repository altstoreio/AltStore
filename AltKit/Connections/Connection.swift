//
//  Connection.swift
//  AltKit
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

public extension Connection
{
    func send(_ data: Data, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        self.__send(data) { (success, error) in
            let result = Result(success, error).mapError { (error) -> ALTServerError in
                guard let nwError = error as? NWError else { return ALTServerError(error) }
                return ALTServerError(.lostConnection, underlyingError: nwError)
            }
            
            completionHandler(result)
        }
    }
    
    func receiveData(expectedSize: Int, completionHandler: @escaping (Result<Data, ALTServerError>) -> Void)
    {
        self.__receiveData(expectedSize: expectedSize) { (data, error) in
            let result = Result(data, error).mapError { (error) -> ALTServerError in
                guard let nwError = error as? NWError else { return ALTServerError(error) }
                return ALTServerError(.lostConnection, underlyingError: nwError)
            }
            
            completionHandler(result)
        }
    }
    
    func send<T: Encodable>(_ response: T, shouldDisconnect: Bool = false, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        func finish(_ result: Result<Void, ALTServerError>)
        {
            completionHandler(result)
            
            if shouldDisconnect
            {
                // Add short delay to prevent us from dropping connection too quickly.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    self.disconnect()
                }
            }
        }
        
        do
        {
            let data = try JSONEncoder().encode(response)
            let responseSize = withUnsafeBytes(of: Int32(data.count)) { Data($0) }
            
            self.send(responseSize) { (result) in
                switch result
                {
                case .failure(let error): finish(.failure(error))
                case .success:
                    self.send(data) { (result) in
                        switch result
                        {
                        case .failure(let error): finish(.failure(error))
                        case .success: finish(.success(()))
                        }
                    }
                }
            }
        }
        catch
        {
            finish(.failure(.init(.invalidResponse, underlyingError: error)))
        }
    }
    
    func receiveRequest(completionHandler: @escaping (Result<ServerRequest, ALTServerError>) -> Void)
    {
        let size = MemoryLayout<Int32>.size
        
        print("Receiving request size from connection:", self)
        self.receiveData(expectedSize: size) { (result) in
            do
            {
                let data = try result.get()
                
                let expectedSize = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                print("Receiving request from connection: \(self)... (\(expectedSize) bytes)")
                
                self.receiveData(expectedSize: expectedSize) { (result) in
                    do
                    {
                        let data = try result.get()
                        let request = try JSONDecoder().decode(ServerRequest.self, from: data)
                        
                        print("Received request:", request)
                        completionHandler(.success(request))
                    }
                    catch
                    {
                        completionHandler(.failure(ALTServerError(error)))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
}
