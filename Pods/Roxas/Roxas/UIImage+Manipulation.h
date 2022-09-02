//
//  UIImage+Manipulation.h
//  Hoot
//
//  Created by Riley Testut on 9/23/14.
//  Copyright (c) 2014 TMT. All rights reserved.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UIImageMetadataOrientation)
{
    UIImageMetadataOrientationUp               = 1,
    UIImageMetadataOrientationDown             = 3,
    UIImageMetadataOrientationLeft             = 8,
    UIImageMetadataOrientationRight            = 6,
    UIImageMetadataOrientationUpMirrored       = 2,
    UIImageMetadataOrientationDownMirrored     = 4,
    UIImageMetadataOrientationLeftMirrored     = 5,
    UIImageMetadataOrientationRightMirrored    = 7,
};

RST_EXTERN UIImageMetadataOrientation UIImageMetadataOrientationFromImageOrientation(UIImageOrientation imageOrientation);
RST_EXTERN UIImageOrientation UIImageOrientationFromMetadataOrientation(UIImageMetadataOrientation metadataOrientation);

@interface UIImage (Manipulation)

// Resizing
- (nullable UIImage *)imageByResizingToSize:(CGSize)size;
- (nullable UIImage *)imageByResizingToFitSize:(CGSize)size;
- (nullable UIImage *)imageByResizingToFillSize:(CGSize)size;

// Rounded Corners
- (nullable UIImage *)imageWithCornerRadius:(CGFloat)cornerRadius;
- (nullable UIImage *)imageWithCornerRadius:(CGFloat)cornerRadius inset:(UIEdgeInsets)inset;

// Rotating
- (nullable UIImage *)imageByRotatingToImageOrientation:(UIImageOrientation)imageOrientation NS_SWIFT_NAME(rotatedToImageOrientation(_:));
- (nullable UIImage *)imageByRotatingToIntrinsicOrientation NS_SWIFT_NAME(rotatedToIntrinsicOrientation());

@end

NS_ASSUME_NONNULL_END
