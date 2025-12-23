//
//  iCloudAPI+Types.swift
//  AltStore
//
//  Created by Riley Testut on 8/25/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import CloudKit

protocol CloudRecordFields: Codable
{
    static var recordType: CKRecord.RecordType { get }
}

extension iCloudAPI
{
    @dynamicMemberLookup
    struct CloudRecord<Fields: CloudRecordFields>: Identifiable
    {
        static var recordType: CKRecord.RecordType { Fields.recordType }
        var id: CKRecord.ID { self.record.recordID }
        
        private let record: CKRecord
        
        subscript<T>(dynamicMember keyPath: KeyPath<Fields, T>) -> T
        {
            let stringValue = keyPath._kvcKeyPathString!
            
            let value = self.record[stringValue] as! T
            return value
        }
        
        init(record: CKRecord)
        {
            self.record = record
        }
    }

    typealias SourceRecord = CloudRecord<SourceFields>
    typealias NewsItemRecord = CloudRecord<NewsItemFields>
    typealias AppRecord = CloudRecord<AppFields>
    typealias AppVersionRecord = CloudRecord<AppVersionFields>

    @objcMembers
    class SourceFields: CloudRecordFields
    {
        static var recordType: CKRecord.RecordType { "Source" }
        
        var sourceID: String
        var url: URL
        var username: String
    }
    
    @objcMembers
    class AppFields: CloudRecordFields
    {
        static var recordType: CKRecord.RecordType { "App" }
        
        var bundleID: String
        var sourceID: String
        var date: Date
        var statusID: String?
    }

    @objcMembers
    class NewsItemFields: CloudRecordFields
    {
        static var recordType: CKRecord.RecordType { "NewsItem" }
        
        var identifier: String
        var sourceID: String
        var date: Date
        var statusID: String?
    }

    @objcMembers
    class AppVersionFields: CloudRecordFields
    {
        static var recordType: String { "AppVersion" }
        
        var date: Date
        var versionID: String
        
        var sourceID: String
        var appBundleID: String
        
        var statusID: String?
    }
}

extension iCloudAPI.CloudRecord where Fields == iCloudAPI.AppVersionFields
{
    var globallyUniqueID: String {
        let globallyUniqueID = self.versionID + "|" + self.appBundleID + "|" + self.sourceID
        return globallyUniqueID
    }
}
