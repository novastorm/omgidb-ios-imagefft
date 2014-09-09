//
//  ViewController.m
//  ImageFFT
//
//  Created by Adland Lee on 8/18/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import <Accelerate/Accelerate.h>
#import <CoreVideo/CVOpenGLESTextureCache.h>

#import "ImageFFTViewController.h"

@interface ImageFFTViewController () {
    CIContext * _CIContext;
    EAGLContext* _EAGLContext;
    CGRect _PrimaryViewerBounds;
    CGRect _SecondaryViewerBounds;
    
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    
    NSString* _sessionPreset;
    AVCaptureSession* _session;
    
    CVOpenGLESTextureCacheRef _videoTextureCache;

    size_t _FFTWidth;
    size_t _FFTHeight;
    Pixel_8 * _bitmap;

    size_t _Log2NWidth;
    size_t _Log2NHeight;
    
    FFTSetup _ImageAnalysis;
    DSPSplitComplex _DSPSplitComplex;
//    Float32 _FFTNormalizationFactor;
    Float32 _ScaleA;
    Float32 _ScaleB;
    UInt32 _FFTLength;
    UInt32 _Log2N;
    
    size_t _FFTHalfWidth;
    size_t _FFTHalfHeight;
}

@end

@implementation ImageFFTViewController

const Float32 kAdjust0DB = 1.5849e-13;
const Float32 one = 1;

/******************************************************************************/
- (void)viewDidLoad {
    [super viewDidLoad];

    _EAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    _CIContext = [CIContext contextWithEAGLContext:_EAGLContext options:@{kCIContextOutputColorSpace: [NSNull null]} ];
    
    if (! _EAGLContext) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView * view = (GLKView *)self.view;
    view.context = _EAGLContext;
    self.preferredFramesPerSecond = 60;
    
    view.contentScaleFactor = [UIScreen mainScreen].scale;
    
    _sessionPreset = AVCaptureSessionPreset352x288;
    
    CGFloat width = view.frame.size.width * view.contentScaleFactor;
    CGFloat height = view.frame.size.height * view.contentScaleFactor;
    
    _PrimaryViewerBounds = CGRectZero;
    _PrimaryViewerBounds.origin.x = 0;
    _PrimaryViewerBounds.origin.y = height - width;
    _PrimaryViewerBounds.size.width = width;
    _PrimaryViewerBounds.size.height = width;
    
    _SecondaryViewerBounds = CGRectZero;
    _SecondaryViewerBounds.origin.x = 0.5f * view.frame.size.width;
    _SecondaryViewerBounds.origin.y = 0.25f * view.frame.size.width;
    _SecondaryViewerBounds.size.width = view.frame.size.width;
    _SecondaryViewerBounds.size.height = view.frame.size.width;

    [self setupFFTAnalysis];
    [self setupGL];
    [self setupAVCapture];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/******************************************************************************/
- (void) setupGL
{
    [EAGLContext setCurrentContext:_EAGLContext];
    
//    [self loadShaders];
}

/******************************************************************************/
- (void) setupAVCapture
{
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _EAGLContext, NULL, &_videoTextureCache);
#else
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)_context, NULL, &_videoTextureCache);
#endif
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
    
    _session = [[AVCaptureSession alloc] init];
    [_session beginConfiguration];
    
    [_session setSessionPreset:_sessionPreset];
    
    AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (nil == videoDevice) assert(0);
    
    NSError* error;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) assert(0);
    
    [_session addInput:input];
    
    
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [dataOutput setVideoSettings:[NSDictionary
    	dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        forKey:(id)kCVPixelBufferPixelFormatTypeKey]
        ];
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_session addOutput:dataOutput];
    [_session commitConfiguration];
    
    [_session startRunning];
}

/******************************************************************************/
- (void) setupFFTAnalysis
{
    _FFTWidth = 256;
    _FFTHeight = 256;
    _FFTHalfWidth = _FFTWidth / 2;
    _FFTHalfHeight = _FFTHeight / 2;
    
    _bitmap =  (Pixel_8 *)malloc(sizeof(Pixel_8) * _FFTWidth * _FFTHeight);
    
    _Log2NWidth = log2(_FFTWidth);
    _Log2NHeight = log2(_FFTHeight);
    
    _Log2N = _Log2NWidth + _Log2NHeight;
    
    _ImageAnalysis = NULL;
    _FFTLength = 1 << _Log2N;
    _ScaleA = 0.1f;
    _ScaleB = 1.0 / sqrt(_FFTLength);
    
    _DSPSplitComplex.realp = (Float32 *)calloc(_FFTLength, sizeof(Float32));
    _DSPSplitComplex.imagp = (Float32 *)calloc(_FFTLength, sizeof(Float32));
    
    _ImageAnalysis = vDSP_create_fftsetup(_Log2N, kFFTRadix2);
}

/******************************************************************************/
- (void) captureOutput:(AVCaptureOutput *)captureOutput
	didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection *)connection
{
    if (! _videoTextureCache) {
        NSLog(@"No video texture cache");
        return;
    }

    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    CIImage * image = [self imageFromSampleBuffer:sampleBuffer];

    CIImage * drawImage = [self filterFFTImage:image];

    CGRect sourceRect = drawImage.extent;
    
    [_CIContext drawImage:image inRect:_SecondaryViewerBounds fromRect:sourceRect];
    [_CIContext drawImage:drawImage inRect:_PrimaryViewerBounds fromRect:sourceRect];
    
    [(GLKView *)self.view display];
    
    [self cleanUpTextures];
}

/******************************************************************************
 Create a CIImage from sample buffer data
 ******************************************************************************/
- (CIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    CIImage * image = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    image = [self filterSquareImage:image];
    image = [self filterGrayscaleImage:image];
    image = [self filterScaleImage:image fromSize:image.extent.size.width toSize:256];

    return image;
}

/******************************************************************************
 Create a Square CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterSquareImage:(CIImage *)inImage
{

    // crop to square
    CGRect cropRect = inImage.extent;
    
    if (cropRect.size.width == cropRect.size.height) {
        return inImage;
    }

    if (cropRect.size.width < cropRect.size.height) {
        cropRect.size.height = cropRect.size.width;
    }
    else {
        cropRect.size.width = cropRect.size.height;
    }
    
    return [CIFilter filterWithName:@"CICrop" keysAndValues:
        kCIInputImageKey, inImage
        , @"inputRectangle", [CIVector vectorWithCGRect:cropRect]
        , nil].outputImage;
}

/******************************************************************************
 grayscale the image
 ******************************************************************************/
- (CIImage *) filterGrayscaleImage:(CIImage *)inImage
{
    return [CIFilter filterWithName:@"CIMaximumComponent"
        keysAndValues:
            kCIInputImageKey, inImage
            , nil
        ].outputImage;
}

/******************************************************************************
 Scale input CIImage
 ******************************************************************************/
- (CIImage *) filterScaleImage:(CIImage *)inImage fromSize:(Float32)fromSize toSize:(Float32)toSize
{
    Float32 scale = toSize / fromSize;
    
    return [CIFilter filterWithName:@"CILanczosScaleTransform"
                         keysAndValues:
               kCIInputImageKey, inImage
               , @"inputScale", [NSNumber numberWithFloat:scale]
               , nil
               ].outputImage;
}

/******************************************************************************
 Create a 2DFFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterFFTImage:(CIImage *) inImage
{
    size_t width = inImage.extent.size.width;
    size_t height = inImage.extent.size.height;
    
    CGRect bounds = CGRectMake(0, 0, width, height);
    
    Pixel_8 * bitmap = _bitmap;

    size_t bytesPerPixel = 1;
    size_t bitsPerComponent = 8;
    size_t bytesPerRow = bytesPerPixel * width;

    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone;

    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(bitmap, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);

    if (context == NULL) {
        NSLog(@"Could not create CGContext");
        return nil;
    }
    
    CGImageRef aCGImage = [_CIContext createCGImage:inImage fromRect:inImage.extent];
    
    if (aCGImage == NULL) {
        NSLog(@"cannot get a CGImage from inImage");
        return nil;
    }
    
    // draw image to bitmap context
    CGContextDrawImage(context, bounds, aCGImage);
    CGImageRelease(aCGImage);
    
    [self computeFFTForBitmap:bitmap];

    // Create a CGImage from the pixel data in the bitmap graphics context
    aCGImage = CGBitmapContextCreateImage(context);

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
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(aCGImage);
    
    return outImage;
}

/******************************************************************************/
- (void) cleanUpTextures
{
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
    
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
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

/******************************************************************************/


@end
