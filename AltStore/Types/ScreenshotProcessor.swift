//
//  ScreenshotProcessor.swift
//  AltStore
//
//  Created by Riley Testut on 4/11/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Nuke

struct ScreenshotProcessor: ImageProcessing
{
    func process(image: Image, context: ImageProcessingContext) -> Image?
    {
        guard let cgImage = image.cgImage, image.size.width > image.size.height else { return image }
        
        let rotatedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .right)
        return rotatedImage
    }
}

extension ImageProcessing where Self == ScreenshotProcessor
{
    static var screenshot: Self { Self() }
}
