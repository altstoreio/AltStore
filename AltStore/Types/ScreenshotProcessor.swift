//
//  ScreenshotProcessor.swift
//  AltStore
//
//  Created by Riley Testut on 4/11/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import AltStoreCore

import Nuke

struct ScreenshotProcessor: ImageProcessing
{
    var identifier: String { "io.altstore.ScreenshotProcessor" }
    
    @Managed
    var screenshot: AppScreenshot?
    
    var traits: UITraitCollection?
    
    func process(_ image: PlatformImage) -> PlatformImage?
    {
        guard let cgImage = image.cgImage, image.size.width > image.size.height else { return image }
        
        let rotatedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .right)
        return rotatedImage
    }
    
    func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer? 
    {
        if let screenshot
        {
            guard let traits else { return container }
            
            let (size, deviceType) = $screenshot.perform { _ in (screenshot.size, screenshot.deviceType) }
            guard let aspectRatio = size, aspectRatio.width > aspectRatio.height else { return container }
                    
            var shouldRotate = false
            
            switch deviceType
            {
            case .iphone:
                // Always rotate landscape iPhone screenshots regardless of horizontal size class.
                shouldRotate = true
                
            case .ipad where traits.horizontalSizeClass == .compact:
                // Only rotate landscape iPad screenshots if we're in horizontally compact environment.
                shouldRotate = true
                
            default: break
            }
            
            guard shouldRotate else { return container}
            
            let container = container.map { image in
                guard let cgImage = image.cgImage else { return image }
                
                let rotatedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .right)
                return rotatedImage
            }
            
            return container
        }
        else
        {
            guard let cgImage = container.image.cgImage, container.image.size.width > container.image.size.height else { return container }
            
            let rotatedImage = UIImage(cgImage: cgImage, scale: container.image.scale, orientation: .right)
            return container.map { _ in rotatedImage }
        }
    }
}

extension ImageProcessing where Self == ScreenshotProcessor
{
    static func screenshot(_ screenshot: AppScreenshot?, traits: UITraitCollection?) -> Self
    {
        let processor = ScreenshotProcessor(screenshot: screenshot, traits: traits)
        return processor
    }
}
