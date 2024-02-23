//
//  InstalledApp+LoadIcon.swift
//  AltStore
//
//  Created by Riley Testut on 1/29/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import AltStoreCore

import Nuke

extension InstalledApp
{
    func loadIcon(completion: @escaping (Result<UIImage?, Error>) -> Void)
    {
        #if MARKETPLACE
        
        //TODO: Handle apps without sources/storeApps
        
        guard let storeApp = self.storeApp else {
            //TODO: Replace with better error
            return completion(.failure(CocoaError(.fileNoSuchFile)))
        }
        
        ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { result in
            switch result
            {
            case .success(let response): completion(.success(response.image))
            case .failure(let error): completion(.failure(error))
            }
        }
        
        #else
        
        if self.bundleIdentifier == StoreApp.altstoreAppID, let iconName = UIApplication.alt_shared?.alternateIconName
        {
            // Use alternate app icon for AltStore, if one is chosen.
            
            let image = UIImage(named: iconName)
            completion(.success(image))
            
            return
        }
        
        let hasAlternateIcon = self.hasAlternateIcon
        let alternateIconURL = self.alternateIconURL
        let fileURL = self.fileURL
        
        DispatchQueue.global().async {
            do
            {
                if hasAlternateIcon,
                   case let data = try Data(contentsOf: alternateIconURL),
                   let icon = UIImage(data: data)
                {
                    return completion(.success(icon))
                }
                
                let application = ALTApplication(fileURL: fileURL)
                completion(.success(application?.icon))
            }
            catch
            {
                completion(.failure(error))
            }
        }
        
        #endif
    }
}
