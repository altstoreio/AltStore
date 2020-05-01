//
//  JSONDecoder+Properties.swift
//  Harmony
//
//  Created by Riley Testut on 10/3/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

extension CodingUserInfoKey
{
    static let managedObjectContext = CodingUserInfoKey(rawValue: "managedObjectContext")!
    static let sourceURL = CodingUserInfoKey(rawValue: "sourceURL")!
}

public final class JSONDecoder: Foundation.JSONDecoder
{
    @DecoderItem(key: .managedObjectContext)
    var managedObjectContext: NSManagedObjectContext?
    
    @DecoderItem(key: .sourceURL)
    var sourceURL: URL?
}

extension Decoder
{
    var managedObjectContext: NSManagedObjectContext? { self.userInfo[.managedObjectContext] as? NSManagedObjectContext }
    var sourceURL: URL? { self.userInfo[.sourceURL] as? URL }
}

@propertyWrapper
struct DecoderItem<Value>
{
    let key: CodingUserInfoKey
    
    var wrappedValue: Value? {
        get { fatalError("only works on instance properties of classes") }
        set { fatalError("only works on instance properties of classes") }
    }
    
    init(key: CodingUserInfoKey)
    {
        self.key = key
    }
    
    public static subscript<OuterSelf: JSONDecoder>(
        _enclosingInstance decoder: OuterSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<OuterSelf, Value?>,
        storage storageKeyPath: ReferenceWritableKeyPath<OuterSelf, Self>
    ) -> Value? {
        get {
            let wrapper = decoder[keyPath: storageKeyPath]

            let value = decoder.userInfo[wrapper.key] as? Value
            return value
        }
        set {
            let wrapper = decoder[keyPath: storageKeyPath]
            decoder.userInfo[wrapper.key] = newValue
        }
    }
}
