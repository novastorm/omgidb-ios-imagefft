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
    _videoPreviewViewBounds.size.width = view.drawableWidth;
    _videoPreviewViewBounds.size.height = view.drawableHeight;
    
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
- (void) captureOutput:(AVCaptureOutput *)captureOutput
	didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection *)connection
{
    if (! _videoTextureCache) {
        NSLog(@"No video texture cache");
        return;
    }

//    CVReturn err;
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

//    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
//    GLubyte * rawImageBytes = CVPixelBufferGetBaseAddress(pixelBuffer);
    
//    NSLog(@"%u", CVPixelBufferGetPlaneCount(imageBuffer));
//    NSLog(@"%u", CVPixelBufferGetDataSize(imageBuffer));
    
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
//    NSData * dataForRawBytes = [NSData dataWithBytes:rawImageBytes length:bytesPerRow];

    CIImage * sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer options:nil];
    CGRect sourceExtent = sourceImage.extent;
    
    GLKView * view = (GLKView *)self.view;

//    CGFloat sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
//    CGFloat previewAspect = _videoPreviewViewBounds.size.width  / _videoPreviewViewBounds.size.height;
    
    // we want to maintain the aspect radio of the screen size, so we clip the video image
    CGRect drawRect = sourceExtent;
    drawRect.size.width = _videoPreviewViewBounds.size.height;
    drawRect.size.height = _videoPreviewViewBounds.size.height;
    
//    if (sourceAspect > previewAspect)
//    {
//        // use full height of the video image, and center crop the width
//        drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
//        drawRect.size.width = drawRect.size.height * previewAspect;
//    }
//    else
//    {
//        // use full width of the video image, and center crop the height
//        drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
//        drawRect.size.height = drawRect.size.width / previewAspect;
//    }

    [view bindDrawable];
    
    CGRect cropRect = sourceExtent;
    cropRect.size.width = 256;
    cropRect.size.height = 256;
    
    CIImage * filteredImage = [sourceImage imageByCroppingToRect:cropRect];
//    CIImage * filteredImage;
    
//    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)imageBuffer;
//    CVPixelBufferCreate(NULL
//    	, 256
//        , 256
//        , [NSDictionary
//           dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
//           forKey:(id)kCVPixelBufferPixelFormatTypeKey]
//        , NULL
//        , &pixelBuffer
//        );
    
//    NSLog(@"%lu", CVPixelBufferGetDataSize(pixelBuffer));
//    NSLog(@"%lu", CVPixelBufferGetBytesPerRow(pixelBuffer));
//    NSLog(@"H[%lu]W[%lu]"
//    	, CVPixelBufferGetHeight(pixelBuffer)
//        , CVPixelBufferGetWidth(pixelBuffer)
//        );
    
//    filteredImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

    CIImage * drawImage = filteredImage;
    
    [_CIContext drawImage:drawImage inRect:drawRect fromRect:sourceImage.extent];
    [view display];
    
    [self cleanUpTextures];
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
