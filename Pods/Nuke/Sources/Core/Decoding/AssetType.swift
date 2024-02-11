// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A uniform type identifier (UTI).
public struct AssetType: ExpressibleByStringLiteral, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let png: AssetType = "public.png"
    public static let jpeg: AssetType = "public.jpeg"
    public static let gif: AssetType = "com.compuserve.gif"
    /// HEIF (High Efficiency Image Format) by Apple.
    public static let heic: AssetType = "public.heic"

    /// WebP
    ///
    /// Native decoding support only available on the following platforms: macOS 11,
    /// iOS 14, watchOS 7, tvOS 14.
    public static let webp: AssetType = "public.webp"

    public static let mp4: AssetType = "public.mpeg4"
    
    /// The M4V file format is a video container format developed by Apple and
    /// is very similar to the MP4 format. The primary difference is that M4V
    /// files may optionally be protected by DRM copy protection.
    public static let m4v: AssetType = "public.m4v"
    
    public var isVideo: Bool {
        self == .mp4 || self == .m4v
    }
}

public extension AssetType {
    /// Determines a type of the image based on the given data.
    init?(_ data: Data) {
        guard let type = AssetType.make(data) else {
            return nil
        }
        self = type
    }

    private static func make(_ data: Data) -> AssetType? {
        func _match(_ numbers: [UInt8?], offset: Int = 0) -> Bool {
            guard data.count >= numbers.count else {
                return false
            }
            return zip(numbers.indices, numbers).allSatisfy { index, number in
                guard let number = number else { return true }
                guard (index + offset) < data.count else { return false }
                return data[index + offset] == number
            }
        }

        // JPEG magic numbers https://en.wikipedia.org/wiki/JPEG
        if _match([0xFF, 0xD8, 0xFF]) { return .jpeg }

        // PNG Magic numbers https://en.wikipedia.org/wiki/Portable_Network_Graphics
        if _match([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }

        // GIF magic numbers https://en.wikipedia.org/wiki/GIF
        if _match([0x47, 0x49, 0x46]) { return .gif }

        // WebP magic numbers https://en.wikipedia.org/wiki/List_of_file_signatures
        if _match([0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x45, 0x42, 0x50]) { return .webp }

        // TODO: Extend support to other video formats supported by the system
        // see https://stackoverflow.com/questions/21879981/avfoundation-avplayer-supported-formats-no-vob-or-mpg-containers
        // https://en.wikipedia.org/wiki/List_of_file_signatures
        if _match([0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D], offset: 4) { return .mp4 }
        
        if _match([0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32], offset: 4) { return .m4v }
        
        // Either not enough data, or we just don't support this format.
        return nil
    }
}
