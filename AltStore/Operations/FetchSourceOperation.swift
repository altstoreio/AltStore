//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    
    private let session = URLSession(configuration: .default)
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter
    }()
    
    init(sourceURL: URL)
    {
        self.sourceURL = sourceURL
    }
    
    override func main()
    {
        super.main()
        
        let dataTask = self.session.dataTask(with: self.sourceURL) { (data, response, error) in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                do
                {
                    let (data, _) = try Result((data, response), error).get()
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(self.dateFormatter)
                    decoder.managedObjectContext = context
                    
                    let source = try decoder.decode(Source.self, from: data)
                    self.finish(.success(source))
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
