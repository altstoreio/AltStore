//
//  AppPermission.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import UIKit

public extension ALTAppPermissionType
{
    var localizedShortName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .backgroundAudio: return NSLocalizedString("Audio (BG)", comment: "")
        case .backgroundFetch: return NSLocalizedString("Fetch (BG)", comment: "")
        default: return nil
        }
    }
    
    var localizedName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .camera: return NSLocalizedString("Camera", comment: "")
        case .location: return NSLocalizedString("Location", comment: "")
        case .contacts: return NSLocalizedString("Contacts", comment: "")
        case .reminders: return NSLocalizedString("Reminders", comment: "")
        case .appleMusic: return NSLocalizedString("Apple Music", comment: "")
        case .microphone: return NSLocalizedString("Microphone", comment: "")
        case .speechRecognition: return NSLocalizedString("Speech Recognition", comment: "")
        case .backgroundAudio: return NSLocalizedString("Background Audio", comment: "")
        case .backgroundFetch: return NSLocalizedString("Background Fetch", comment: "")
        case .bluetooth: return NSLocalizedString("Bluetooth", comment: "")
        case .network: return NSLocalizedString("Network", comment: "")
        case .calendars: return NSLocalizedString("Calendars", comment: "")
        case .touchID: return NSLocalizedString("Touch ID", comment: "")
        case .faceID: return NSLocalizedString("Face ID", comment: "")
        case .siri: return NSLocalizedString("Siri", comment: "")
        case .motion: return NSLocalizedString("Motion", comment: "")
        default: return nil
        }
    }
    
    var icon: UIImage? {
        switch self
        {
        case .photos: return UIImage(systemName: "photo.on.rectangle.angled")
        case .camera: return UIImage(systemName: "camera.fill")
        case .location: return UIImage(systemName: "location.fill")
        case .contacts: return UIImage(systemName: "person.2.fill")
        case .reminders: return UIImage(systemName: "checklist")
        case .appleMusic: return UIImage(systemName: "music.note")
        case .microphone: return UIImage(systemName: "mic.fill")
        case .speechRecognition: return UIImage(systemName: "waveform.and.mic")
        case .backgroundAudio: return UIImage(systemName: "speaker.fill")
        case .backgroundFetch: return UIImage(systemName: "square.and.arrow.down")
        case .bluetooth: return UIImage(systemName: "wave.3.right")
        case .network: return UIImage(systemName: "network")
        case .calendars: return UIImage(systemName: "calendar")
        case .touchID: return UIImage(systemName: "touchid")
        case .faceID: return UIImage(systemName: "faceid")
        case .siri: return UIImage(systemName: "mic.and.signal.meter.fill")
        case .motion: return UIImage(systemName: "figure.walk.motion")
        default:
            return nil
        }
    }
}

@objc(AppPermission)
public class AppPermission: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public var type: ALTAppPermissionType
    @NSManaged public var usageDescription: String
    
    /* Relationships */
    @NSManaged public private(set) var app: StoreApp!
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case type
        case usageDescription
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppPermission.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.usageDescription = try container.decode(String.self, forKey: .usageDescription)
            
            let rawType = try container.decode(String.self, forKey: .type)
            self.type = ALTAppPermissionType(rawValue: rawType)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

public extension AppPermission
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppPermission>
    {
        return NSFetchRequest<AppPermission>(entityName: "AppPermission")
    }
}
