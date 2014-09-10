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

    DSPSplitComplex _DSPSplitComplex;

    FFTSetup _ImageAnalysis;

    Float32 _FFTNormalizationFactor;
    Float32 _FFTScale;
//    Float32 _ScaleB;
    UInt32 _FFTLength;
    UInt32 _Log2N;

    UInt32 _halfWidth;
    UInt32 _halfHeight;
}

@end

@implementation FFT2D

const Float32 kAdjust0DB = 1.5849e-13;
const Float32 one = 1;
const UInt32 originPixel = 0;

/******************************************************************************/
- (id) init
{
    self = [super init];

    _bytesPerPixel = 1;
    _bitsPerComponent = 8;
    
    _colorSpace = CGColorSpaceCreateDeviceGray();
    _bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone;

    return self;
}

/******************************************************************************/
+ (FFT2D *) FFT2DWithBounds:(CGRect)bounds
{
    return [[FFT2D alloc] initWithBounds:bounds];
}

/******************************************************************************/
+ (FFT2D *) FFT2DWithImage:(CIImage *)image
{
    return [[FFT2D alloc] initWithImage:image];
}

/******************************************************************************/
- (id) initWithBounds:(CGRect)bounds
{
    self = [self init];
    [self reinitWithBounds:bounds];
    
    return self;
}

/******************************************************************************/
- (id) initWithImage:(CIImage *)image
{
    self = [self init];
    [self reinitWithImage:image];
    
    return self;
}

/******************************************************************************
 Setup processor for bounds
 ******************************************************************************/
- (void) reinitWithBounds:(CGRect)bounds
{
    if (CGRectEqualToRect(_bounds, bounds)) {
        return;
    }

    _bounds = bounds;
    _width = _bounds.size.width;
    _height = _bounds.size.height;
    
    if (_bitmap) { free(_bitmap); }
    _bitmap =  (Pixel_8 *)malloc(sizeof(Pixel_8) * _width * _height);
    
    _halfWidth = _width / 2;
    _halfHeight = _height / 2;
    
    _Log2NWidth = log2(_width);
    _Log2NHeight = log2(_height);
    
    _Log2N = _Log2NWidth + _Log2NHeight;
    
    _ImageAnalysis = vDSP_create_fftsetup(_Log2N, kFFTRadix2);
    
    _FFTLength = 1 << _Log2N;
    _FFTScale = 1 / sqrt(_FFTLength);
    
    if (_DSPSplitComplex.realp) { free(_DSPSplitComplex.realp); }
    if (_DSPSplitComplex.imagp) { free(_DSPSplitComplex.imagp); }
    
    _DSPSplitComplex.realp = (Float32 *)calloc(_FFTLength, sizeof(Float32));
    _DSPSplitComplex.imagp = (Float32 *)calloc(_FFTLength, sizeof(Float32));
    
    _bytesPerRow = _bytesPerPixel * _width;
    
    if (_CGBitmapContext) { CGContextRelease(_CGBitmapContext); }
    _CGBitmapContext = CGBitmapContextCreate(_bitmap, _width, _height, _bitsPerComponent, _bytesPerRow, _colorSpace, _bitmapInfo);
    
    if (! _CGBitmapContext) {
        NSLog(@"Could not create CGContext");
    }
}

/******************************************************************************
 Setup processor for image
 ******************************************************************************/
- (void) reinitWithImage:(CIImage *)image
{
    [self reinitWithBounds:image.extent];
}

/******************************************************************************
 dealloc
 ******************************************************************************/
- (void) dealloc
{
    CGContextRelease(_CGBitmapContext);
    CGColorSpaceRelease(_colorSpace);
    
    free(_bitmap);
    free(_DSPSplitComplex.realp);
    free(_DSPSplitComplex.imagp);
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
    // vDSP_zvabs(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    // get the magnitude
    vDSP_zvmags(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    
    vDSP_vsmul(_DSPSplitComplex.realp, 1, &_FFTScale, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // log scale
    vDSP_vdbcon(_DSPSplitComplex.realp, 1, &one, _DSPSplitComplex.realp, 1, _FFTLength, 1);
    
    float min = 1.0f;
    float max = 255.0f;
    //
    vDSP_vclip(_DSPSplitComplex.realp, 1, &min, &max, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // Rearrange output sectors
    UInt32 rowSrc, rowDst, rowMax, colSrc, colDst, colMax;
    
    // swap SE and NW Sectors
    rowMax = _halfHeight * _width;
    for (rowDst = originPixel * _width, rowSrc = _halfHeight * _width + _halfWidth; rowDst < rowMax; rowDst += _width, rowSrc += _width ) {
        colMax = rowDst + _halfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc]);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst]);
        }
    }
    
    // swap NE and SW Sectors
    rowMax = _height * _width;
    for (rowDst = _halfHeight * _width, rowSrc = originPixel * _width + _halfWidth; rowDst < rowMax; rowDst += _width, rowSrc += _width ) {
        colMax = rowDst + _halfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc]);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst]);
        }
    }
}

@end
