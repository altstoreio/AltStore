//
//  FetchAppsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/17/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

@objc(FetchAppsOperation)
class FetchAppsOperation: ResultOperation<[App]>
{
    private let session = URLSession(configuration: .default)
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter
    }()
    
    override func main()
    {
        super.main()
        
        let appsURL = URL(string: "https://www.dropbox.com/s/6qi1vt6hsi88lv6/Apps-Dev.json?dl=1")!
        
        let dataTask = self.session.dataTask(with: appsURL) { (data, response, error) in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                do
                {
                    let (data, _) = try Result((data, response), error).get()
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(self.dateFormatter)
                    decoder.managedObjectContext = context
                    
                    let apps = try decoder.decode([App].self, from: data)
                    self.finish(.success(apps))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
        
        self.progress.addChild(dataTask.progress, withPendingUnitCount: 1)
        
        dataTask.resume()
    }
}
