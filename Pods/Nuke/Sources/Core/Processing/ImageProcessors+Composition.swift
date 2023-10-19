// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageProcessors {
    /// Composes multiple processors.
    public struct Composition: ImageProcessing, Hashable, CustomStringConvertible {
        let processors: [ImageProcessing]

        /// Composes multiple processors.
        public init(_ processors: [ImageProcessing]) {
            // note: multiple compositions are not flatten by default.
            self.processors = processors
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            processors.reduce(image) { image, processor in
                autoreleasepool {
                    image.flatMap { processor.process($0) }
                }
            }
        }

        /// Processes the given image by applying each processor in an order in
        /// which they were added. If one of the processors fails to produce
        /// an image the processing stops and `nil` is returned.
        public func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer? {
            processors.reduce(container) { container, processor in
                autoreleasepool {
                    container.flatMap { processor.process($0, context: context) }
                }
            }
        }

        public var identifier: String {
            processors.map({ $0.identifier }).joined()
        }

        public var hashableIdentifier: AnyHashable { self }

        public func hash(into hasher: inout Hasher) {
            for processor in processors {
                hasher.combine(processor.hashableIdentifier)
            }
        }

        public static func == (lhs: Composition, rhs: Composition) -> Bool {
            lhs.processors == rhs.processors
        }

        public var description: String {
            "Composition(processors: \(processors))"
        }
    }
}
