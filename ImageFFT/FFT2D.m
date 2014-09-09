//
//  FFT2D.m
//  ImageFFT
//
//  Created by Adland Lee on 9/8/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import <Accelerate/Accelerate.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

#import "FFT2D.h"

@interface FFT2D () {
    CIContext * _CIContext;
    CGContextRef _CGBitmapContext;

    CGRect _bounds;
    UInt32 _width;
    UInt32 _height;

    Pixel_8 * _bitmap;
    
    UInt32 _bytesPerPixel;
    UInt32 _bitsPerComponent;
    UInt32 _bytesPerRow;
    
    CGColorSpaceRef _colorSpace;
    CGBitmapInfo _bitmapInfo;

    UInt32 _Log2NWidth;
    UInt32 _Log2NHeight;

    FFTSetup _ImageAnalysis;
    DSPSplitComplex _DSPSplitComplex;
    Float32 _FFTNormalizationFactor;
    Float32 _ScaleA;
    Float32 _ScaleB;
    UInt32 _FFTLength;
    UInt32 _Log2N;

    UInt32 _FFTHalfWidth;
    UInt32 _FFTHalfHeight;
}

@end

@implementation FFT2D

const Float32 kAdjust0DB = 1.5849e-13;
const Float32 one = 1;

/******************************************************************************
 init
 ******************************************************************************/
- (id) init
{
    self = [super init];

    _bytesPerPixel = 1;
    _bitsPerComponent = 8;
    
    _colorSpace = CGColorSpaceCreateDeviceGray();
    _bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone;

    return self;
}

/******************************************************************************
 Setup processor for image
 ******************************************************************************/
- (void) setupForImage:(CIImage *)image
{
    _bounds = image.extent;
    _width = _bounds.size.width;
    _height = _bounds.size.height;
    
    if (_bitmap) {
        free(_bitmap);
    }
    
    _bitmap =  (Pixel_8 *)malloc(sizeof(Pixel_8) * _width * _height);
    
    _bytesPerRow = _bytesPerPixel * _width;

    if (_CGBitmapContext) {
        CGContextRelease(_CGBitmapContext);
    }
    _CGBitmapContext = CGBitmapContextCreate(_bitmap, _width, _height, _bitsPerComponent, _bytesPerRow, _colorSpace, _bitmapInfo);
    
    if (! _CGBitmapContext) {
        NSLog(@"Could not create CGContext");
    }
}

/******************************************************************************
 Create a 2DFFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterFFTForImage:(CIImage *) inImage
{
    CGImageRef aCGImage = [_CIContext createCGImage:inImage fromRect:inImage.extent];
    
    if (aCGImage == NULL) {
        NSLog(@"cannot get a CGImage from inImage");
        return nil;
    }
    
    // draw image to bitmap context
    CGContextDrawImage(_CGBitmapContext, _bounds, aCGImage);
    CGImageRelease(aCGImage);
    
    [self computeFFTForBitmap:_bitmap];
    
    // Create a CGImage from the pixel data in the bitmap graphics context
    aCGImage = CGBitmapContextCreateImage(_CGBitmapContext);
    
    if (aCGImage == NULL) {
        NSLog(@"Cannot create quartzImage from context");
        return nil;
    }
    
    CIImage * outImage = [CIImage imageWithCGImage:aCGImage];
    
    if (outImage == NULL) {
        NSLog(@"Cannot create outImage from quartzImage");
        return nil;
    }
    
    // Free up the context, color space,
    CGImageRelease(aCGImage);
    
    return outImage;
}

/******************************************************************************/
- (void) computeFFTForBitmap:(Pixel_8 *)bitmap
{
    for (UInt32 i = 0; i < _FFTLength; ++i) {
        _DSPSplitComplex.realp[i] = (Float32)bitmap[i] / 255.0f;
        _DSPSplitComplex.imagp[i] = 0.0;
    }
    
    size_t col = _Log2NWidth;
    size_t row = col;
    
    // FFT the data
    vDSP_fft2d_zip(_ImageAnalysis, &_DSPSplitComplex, 1, 0, col, row, kFFTDirection_Forward);
    
    // get the absolute value
    //    vDSP_zvabs(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    // get the magnitude
    vDSP_zvmags(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    
    vDSP_vsmul(_DSPSplitComplex.realp, 1, &_ScaleB, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // log scale
    vDSP_vdbcon(_DSPSplitComplex.realp, 1, &one, _DSPSplitComplex.realp, 1, _FFTLength, 1);
    
    float min = 1.0f;
    float max = 255.0f;
    //
    vDSP_vclip(_DSPSplitComplex.realp, 1, &min, &max, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // Rearrange output sectors
    UInt32 rowSrc, rowDst, rowMax, colSrc, colDst, colMax;
    
    
    // swap SE and NW Sectors
    rowMax = _FFTHalfHeight * _FFTWidth;
    for (rowDst = 0, rowSrc = 128 * _FFTWidth + 128; rowDst < rowMax; rowDst += _FFTWidth, rowSrc += _FFTWidth ) {
        colMax = rowDst + _FFTHalfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc]);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst]);
        }
    }
    
    // swap NE and SW Sectors
    rowMax = _FFTHeight * _FFTWidth;
    for (rowDst = 128 * _FFTWidth, rowSrc = 0 * _FFTWidth + 128; rowDst < rowMax; rowDst += _FFTWidth, rowSrc += _FFTWidth ) {
        colMax = rowDst + _FFTHalfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc]);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst]);
        }
    }
}

@end
