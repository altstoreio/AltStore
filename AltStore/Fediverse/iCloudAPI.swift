//
//  iCloudAPI.swift
//  AltStore
//
//  Created by Riley Testut on 8/25/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import CloudKit

import AltStoreCore

final class iCloudAPI
{
    static let shared = iCloudAPI()
    
    private let container = CKContainer(identifier: "iCloud.io.altstore.AltStore.Sources")
    
    private init()
    {
    }
}

extension iCloudAPI
{
    func fetchSource(id: String) async throws -> SourceRecord?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(SourceFields.sourceID), id)
        let query = CKQuery(recordType: SourceRecord.recordType, predicate: predicate)
        
        let results = try await self._fetchRecords(of: SourceRecord.self, query: query)
        return results.first
    }
    
    func fetchNewsItems(@AsyncManaged for source: Source) async throws -> [NewsItemRecord]
    {
        let sourceID = await $source.identifier
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(NewsItemFields.sourceID), sourceID)
        let sortDescriptor = NSSortDescriptor(keyPath: \NewsItemFields.date, ascending: false)
        
        let query = CKQuery(recordType: NewsItemRecord.recordType, predicate: predicate)
        query.sortDescriptors = [sortDescriptor]
        
        let results = try await self._fetchRecords(of: NewsItemRecord.self, query: query)
        return results
    }
    
    func fetchApps(@AsyncManaged for source: Source) async throws -> [AppRecord]
    {
        let sourceID = await $source.identifier
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(AppFields.sourceID), sourceID)
        let sortDescriptor = NSSortDescriptor(keyPath: \AppFields.date, ascending: false)
        
        let query = CKQuery(recordType: AppRecord.recordType, predicate: predicate)
        query.sortDescriptors = [sortDescriptor]
        
        let results = try await self._fetchRecords(of: AppRecord.self, query: query)
        return results
    }
    
    func fetchAppVersions(@AsyncManaged for source: Source) async throws -> [AppVersionRecord]
    {
        let sourceID = await $source.identifier
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(AppVersionFields.sourceID), sourceID)
        let sortDescriptor = NSSortDescriptor(keyPath: \AppVersionFields.date, ascending: false)
        
        let query = CKQuery(recordType: AppVersionRecord.recordType, predicate: predicate)
        query.sortDescriptors = [sortDescriptor]
        
        let results = try await self._fetchRecords(of: AppVersionRecord.self, query: query)
        return results
    }
}

private extension iCloudAPI
{
    func _fetchRecords<Fields: CloudRecordFields>(of recordType: CloudRecord<Fields>.Type, query: CKQuery) async throws -> [CloudRecord<Fields>]
    {
        var results: [(CKRecord.ID, Result<CKRecord, Error>)] = []
        var fetchCursor: CKQueryOperation.Cursor? = nil
        
        repeat
        {
            let fetchResults: [(CKRecord.ID, Result<CKRecord, any Error>)]
            
            if let tempCursor = fetchCursor
            {
                let (results, cursor) = try await withCheckedThrowingContinuation { continuation in
                    self.container.publicCloudDatabase.fetch(withCursor: tempCursor) { result in
                        continuation.resume(with: result)
                    }
                }
                
                fetchResults = results
                fetchCursor = cursor
            }
            else
            {
                let (results, cursor) = try await withCheckedThrowingContinuation { continuation in
                    self.container.publicCloudDatabase.fetch(withQuery: query) { result in
                        continuation.resume(with: result)
                    }
                }
                
                fetchResults = results
                fetchCursor = cursor
            }
            
            for (recordID, result) in fetchResults
            {
                results.append((recordID, result))
            }
        } while (fetchCursor != nil);
        
        var records: [CloudRecord<Fields>] = []
        
        for (recordID, result) in results
        {
            do
            {
                let record = try result.get()
                
                let cloudRecord = CloudRecord<Fields>(record: record)
                records.append(cloudRecord)
            }
            catch
            {
                Logger.main.error("Failed to fetch \(Fields.recordType, privacy: .public) record \(recordID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return records
    }
}
