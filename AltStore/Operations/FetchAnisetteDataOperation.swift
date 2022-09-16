//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>
{
    let context: OperationContext
    
    init(context: OperationContext)
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
        
        let urlString = UserDefaults.standard.string(forKey: "customAnisetteURL") ?? "https://sideloadly.io/anisette/irGb3Quww8zrhgqnzmrx"
        guard let url = URL(string: urlString) else { return }

           let task = URLSession.shared.dataTask(with: url) { data, response, error in

               guard let data = data, error == nil else { return }

               do {
                   // make sure this JSON is in the format we expect
                   // convert data to json
                   if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                       // try to read out a dictionary
                           //for some reason serial number isn't needed but it doesn't work unless it has a value
                       let formattedJSON: [String: String] = ["machineID": json["X-Apple-I-MD-M"]!, "oneTimePassword": json["X-Apple-I-MD"]!, "localUserID": json["X-Apple-I-MD-LU"]!, "routingInfo": json["X-Apple-I-MD-RINFO"]!, "deviceUniqueIdentifier": json["X-Mme-Device-Id"]!, "deviceDescription": json["X-MMe-Client-Info"]!, "date": json["X-Apple-I-Client-Time"]!, "locale": json["X-Apple-Locale"]!, "timeZone": json["X-Apple-I-TimeZone"]!, "deviceSerialNumber": "1"]
                       
                       if let anisette = ALTAnisetteData(json: formattedJSON) {
                           self.finish(.success(anisette))
                       }
                   }
               } catch let error as NSError {
                   print("Failed to load: \(error.localizedDescription)")
                   self.finish(.failure(error))
               }

           }

           task.resume()

    }
}
