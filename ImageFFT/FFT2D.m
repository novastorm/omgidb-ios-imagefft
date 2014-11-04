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

@interface FFT2D ()

@property (nonatomic) CGContextRef bitmapContext;
@property (nonatomic) Pixel_8 * bitmap;

@property (nonatomic) UInt32 bytesPerPixel;
@property (nonatomic) UInt32 bitsPerComponent;
@property (nonatomic) UInt32 bytesPerRow;

@property (nonatomic) CGColorSpaceRef colorSpace;
@property (nonatomic) CGBitmapInfo bitmapInfo;

@property (nonatomic) UInt32 log2NWidth;
@property (nonatomic) UInt32 log2NHeight;

@property (nonatomic) DSPSplitComplex splitComplexBuffer;

@property (nonatomic) FFTSetup imageAnalysis;

@property (nonatomic) Float32 normalizationFactor;
@property (nonatomic) Float32 scale;
@property (nonatomic) UInt32 FFTLength;
@property (nonatomic) UInt32 log2N;

@property (nonatomic) UInt32 halfWidth;
@property (nonatomic) UInt32 halfHeight;

@property (nonatomic) CIImage * outputImage;

@end

@implementation FFT2D

@synthesize bounds = _bounds;
@synthesize bitmap = _bitmap;
@synthesize splitComplexBuffer = _splitComplexBuffer;

const Float32 kAdjust0DB = 1.5849e-13;
const Float32 one = 1;
const Float32 min = 0.0f;
const Float32 max = 255.0f;
const UInt32 originPixel = 0;

/******************************************************************************/
- (instancetype) init
{
    self = [super init];

    self.bytesPerPixel = 1;
    self.bitsPerComponent = 8;
    
    self.colorSpace = CGColorSpaceCreateDeviceGray();
    self.bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone;
    self.outputImage = nil;

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

/**
 Initialize with bounds
 */
- (instancetype) initWithBounds:(CGRect)bounds
{
    self = [self init];
    self.bounds = bounds;
    
    return self;
}

/**
 Initialize with bounds and context
 */
- (instancetype) initWithBounds:(CGRect)bounds context:(CIContext *)context
{
    self = [self initWithBounds:bounds];
    self.context = context;
    
    return self;
}

/**
 get bounds
 */
- (CGRect) bounds
{
    return _bounds;
}

/**
 Setup processor with bounds
 */
- (void) setBounds:(CGRect)bounds
{
    if (CGRectEqualToRect(_bounds, bounds)) return;

    [self willChangeValueForKey:@"bounds"];

    _bounds = bounds;
    
    UInt32 width = bounds.size.width;
    UInt32 height = bounds.size.height;
    
    if (self.bitmap) {
        free(self.bitmap);
        self.bitmap = nil;
    }
    self.bitmap =  (Pixel_8 *)malloc(sizeof(Pixel_8) * width * height);
    
    self.halfWidth = width >> 1;
    self.halfHeight = height >> 1;
    
    self.log2NWidth = log2(width);
    self.log2NHeight = log2(height);
    
    self.log2N = self.log2NWidth + self.log2NHeight;
    
    self.imageAnalysis = vDSP_create_fftsetup(self.log2N, kFFTRadix2);
    
    self.FFTLength = 1 << self.log2N;
    self.scale = 1 / sqrt(self.FFTLength);
    
    self.splitComplexBuffer = (DSPSplitComplex){
        (Float32 *)calloc(self.FFTLength, sizeof(Float32))
        , (Float32 *)calloc(self.FFTLength, sizeof(Float32))
    };
    
    self.bytesPerRow = self.bytesPerPixel * width;
    
    if (self.bitmapContext) { CGContextRelease(self.bitmapContext); }
    self.bitmapContext = CGBitmapContextCreate(self.bitmap, width, height, self.bitsPerComponent, self.bytesPerRow, self.colorSpace, self.bitmapInfo);
    
    if (! self.bitmapContext) {
        NSLog(@"Could not create CGContext");
    }
    
    [self didChangeValueForKey:@"bounds"];
}

/**
 get bitmap
 */
- (Pixel_8 *) bitmap
{
    return _bitmap;
}

/**
 set bitmap
 */
- (void) setBitmap:(Pixel_8 *)bitmap
{
    [self willChangeValueForKey:@"bitmap"];
    if (_bitmap) {
        free(_bitmap);
    }
    
    _bitmap = bitmap;
    [self didChangeValueForKey:@"bitmap"];
}

- (void) dealloc
{
    CGContextRelease(self.bitmapContext);
    self.bitmapContext = nil;
    CGColorSpaceRelease(self.colorSpace);
    self.colorSpace = nil;
    
    self.bitmap = nil;
    self.splitComplexBuffer = (DSPSplitComplex){};
}

- (DSPSplitComplex) splitComplexBuffer
{
    return _splitComplexBuffer;
}

- (void) setSplitComplexBuffer:(DSPSplitComplex)splitComplexBuffer
{
    [self willChangeValueForKey:@"splitComplexBuffer"];

    if (_splitComplexBuffer.realp) free(_splitComplexBuffer.realp);
    if (_splitComplexBuffer.imagp) free(_splitComplexBuffer.imagp);
    
    _splitComplexBuffer = splitComplexBuffer;
    [self didChangeValueForKey:@"splitComplexBuffer"];
}

/**
 Create a 2DFFT CIImage from input CGImage
 */
- (CIImage *) FFTWithCGImage:(CGImageRef)image
{
    // draw image to bitmap context
    CGContextDrawImage(self.bitmapContext, self.bounds, image);
    
    [self computeFFTForBitmap:self.bitmap];
    
    // Create a CGImage from the pixel data in the bitmap graphics context
    CGImageRef aCGImage = CGBitmapContextCreateImage(self.bitmapContext);
    
    if (aCGImage == NULL) {
        NSLog(@"Cannot create quartzImage from context");
        return nil;
    }
    
    self.outputImage = [CIImage imageWithCGImage:aCGImage];
    
    // Free up the context, color space,
    CGImageRelease(aCGImage);
    
    if (self.outputImage == nil) {
        NSLog(@"Cannot create outImage from quartzImage");
    }
    
    return self.outputImage;
}

/******************************************************************************
 Create a 2DFFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) FFTWithCIImage:(CIImage *)image
{
    if (! self.context) {
        NSLog(@"context required");
        return nil;
    }
    
    return [self FFTWithCIImage:image context:self.context];
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
    
    self.outputImage = [self FFTWithCGImage:aCGImage];
    
    CGImageRelease(aCGImage);
    
    return self.outputImage;
}

/******************************************************************************/
- (void) computeFFTForBitmap:(Pixel_8 *)bitmap
{
    vDSP_vfltu8(bitmap, 1, _splitComplexBuffer.realp, 1, _FFTLength);
    vDSP_vsdiv(_splitComplexBuffer.realp, 1, &max, _splitComplexBuffer.realp, 1, _FFTLength);
    vDSP_vclr(_splitComplexBuffer.imagp, 1, _FFTLength);
    
    // FFT the data
    vDSP_fft2d_zip(self.imageAnalysis, &_splitComplexBuffer, 1, 0, self.log2NWidth, self.log2NHeight, kFFTDirection_Forward);

    // Get the absolute value
    vDSP_zvabs(&_splitComplexBuffer, 1, _splitComplexBuffer.realp, 1, self.FFTLength);
    
    // scale the magnitudes
//    vDSP_vsmul(_splitComplexBuffer.realp, 1, &_scale, _splitComplexBuffer.realp, 1, self.FFTLength);
    
    // convert to log scale
    vDSP_vdbcon(_splitComplexBuffer.realp, 1, &one, _splitComplexBuffer.realp, 1, self.FFTLength, 1);

    // clip to range
    vDSP_vclip(_splitComplexBuffer.realp, 1, &min, &max, _splitComplexBuffer.realp, 1, self.FFTLength);
    
    // swap quadrants
    UInt32 rowUR, rowLR, rowUL, rowLL, rowMax
         , colUR, colLR, colUL, colLL, colMax;
    
    UInt32 width = self.bounds.size.width;
    
    rowMax = self.halfHeight * width;
    for (rowUL = originPixel * width
        , rowUR = originPixel * width + self.halfWidth
        , rowLL = self.halfHeight * width
        , rowLR = self.halfHeight * width + self.halfWidth
        ;
        rowUL < rowMax
        ;
        rowUL += width, rowUR += width, rowLL += width, rowLR += width)
    {
        colMax = rowUL + self.halfWidth;
        for (colUL = rowUL, colUR = rowUR, colLL = rowLL, colLR = rowLR
            ;
            colUL < colMax
            ;
            colUL++, colUR++, colLL++, colLR++)
        {
            bitmap[colUL] = (int)(_splitComplexBuffer.realp[colLR]);
            bitmap[colLR] = (int)(_splitComplexBuffer.realp[colUL]);
            bitmap[colUR] = (int)(_splitComplexBuffer.realp[colLL]);
            bitmap[colLL] = (int)(_splitComplexBuffer.realp[colUR]);
        }
    }
}

@end
