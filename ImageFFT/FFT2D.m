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
//    CGContextRef _bitmapContext;

    CGRect _bounds;
    UInt32 _width;
    UInt32 _height;

//    Pixel_8 * _bitmap;
    
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
    
    CIImage * _outputImage;
}

@property (nonatomic) CGContextRef bitmapContext;
@property (nonatomic) Pixel_8 * bitmap;


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
    _outputImage = nil;

    return self;
}

/******************************************************************************/
+ (instancetype) FFT2DWithBounds:(CGRect)bounds
{
    return [[FFT2D alloc] initWithBounds:bounds];
}

/******************************************************************************/
+ (instancetype) FFT2DWithBounds:(CGRect)bounds context:(CIContext *)context
{
    return [[FFT2D alloc] initWithBounds:bounds context:context];
}

/******************************************************************************/
+ (instancetype) FFT2DWithImage:(CIImage *)image
{
    return [[FFT2D alloc] initWithImage:image];
}

/******************************************************************************/
+ (instancetype) FFT2DWithImage:(CIImage *)image context:(CIContext *)context
{
    return [[FFT2D alloc] initWithImage:image context:context];
}

/**
 Initialize with bounds
 */
- (id) initWithBounds:(CGRect)bounds
{
    self = [self init];
    [self reinitWithBounds:bounds];
    
    return self;
}

/**
 Initialize with bounds and context
 */
- (id) initWithBounds:(CGRect)bounds context:(CIContext *)context
{
    self = [self initWithBounds:bounds];
    self.ciContext = context;
    
    return self;
}

/**
 Initialize FFT2D with an image
*/
- (id) initWithImage:(CIImage *)image
{
    self = [self init];
    [self reinitWithImage:image];

    return self;
}

/**
 Initialize FFT2D with an image
 */
- (id) initWithImage:(CIImage *)image context:(CIContext *)context
{
    self = [self initWithImage:image];
    self.ciContext = context;
    
    return self;
}

/**
 Setup processor with bounds
 */
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
    
    _halfWidth = _width >> 1;
    _halfHeight = _height >> 1;
    
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
    
    if (_bitmapContext) { CGContextRelease(_bitmapContext); }
    _bitmapContext = CGBitmapContextCreate(_bitmap, _width, _height, _bitsPerComponent, _bytesPerRow, _colorSpace, _bitmapInfo);
    
    if (! _bitmapContext) {
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
    CGContextRelease(_bitmapContext);
    CGColorSpaceRelease(_colorSpace);
    
    free(_bitmap);
    free(_DSPSplitComplex.realp);
    free(_DSPSplitComplex.imagp);
}

/******************************************************************************
 Create a 2DFFT CIImage from input CGImage
 ******************************************************************************/
- (CIImage *) FFTWithCGImage:(CGImageRef)image
{
    // draw image to bitmap context
    CGContextDrawImage(_bitmapContext, _bounds, image);
    
    [self computeFFTForBitmap:_bitmap];
    
    // Create a CGImage from the pixel data in the bitmap graphics context
    CGImageRef aCGImage = CGBitmapContextCreateImage(_bitmapContext);
    
    if (aCGImage == NULL) {
        NSLog(@"Cannot create quartzImage from context");
        return nil;
    }
    
    _outputImage = [CIImage imageWithCGImage:aCGImage];
    
    if (_outputImage == nil) {
        NSLog(@"Cannot create outImage from quartzImage");
        return nil;
    }
    
    // Free up the context, color space,
    CGImageRelease(aCGImage);
    
    return _outputImage;
}

/******************************************************************************
 Create a 2DFFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) FFTWithCIImage:(CIImage *)image context:(CIContext *)context
{
    CGImageRef aCGImage = [context createCGImage:image fromRect:image.extent];
    
    if (aCGImage == NULL) {
        NSLog(@"cannot get a CGImage from image");
        return nil;
    }
    
    _outputImage = [self FFTWithCGImage:aCGImage];
    
    CGImageRelease(aCGImage);
    
    return _outputImage;
}

/******************************************************************************
 Create a 2DFFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) FFTWithCIImage:(CIImage *)image
{
    if (! self.ciContext) {
        NSLog(@"context required");
        return nil;
    }
    
    return [self FFTWithCIImage:image context:self.ciContext];
}

/******************************************************************************/
- (void) computeFFTForBitmap:(Pixel_8 *)bitmap
{
    for (UInt32 i = 0; i < _FFTLength; ++i) {
        _DSPSplitComplex.realp[i] = (Float32)bitmap[i] / 255.0f;
        _DSPSplitComplex.imagp[i] = 0.0;
    }
    
    // FFT the data
    vDSP_fft2d_zip(_ImageAnalysis, &_DSPSplitComplex, 1, 0, _Log2NWidth, _Log2NHeight, kFFTDirection_Forward);
    
    // get the absolute value
    // vDSP_zvabs(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    // get the magnitude
    vDSP_zvmags(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    
    vDSP_vsmul(_DSPSplitComplex.realp, 1, &_FFTScale, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // log scale
    vDSP_vdbcon(_DSPSplitComplex.realp, 1, &one, _DSPSplitComplex.realp, 1, _FFTLength, 1);
    
    float min = 0.9f;
    float max = 255.0f;
    //
    vDSP_vclip(_DSPSplitComplex.realp, 1, &min, &max, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // swap quadrants
    UInt32 rowUR, rowLR, rowUL, rowLL, rowMax
         , colUR, colLR, colUL, colLL, colMax;
    
    rowMax = _halfHeight * _width;
    for (rowUL = originPixel * _width
        , rowUR = originPixel * _width + _halfWidth
        , rowLL = _halfHeight * _width
        , rowLR = _halfHeight * _width + _halfWidth
        ;
        rowUL < rowMax
        ;
        rowUL += _width, rowUR += _width, rowLL += _width, rowLR += _width)
    {
        colMax = rowUL + _halfWidth;
        for (colUL = rowUL, colUR = rowUR, colLL = rowLL, colLR = rowLR
            ;
            colUL < colMax
            ;
            colUL++, colUR++, colLL++, colLR++)
        {
            bitmap[colUL] = (int)(_DSPSplitComplex.realp[colLR]);
            bitmap[colLR] = (int)(_DSPSplitComplex.realp[colUL]);
            bitmap[colUR] = (int)(_DSPSplitComplex.realp[colLL]);
            bitmap[colLL] = (int)(_DSPSplitComplex.realp[colUR]);
        }
    }
}

@end
