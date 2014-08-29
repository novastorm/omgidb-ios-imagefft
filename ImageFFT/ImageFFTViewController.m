//
//  ViewController.m
//  ImageFFT
//
//  Created by Adland Lee on 8/18/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

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

    CIImage * sourceImage = [self imageFromSampleBuffer:sampleBuffer];
  
    CIImage * drawImage = [self filterImage:sourceImage];

    CGRect sourceRect = sourceImage.extent;
    sourceRect.size.width = sourceRect.size.height;

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
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
//    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
//    size_t planes = CVPixelBufferGetPlaneCount(imageBuffer);
    
//    NSLog(@"S[%lu] P[%lu]"
//          , CVPixelBufferGetDataSize(imageBuffer)
//          , planes
//    );
//    
//    for (size_t i = 0; i < planes; i++) {
//        NSLog(@"%lu: BpR[%lu] W[%lu] H[%lu]"
//              , i
//              , CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i)
//              , CVPixelBufferGetWidthOfPlane(imageBuffer, i)
//              , CVPixelBufferGetHeightOfPlane(imageBuffer, i)
//        );
//    }
    
//    // Create a device-dependent RGB color space
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//    
//    // Create a bitmap graphics context with the sample buffer data
//    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
//                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//    // Create a Quartz image from the pixel data in the bitmap graphics context
//    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
//    // Unlock the pixel buffer
//    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
//    CGContextRelease(context);
//    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
//    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
//    CGImageRelease(quartzImage);

    CIImage * image = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    image = [self filterSquareImage:image];
    image = [self filterGrayscaleImage:image];
    
    CGRect cropRect = image.extent;
    
    if (cropRect.size.width < cropRect.size.height) {
        cropRect.size.height = cropRect.size.width;
    }
    else {
        cropRect.size.width = cropRect.size.height;
    }

    [_CIContext render:image toCVPixelBuffer:imageBuffer bounds:cropRect colorSpace:CGColorSpaceCreateDeviceRGB()];
//    [_CIContext render:image toCVPixelBuffer:imageBuffer];

//    size_t planes = CVPixelBufferGetPlaneCount(imageBuffer);
//
//    NSLog(@"S[%lu] P[%lu]"
//          , CVPixelBufferGetDataSize(imageBuffer)
//          , planes
//    );
//
//    for (size_t i = 0; i < planes; i++) {
//        NSLog(@"%lu: BpR[%lu] W[%lu] H[%lu]"
//              , i
//              , CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i)
//              , CVPixelBufferGetWidthOfPlane(imageBuffer, i)
//              , CVPixelBufferGetHeightOfPlane(imageBuffer, i)
//        );
//    }
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

    return [CIImage imageWithCVPixelBuffer:imageBuffer];
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
 Create a Filtered CIImage from input CIImage
 ******************************************************************************/
- (CIImage *) filterImage:(CIImage *)inImage
{
    CIImage * outImage = inImage;
    
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
