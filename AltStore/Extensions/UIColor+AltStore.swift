//
//  UIColor+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

extension UIColor
{
    static let altBackground = UIColor(named: "Background")!
}

extension UIColor
{
//    private static let vibrancyView = UIVisualEffectView(effect: tintColorVibrancyEffect)
//    private static let tintColorVibrancyEffect = UIVibrancyEffect(blurEffect: .init(style: .systemChromeMaterialLight),
//                                                                  style: .secondaryLabel)
//    
//    private static var resolvedTintColors: [UIColor: UIColor] = [:]
    
    private static let brightnessMaxThreshold = 0.85
    private static let brightnessMinThreshold = 0.35
    
    private static let saturationBrightnessThreshold = 0.5
    
    var adjustedForDisplay: UIColor {
        guard self.isTooBright || self.isTooDark else { return self }
        
        return UIColor { traits in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            guard self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else { return self }
            
            brightness = min(brightness, UIColor.brightnessMaxThreshold)
            
            if traits.userInterfaceStyle == .dark
            {
                // Only raise brightness when in dark mode
                brightness = max(brightness, UIColor.brightnessMinThreshold)
            }
            
            let color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
            return color
        }
    }
    
    var isTooBright: Bool {
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        
        guard self.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil) else { return false }
        
        let isTooBright = (brightness >= UIColor.brightnessMaxThreshold && saturation <= UIColor.saturationBrightnessThreshold)
        return isTooBright
    }
    
    var isTooDark: Bool {
        var brightness: CGFloat = 0
        guard self.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil) else { return false }
                
        let isTooDark = brightness <= UIColor.brightnessMinThreshold
        return isTooDark
    }
    
//    class func dynamicTintColor2(_ tintColor: UIColor) -> UIColor
//    {
//        let color = UIColor { traitCollection in
//            if let resolvedColor = resolvedTintColors[tintColor]
//            {
//                return resolvedColor
//            }
//            
//            let vibrancyView = UIVisualEffectView(effect: tintColorVibrancyEffect)
//            vibrancyView.contentView.backgroundColor = .white.withAlphaComponent(0.5)
//            vibrancyView.backgroundColor = tintColor
//            vibrancyView.setNeedsLayout()
//            vibrancyView.layoutIfNeeded()
//            
//            let format = UIGraphicsImageRendererFormat()
//            format.scale = 1.0
//            format.opaque = true
//            format.preferredRange = .standard
//            
//            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
//            let image = renderer.image { ctx in
//                vibrancyView.drawHierarchy(in: CGRect(x: 0, y: 0, width: 1, height: 1), afterScreenUpdates: false)
//            }
//            
//            let resolvedColor = image.pixelColor(x: 0, y: 0)
//            resolvedTintColors[tintColor] = resolvedColor
//            
//            print("[RSTLog] Resolved color \(resolvedColor.hexString) from \(tintColor.hexString)")
//            
//            return resolvedColor
//        }
//        
//        return color
//    }
}

public extension UIImage {

    var pixelWidth: Int {
        return cgImage?.width ?? 0
    }

    var pixelHeight: Int {
        return cgImage?.height ?? 0
    }

    func pixelColor(x: Int, y: Int) -> UIColor {
        assert(
            0..<pixelWidth ~= x && 0..<pixelHeight ~= y,
            "Pixel coordinates are out of bounds")

        guard
            let cgImage = cgImage,
            let data = cgImage.dataProvider?.data,
            let dataPtr = CFDataGetBytePtr(data),
            let colorSpaceModel = cgImage.colorSpace?.model,
            let componentLayout = cgImage.bitmapInfo.componentLayout
        else {
            assertionFailure("Could not get the color of a pixel in an image")
            return .clear
        }

        assert(
            colorSpaceModel == .rgb,
            "The only supported color space model is RGB")
        assert(
            cgImage.bitsPerPixel == 32 || cgImage.bitsPerPixel == 24,
            "A pixel is expected to be either 4 or 3 bytes in size")

        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel/8
        let pixelOffset = y*bytesPerRow + x*bytesPerPixel

        if componentLayout.count == 4 {
            let components = (
                dataPtr[pixelOffset + 0],
                dataPtr[pixelOffset + 1],
                dataPtr[pixelOffset + 2],
                dataPtr[pixelOffset + 3]
            )

            var alpha: UInt8 = 0
            var red: UInt8 = 0
            var green: UInt8 = 0
            var blue: UInt8 = 0

            switch componentLayout {
            case .bgra:
                alpha = components.3
                red = components.2
                green = components.1
                blue = components.0
            case .abgr:
                alpha = components.0
                red = components.3
                green = components.2
                blue = components.1
            case .argb:
                alpha = components.0
                red = components.1
                green = components.2
                blue = components.3
            case .rgba:
                alpha = components.3
                red = components.0
                green = components.1
                blue = components.2
            default:
                return .clear
            }

            // If chroma components are premultiplied by alpha and the alpha is `0`,
            // keep the chroma components to their current values.
            if cgImage.bitmapInfo.chromaIsPremultipliedByAlpha && alpha != 0 {
                let invUnitAlpha = 255/CGFloat(alpha)
                red = UInt8((CGFloat(red)*invUnitAlpha).rounded())
                green = UInt8((CGFloat(green)*invUnitAlpha).rounded())
                blue = UInt8((CGFloat(blue)*invUnitAlpha).rounded())
            }

            return .init(red: red, green: green, blue: blue, alpha: alpha)

        } else if componentLayout.count == 3 {
            let components = (
                dataPtr[pixelOffset + 0],
                dataPtr[pixelOffset + 1],
                dataPtr[pixelOffset + 2]
            )

            var red: UInt8 = 0
            var green: UInt8 = 0
            var blue: UInt8 = 0

            switch componentLayout {
            case .bgr:
                red = components.2
                green = components.1
                blue = components.0
            case .rgb:
                red = components.0
                green = components.1
                blue = components.2
            default:
                return .clear
            }

            return .init(red: red, green: green, blue: blue, alpha: UInt8(255))

        } else {
            assertionFailure("Unsupported number of pixel components")
            return .clear
        }
    }

}

public extension UIColor {

    convenience init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.init(
            red: CGFloat(red)/255,
            green: CGFloat(green)/255,
            blue: CGFloat(blue)/255,
            alpha: CGFloat(alpha)/255)
    }

}

public extension CGBitmapInfo {

    enum ComponentLayout {

        case bgra
        case abgr
        case argb
        case rgba
        case bgr
        case rgb

        var count: Int {
            switch self {
            case .bgr, .rgb: return 3
            default: return 4
            }
        }

    }

    var componentLayout: ComponentLayout? {
        guard let alphaInfo = CGImageAlphaInfo(rawValue: rawValue & Self.alphaInfoMask.rawValue) else { return nil }
        let isLittleEndian = contains(.byteOrder32Little)

        if alphaInfo == .none {
            return isLittleEndian ? .bgr : .rgb
        }
        let alphaIsFirst = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst

        if isLittleEndian {
            return alphaIsFirst ? .bgra : .abgr
        } else {
            return alphaIsFirst ? .argb : .rgba
        }
    }

    var chromaIsPremultipliedByAlpha: Bool {
        let alphaInfo = CGImageAlphaInfo(rawValue: rawValue & Self.alphaInfoMask.rawValue)
        return alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
    }

}
