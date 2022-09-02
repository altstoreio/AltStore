//
//  UIImage+Manipulation.m
//  Hoot
//
//  Created by Riley Testut on 9/23/14.
//  Copyright (c) 2014 TMT. All rights reserved.
//

#import "UIImage+Manipulation.h"

@implementation UIImage (Manipulation)

#pragma mark - Resizing -

- (UIImage *)imageByResizingToFitSize:(CGSize)size
{
    CGSize imageSize = self.size;
    
    CGFloat horizontalScale = size.width / imageSize.width;
    CGFloat verticalScale = size.height / imageSize.height;
    
    // Resizing to minimum scale (ex: 1/20 instead of 1/2) ensures image will retain aspect ratio, and fit inside size
    CGFloat scale = MIN(horizontalScale, verticalScale);
    size = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    
    return [self imageByResizingToSize:size];
}

- (UIImage *)imageByResizingToFillSize:(CGSize)size
{
    CGSize imageSize = self.size;
    
    CGFloat horizontalScale = size.width / imageSize.width;
    CGFloat verticalScale = size.height / imageSize.height;
    
    // Resizing to maximum scale (ex: 1/2 instead of 1/20) ensures image will retain aspect ratio, and will fill size
    CGFloat scale = MAX(horizontalScale, verticalScale);
    size = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    
    return [self imageByResizingToSize:size];
}

- (UIImage *)imageByResizingToSize:(CGSize)size
{
    switch (self.imageOrientation)
    {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            size = CGSizeMake(size.height, size.width);
            break;
            
        default:
            break;
    }
    
    CGRect rect = CGRectIntegral(CGRectMake(0, 0, size.width * self.scale, size.height * self.scale));
    
    CGContextRef context = [self createContextWithRect:rect];
    if (context == nil)
    {
        return nil;
    }
    
    CGContextDrawImage(context, rect, self.CGImage);
    
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    UIImage *image = [[UIImage imageWithCGImage:imageRef scale:self.scale orientation:self.imageOrientation] imageWithRenderingMode:self.renderingMode];
    
    CFRelease(imageRef);
    CFRelease(context);
    
    return image;
}

#pragma mark - Rounded Corners -

- (UIImage *)imageWithCornerRadius:(CGFloat)cornerRadius
{
    return [self imageWithCornerRadius:cornerRadius inset:UIEdgeInsetsZero];
}

- (UIImage *)imageWithCornerRadius:(CGFloat)cornerRadius inset:(UIEdgeInsets)inset
{
    UIEdgeInsets correctedInset = inset;
    
    switch (self.imageOrientation)
    {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            correctedInset.top = inset.left;
            correctedInset.bottom = inset.right;
            correctedInset.left = inset.bottom;
            correctedInset.right = inset.top;
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            correctedInset.top = inset.right;
            correctedInset.bottom = inset.left;
            correctedInset.left = inset.top;
            correctedInset.right = inset.bottom;
            break;
            
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            correctedInset.top = inset.bottom;
            correctedInset.bottom = inset.top;
            correctedInset.left = inset.left;
            correctedInset.right = inset.right;
            break;
            
        default:
            break;
    }
    
    CGFloat imageScale = self.scale;
    
    CGRect clippedRect = CGRectMake(0, 0, self.size.width - correctedInset.left - correctedInset.right, self.size.height - correctedInset.top - correctedInset.bottom);
    CGRect drawingRect = CGRectMake(-correctedInset.left, -correctedInset.top, self.size.width, self.size.height);
    
    clippedRect = CGRectApplyAffineTransform(clippedRect, CGAffineTransformMakeScale(imageScale, imageScale));
    drawingRect = CGRectApplyAffineTransform(drawingRect, CGAffineTransformMakeScale(imageScale, imageScale));
    
    CGContextRef context = [self createContextWithRect:clippedRect];
    if (context == nil)
    {
        return nil;
    }
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:clippedRect cornerRadius:cornerRadius * imageScale];
    
    CGContextAddPath(context, path.CGPath);
    CGContextClip(context);
    
    CGContextDrawImage(context, drawingRect, self.CGImage);
    
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    UIImage *image = [[UIImage imageWithCGImage:imageRef scale:imageScale orientation:self.imageOrientation] imageWithRenderingMode:self.renderingMode];
    
    CFRelease(imageRef);
    CFRelease(context);
    
    return image;
}

#pragma mark - Rotating -

- (UIImage *)imageByRotatingToImageOrientation:(UIImageOrientation)imageOrientation
{
    UIImage *image = [UIImage imageWithCGImage:self.CGImage scale:self.scale orientation:imageOrientation];
    UIImage *rotatedImage = [image imageByRotatingToIntrinsicOrientation];
    
    return rotatedImage;
}

- (nullable UIImage *)imageByRotatingToIntrinsicOrientation
{
    if (self.imageOrientation == UIImageOrientationUp)
    {
        // Image orientation is already UIImageOrientationUp, so no need to do anything.
        return self;
    }
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (self.imageOrientation)
    {
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
            
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, self.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, self.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
    }
    
    switch (self.imageOrientation)
    {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    CGRect rect = CGRectIntegral(CGRectMake(0, 0, self.size.width * self.scale, self.size.height * self.scale));
    
    CGContextRef context = [self createContextWithRect:rect];
    if (context == nil)
    {
        return nil;
    }
    
    CGContextConcatCTM(context, transform);
    
    switch (self.imageOrientation)
    {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            CGContextDrawImage(context, CGRectMake(0, 0, CGRectGetHeight(rect), CGRectGetWidth(rect)), self.CGImage);
            break;
            
        default:
            CGContextDrawImage(context, rect, self.CGImage);
            break;
    }
    
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    UIImage *image = [[UIImage imageWithCGImage:imageRef scale:self.scale orientation:UIImageOrientationUp] imageWithRenderingMode:self.renderingMode];
    
    CFRelease(imageRef);
    CFRelease(context);
    
    return image;
}

#pragma mark - Graphics Context -

- (nullable CGContextRef)createContextWithRect:(CGRect)rect
{
    size_t bitsPerComponent = CGImageGetBitsPerComponent(self.CGImage);
    CGColorSpaceRef imageColorSpace = CGImageGetColorSpace(self.CGImage);
    
    CGColorSpaceRef outputColorSpace = imageColorSpace;
    if (!CGColorSpaceSupportsOutput(imageColorSpace))
    {
        outputColorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(self.CGImage);
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(self.CGImage);
    
    bitmapInfo &= ~(kCGBitmapAlphaInfoMask & alphaInfo);
    
    switch (alphaInfo)
    {
        case kCGImageAlphaNone:
        case kCGImageAlphaLast:
            alphaInfo = kCGImageAlphaNoneSkipLast;
            break;
            
        case kCGImageAlphaPremultipliedLast:
            alphaInfo = kCGImageAlphaPremultipliedFirst;
            break;
            
        default: break;
    }
    
    bitmapInfo |= (kCGBitmapAlphaInfoMask & alphaInfo);
    
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 CGRectGetWidth(rect),
                                                 CGRectGetHeight(rect),
                                                 bitsPerComponent,
                                                 0, // CGImageGetBytesPerRow(self.CGImage) crashes on malformed UIImages (such as Crossy Road's). Passing 0 = automatic calculation, and is safer
                                                 outputColorSpace,
                                                 bitmapInfo);
    
    if (!CGColorSpaceSupportsOutput(imageColorSpace))
    {
        CGColorSpaceRelease(outputColorSpace);
    }
    
    if (context == NULL)
    {
        return nil;
    }
    
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    
    return context;
}

@end


UIImageMetadataOrientation UIImageMetadataOrientationFromImageOrientation(UIImageOrientation imageOrientation)
{
    UIImageMetadataOrientation metadataOrientation = UIImageMetadataOrientationUp;
    
    switch (imageOrientation)
    {
        case UIImageOrientationUp:
            metadataOrientation = UIImageMetadataOrientationUp;
            break;
            
        case UIImageOrientationDown:
            metadataOrientation = UIImageMetadataOrientationDown;
            break;
            
        case UIImageOrientationLeft:
            metadataOrientation = UIImageMetadataOrientationLeft;
            break;
            
        case UIImageOrientationRight:
            metadataOrientation = UIImageMetadataOrientationRight;
            break;
            
        case UIImageOrientationUpMirrored:
            metadataOrientation = UIImageMetadataOrientationUpMirrored;
            break;
            
        case UIImageOrientationDownMirrored:
            metadataOrientation = UIImageMetadataOrientationDownMirrored;
            break;
            
        case UIImageOrientationLeftMirrored:
            metadataOrientation = UIImageMetadataOrientationLeftMirrored;
            break;
            
        case UIImageOrientationRightMirrored:
            metadataOrientation = UIImageMetadataOrientationRightMirrored;
            break;
    }
    
    return metadataOrientation;
}

UIImageOrientation UIImageOrientationFromMetadataOrientation(UIImageMetadataOrientation metadataOrientation)
{
    UIImageOrientation imageOrientation = UIImageOrientationUp;
    
    switch (metadataOrientation)
    {
        case UIImageMetadataOrientationUp:
            imageOrientation = UIImageOrientationUp;
            break;
            
        case UIImageMetadataOrientationDown:
            imageOrientation = UIImageOrientationDown;
            break;
            
        case UIImageMetadataOrientationLeft:
            imageOrientation = UIImageOrientationLeft;
            break;
            
        case UIImageMetadataOrientationRight:
            imageOrientation = UIImageOrientationRight;
            break;
            
        case UIImageMetadataOrientationUpMirrored:
            imageOrientation = UIImageOrientationUpMirrored;
            break;
            
        case UIImageMetadataOrientationDownMirrored:
            imageOrientation = UIImageOrientationDownMirrored;
            break;
            
        case UIImageMetadataOrientationLeftMirrored:
            imageOrientation = UIImageOrientationLeftMirrored;
            break;
            
        case UIImageMetadataOrientationRightMirrored:
            imageOrientation = UIImageOrientationRightMirrored;
            break;
    }
    
    return imageOrientation;
}
