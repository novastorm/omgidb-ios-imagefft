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
#import "FFT2D.h"

@interface ImageFFTViewController () {
    CIContext * _CIContext;
    EAGLContext* _EAGLContext;
    CGRect _PrimaryViewerBounds;
    CGRect _SecondaryViewerBounds;
    
//    CVOpenGLESTextureRef _lumaTexture;
//    CVOpenGLESTextureRef _chromaTexture;
//    
    NSString* _sessionPreset;
    AVCaptureSession* _session;
    
    CVOpenGLESTextureCacheRef _videoTextureCache;
    
    FFT2D * _FFT2D;

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

//const Float32 kAdjust0DB = 1.5849e-13;
//const Float32 one = 1;

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
    CGRect bounds = {0,0, 256,256};
    
    _FFT2D = [FFT2D FFT2DWithBounds:bounds];
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

    CIImage * drawImage = [_FFT2D FFTWithCIImage:image context:_CIContext];

    CGRect sourceRect = drawImage.extent;
    
    [_CIContext drawImage:image inRect:_SecondaryViewerBounds fromRect:sourceRect];
    [_CIContext drawImage:drawImage inRect:_PrimaryViewerBounds fromRect:sourceRect];
    
    [(GLKView *)self.view display];
    
//    [self cleanUpTextures];
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

///******************************************************************************/
//- (void) cleanUpTextures
//{
//    if (_lumaTexture) {
//        CFRelease(_lumaTexture);
//        _lumaTexture = NULL;
//    }
//    
//    if (_chromaTexture) {
//        CFRelease(_chromaTexture);
//        _chromaTexture = NULL;
//    }
//    
//    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
//}

/******************************************************************************/


@end
