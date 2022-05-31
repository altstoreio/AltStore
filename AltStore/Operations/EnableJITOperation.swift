//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore

@available(iOS 14, *)
protocol EnableJITContext
{
    var server: Server? { get }
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
        
        guard let server = self.context.server, let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { return self.finish(.failure(OperationError.unknownUDID)) }
        
        installedApp.managedObjectContext?.perform {
            guard let bundle = Bundle(url: installedApp.fileURL),
                  let processName = bundle.executableURL?.lastPathComponent
            else { return self.finish(.failure(OperationError.invalidApp)) }
            
            let appName = installedApp.name
            let openAppURL = installedApp.openAppURL
            
            ServerManager.shared.connect(to: server) { result in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success(let connection):
                    print("Sending enable JIT request...")
                    
                    DispatchQueue.main.async {
                        
                        // Launch app to make sure it is running in foreground.
                        UIApplication.shared.open(openAppURL) { success in
                            guard success else { return self.finish(.failure(OperationError.openAppFailed(name: appName))) }
                            
                            // Combine immediately finishes if an error is thrown, but we want to wait at least until app enters background.
                            // As a workaround, we set error type to Never and use Result<Void, Error> as the value type instead.
                            let result = Future<Result<Void, Error>, Never> { promise in
                                let request = EnableUnsignedCodeExecutionRequest(udid: udid, processName: processName)
                                connection.send(request) { result in
                                    print("Sent enable JIT request!")
                                    
                                    switch result
                                    {
                                    case .failure(let error): promise(.success(.failure(error)))
                                    case .success:
                                        print("Waiting for enable JIT response...")
                                        connection.receiveResponse() { result in
                                            print("Received enable JIT response:", result)
                                            
                                            switch result
                                            {
                                            case .failure(let error): promise(.success(.failure(error)))
                                            case .success(.error(let response)): promise(.success(.failure(response.error)))
                                            case .success(.enableUnsignedCodeExecution): promise(.success(.success(())))
                                            case .success: promise(.success(.failure(ALTServerError(.unknownResponse))))
                                            }
                                        }
                                    }
                                }
                            }
                            
                            //TODO: Handle case where app does not enter background (e.g. iPad multitasking).
                            self.cancellable = result
                                .combineLatest(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification, object: nil))
                                .first()
                                .receive(on: DispatchQueue.main)
                                .sink { (result, _) in
                                    let content = UNMutableNotificationContent()
                                    
                                    switch result
                                    {
                                    case .failure(let error):
                                        content.title = String(format: NSLocalizedString("Could not enable JIT for %@", comment: ""), appName)
                                        content.body = error.localizedDescription

                                        UIDevice.current.vibrate(pattern: .error)
                                        
                                    case .success:
                                        content.title = String(format: NSLocalizedString("Enabled JIT for %@", comment: ""), appName)
                                        content.body = String(format: NSLocalizedString("JIT will remain enabled until you quit the app.", comment: ""))
                                        
                                        UIDevice.current.vibrate(pattern: .success)
                                    }
                                    
                                    if UIApplication.shared.applicationState == .background
                                    {
                                        // For some reason, notification won't show up reliably unless we provide a trigger (as of iOS 15).
                                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                                        
                                        let request = UNNotificationRequest(identifier: AppManager.enableJITResultNotificationID, content: content, trigger: trigger)
                                        UNUserNotificationCenter.current().add(request)
                                    }
                                    
                                    self.finish(result)
                                }
                        }
                    }
                }
            }
        }
    }
}
