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
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
//    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);

    CIImage * aCIImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    aCIImage = [self filterSquareImage:aCIImage];
    aCIImage = [self filterGrayscaleImage:aCIImage];
    aCIImage = [self filterFFTImage:aCIImage];
    
    UIImage * aUIImage = [UIImage imageWithCIImage:aCIImage];
    
    return [aUIImage CIImage];

    size_t width = 256;
    size_t height = 256;
    CGRect bounds = CGRectMake(0, 0, 256, 256);

    Pixel_8 * bitmap =  (Pixel_8 *)malloc(width * height * sizeof(Pixel_8));

    size_t bytesPerPixel = 1;
    size_t bitsPerComponent = 8;
    size_t bytesPerRow = bytesPerPixel * width;
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

    CGBitmapInfo bitmapInfo = kCGImageAlphaNone;
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(bitmap, width, height, bitsPerComponent,
                                                 bytesPerRow, colorSpace, bitmapInfo);
    
    if (context == NULL) {
        NSLog(@"Could not create CGContext");
        return nil;
    }

    CGContextDrawImage(context, bounds, [aUIImage CGImage]);
    
//    NSLog(@"[%02hhX] [%02hhX]", *bitmap, *(bitmap+1));
    
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Create an image object from the Quartz image
    aUIImage = [UIImage imageWithCGImage:quartzImage];
//    CGSize size = CGSizeMake(bounds.size.width, bounds.size.height);
//    NSData * bitmapData = [NSData dataWithBytesNoCopy:bitmap length:bytesPerRow * height];
//
//    if (bitmapData == nil) {
//        NSLog(@"Could not create bitmapData from bitmap");
//        return nil;
//    }
//    
//    NSLog(@"%lu", (unsigned long)bitmapData.length);

////    aCIImage = [CIImage imageWithBitmapData:bitmapData bytesPerRow:bytesPerRow size:size format:format colorSpace:colorSpace];
//    aUIImage = [UIImage imageWithData:bitmapData];
//    
//    if (aUIImage == nil) {
//        NSLog(@"Could not create UIImage from bitmapData");
//        return nil;
//    }
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Release the Quartz image
//    CGImageRelease(quartzImage);

    
//    image = [self filterSquareImage:image];
//    image = [self filterGrayscaleImage:image];
    aCIImage = [self filterFFTImage:[aUIImage CIImage]];
    
//    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

    return aCIImage;
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
    CIImage * outImage;

    size_t width = inImage.extent.size.width;
    size_t height = inImage.extent.size.height;
    
    NSLog(@"FFT input W[%lu] H[%lu]", width, height);
    
    float scale = 255.0f / width;
    
    CIFilter * filter = [CIFilter filterWithName:@"CILanczosScaleTransform"
    	keysAndValues:
            kCIInputImageKey, inImage
            , @"inputScale", [NSNumber numberWithFloat:scale]
            , nil];
    
    outImage = [filter valueForKey:kCIOutputImageKey];

    NSLog(@"FFT output W[%f] H[%f]"
    	, outImage.extent.size.width
        , outImage.extent.size.height
        );

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
