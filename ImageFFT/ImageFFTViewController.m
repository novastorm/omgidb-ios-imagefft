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
    CGRect _videoPreviewViewBounds;
    
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
    Float32 _FFTNormalizationFactor;
    Float32 _Scale;
    UInt32 _FFTLength;
    UInt32 _Log2N;
    
    size_t _FFTHalfWidth;
    size_t _FFTHalfHeight;
    Pixel_8 * _bitmapTemp;
}

@end

@implementation ImageFFTViewController
            
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
    
    _videoPreviewViewBounds = CGRectZero;
    _videoPreviewViewBounds.size.width = view.frame.size.width;
    _videoPreviewViewBounds.size.height = view.frame.size.height;
    
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
//        dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
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
    _bitmapTemp = (Pixel_8 *)malloc(sizeof(Pixel_8) * _FFTHalfWidth);
    
    _Log2NWidth = log2(_FFTWidth);
    _Log2NHeight = log2(_FFTHeight);
//    NSLog(@"[%lu][%lu]", _Log2NWidth, _Log2NHeight);
    
    _Log2N = _Log2NWidth + _Log2NHeight;
    
    _ImageAnalysis = NULL;
//    _FFTNormalizationFactor = 1.0;
    _FFTLength = 1 << _Log2N;
//    _Scale = 1.0 / _FFTLength;
    _Scale = 1.0 / _FFTWidth; // 1.0 / sqrt(_FFTLength)
//    NSLog(@"[%f]", _Scale);
    
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

    CIImage * drawImage = [self imageFromSampleBuffer:sampleBuffer];

    CGRect sourceRect = drawImage.extent;
//    sourceRect.size.width = sourceRect.size.height;

    CGRect drawRect;
    drawRect.size.width = self.view.frame.size.height;
    drawRect.size.height = self.view.frame.size.height;
    
    [_CIContext drawImage:drawImage inRect:drawRect fromRect:sourceRect];
    
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

    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    CIImage * image = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    image = [self filterSquareImage:image];
    image = [self filterGrayscaleImage:image];
    image = [self filterFFTImage:image];
//    image = [self filterReorderSectors:image];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    return image;
}

/******************************************************************************
 Create a Square CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterSquareImage:(CIImage *)inImage
{

    // crop to square
    CGRect cropRect = inImage.extent;

    if (cropRect.size.width < cropRect.size.height) {
        cropRect.size.height = cropRect.size.width;
    }
    else {
        cropRect.size.width = cropRect.size.height;
    }
    
    CIFilter * filter = [CIFilter filterWithName:@"CICrop"];
    [filter setValue:inImage forKey:@"inputImage"];
    [filter setValue:[CIVector vectorWithCGRect:cropRect] forKey:@"inputRectangle"];

    return [filter valueForKey:kCIOutputImageKey];
}

/******************************************************************************
 grayscale the image
 ******************************************************************************/
- (CIImage *) filterGrayscaleImage:(CIImage *)inImage
{
    CIFilter * filter = [CIFilter filterWithName:@"CIMaximumComponent"];
    
    [filter setValue:inImage forKey:@"inputImage"];
    
    return [filter valueForKey:kCIOutputImageKey];
}

/******************************************************************************
 Create a FFT CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterFFTImage:(CIImage *) inImage
{
    size_t width = inImage.extent.size.width;
    size_t height = inImage.extent.size.height;
    
//    NSLog(@"FFT input W[%0.2f] H[%0.2f]"
//        , inImage.extent.size.width
//        , inImage.extent.size.height
//        );
    
    // scale image to 256x256
    float scale = 256.0f / width;
    
    CIFilter * filter = [CIFilter filterWithName:@"CILanczosScaleTransform"
    	keysAndValues:
            kCIInputImageKey, inImage
            , @"inputScale", [NSNumber numberWithFloat:scale]
            , nil];
    
    inImage = [filter valueForKey:kCIOutputImageKey];

//    NSLog(@"FFT input W[%0.2f] H[%0.2f]"
//        , inImage.extent.size.width
//        , inImage.extent.size.height
//        );
    
//    return inImage;
    
    width = inImage.extent.size.width;
    height = inImage.extent.size.height;
    
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
    
    // process bitmap
    
    [self computeFFTForBitmap:bitmap];
    
//    Pixel_8 * pBit;
//    
//    pBit = (bitmap + (126 * 256) + 126);
//    *pBit = 0xFF; *++pBit = 0xFF; *++pBit = 0xFF;
//    pBit = (bitmap + (127 * 256) + 126);
//    *pBit = 0xFF;  ++pBit;        *++pBit = 0xFF;
//    pBit = (bitmap + (128 * 256) + 126);
//    *pBit = 0xFF; *++pBit = 0xFF; *++pBit = 0xFF;
//    
//    *(bitmap + (124 * 256) + 124) = 0xff;
//    
//    NSLog(@"Target [%d]", *(bitmap + (127 * 255) + 127));
    
//    [self computeFFTForBitmap:bitmap];

    // end process bitmap

    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);

    if (quartzImage == NULL) {
        NSLog(@"Cannot create quartzImage from context");
        return nil;
    }
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

//    return [CIImage imageWithCGImage:quartzImage];
    
    CIImage * outImage = [CIImage imageWithCGImage:quartzImage];
    
    if (outImage == NULL) {
        NSLog(@"Cannot create outImage from quartzImage");
        return nil;
    }
    
    CGImageRelease(quartzImage);
    
    // filter quad
    
    return outImage;
}

/******************************************************************************
 reorder sectors
 ******************************************************************************/
- (CIImage *) filterReorderSectors:(CIImage *)inImage
{
    CIFilter * filter = [CIFilter filterWithName:@"CICrop"];
    
    [filter setValue:inImage forKey:@"inputImage"];
    
    CGRect sector1 = {0  , 128, 128, 128};
    CGRect sector2 = {128, 128, 128, 128};
    CGRect sector3 = {0  ,   0, 128, 128};
    CGRect sector4 = {128,   0, 128, 128};
    
    CIImage * s4 = [CIFilter filterWithName:@"CICrop"
        keysAndValues:
            kCIInputImageKey, inImage
            , @"inputRectangle", [CIVector vectorWithCGRect:sector1]
            , nil].outputImage; // 1
    
    CIImage * s3 = [CIFilter filterWithName:@"CICrop"
        keysAndValues:
            kCIInputImageKey, inImage
            , @"inputRectangle", [CIVector vectorWithCGRect:sector2]
            , nil].outputImage; // 2
    
    CIImage * s2 = [CIFilter filterWithName:@"CICrop"
        keysAndValues:
            kCIInputImageKey, inImage
            , @"inputRectangle", [CIVector vectorWithCGRect:sector3]
            , nil].outputImage; // 3
    
    CIImage * s1 = [CIFilter filterWithName:@"CICrop"
        keysAndValues:
            kCIInputImageKey, inImage
            , @"inputRectangle", [CIVector vectorWithCGRect:sector4]
            , nil].outputImage; // 4
    
    [_CIContext drawImage:s1 inRect:sector1 fromRect:s1.extent];
    [_CIContext drawImage:s2 inRect:sector2 fromRect:s2.extent];
    [_CIContext drawImage:s3 inRect:sector3 fromRect:s3.extent];
    [_CIContext drawImage:s4 inRect:sector4 fromRect:s4.extent];
    
    return [filter valueForKey:kCIOutputImageKey];
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
    
//    NSLog(@"[%f]", _DSPSplitComplex.realp[0]);

    // get the mangitude
    vDSP_zvabs(&_DSPSplitComplex, 1, _DSPSplitComplex.realp, 1, _FFTLength);
    
    // scale the data to original scale
    vDSP_vsmul(_DSPSplitComplex.realp, 1, &_Scale, _DSPSplitComplex.realp, 1, _FFTLength);
//    vDSP_vsmul(_DSPSplitComplex.imagp, 1, &_Scale, _DSPSplitComplex.imagp, 1, _FFTLength);

//    for (UInt32 i = 0; i < _FFTLength; ++i) {
//        bitmap[i] = (int)(_DSPSplitComplex.realp[i] * 255.0);
//    }
//
//    return;
    

    // Rearrange output sectors
    UInt32 rowSrc, rowDst, rowMax, colSrc, colDst, colMax;
    
    rowMax = _FFTHalfHeight * _FFTWidth;

    // swap SE and NW Sectors
    for (rowDst = 0, rowSrc = 128 * _FFTWidth + 128; rowDst < rowMax; rowDst += _FFTWidth, rowSrc += _FFTWidth ) {
        colMax = rowDst + _FFTHalfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc] * 255.0);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst] * 255.0);
        }
    }

    rowMax = _FFTHeight * _FFTWidth;
    // swap NE and SW Sectors
    for (rowDst = 128 * _FFTWidth, rowSrc = 0 * _FFTWidth + 128; rowDst < rowMax; rowDst += _FFTWidth, rowSrc += _FFTWidth ) {
        colMax = rowDst + _FFTHalfWidth;
        for (colDst = rowDst, colSrc = rowSrc; colDst < colMax; colDst++, colSrc++) {
            bitmap[colDst] = (int)(_DSPSplitComplex.realp[colSrc] * 255.0);
            bitmap[colSrc] = (int)(_DSPSplitComplex.realp[colDst] * 255.0);
        }
    }
}

/******************************************************************************/


@end
