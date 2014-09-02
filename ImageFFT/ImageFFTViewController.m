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
    
    // TODO: fix bounds. bounds are zero for some reason.
    
    _videoPreviewViewBounds = CGRectZero;
    _videoPreviewViewBounds.size.width = view.frame.size.width;
    _videoPreviewViewBounds.size.height = view.frame.size.height;
    
    _FFTWidth = 256;
    _FFTHeight = 256;
    
    _bitmap =  (Pixel_8 *)malloc(sizeof(Pixel_8) * _FFTWidth * _FFTHeight);
    
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

    CIImage * image = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    image = [self filterSquareImage:image];
    image = [self filterGrayscaleImage:image];
    image = [self filterFFTImage:image];
    
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
    float scale = 255.0f / width;
    
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
    
    *(bitmap + (5 * 256) + 128) = 0xFF;
    *(bitmap + (5 * 256) + 127) = 0x00;
    
    NSLog(@"[%d] [%d]", *bitmap, *(bitmap + 100));

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


@end
