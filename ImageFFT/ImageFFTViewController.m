//
//  ViewController.m
//  ImageFFT
//
//  Created by Adland Lee on 8/18/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import "ImageFFTViewController.h"

#import "FFT2D.h"

#import <Accelerate/Accelerate.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreVideo/CVOpenGLESTextureCache.h>

typedef enum {
    displayFFTImage
    , displayCameraImage
} HIPDisplayImage;

@interface ImageFFTViewController ()

@property (nonatomic) UIView * flashView;

@property (nonatomic) CIContext * CIContext;
@property (nonatomic) EAGLContext * EAGLContext;

@property (nonatomic) NSString* sessionPreset;

@property (nonatomic) CVOpenGLESTextureCacheRef videoTextureCache;

@property (nonatomic) CGFloat effectiveScale;

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t FFTQueue;

@property (nonatomic) AVCaptureSession *session;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;

@property (nonatomic) AVCaptureStillImageOutput * stillImageOutput;

@property (nonatomic) CGRect primaryViewerBounds;
@property (nonatomic) CGRect secondaryViewerBounds;
@property (nonatomic) FFT2D * aFFT2D;

@property (nonatomic) HIPDisplayImage primaryViewerDisplayImage;
@property (nonatomic) HIPDisplayImage secondaryViewerDisplayImage;

@property (nonatomic) CIImage * cameraImage;
@property (nonatomic) CIImage * fftImage;

@property (nonatomic) CIImage * primaryDisplayImage;
@property (nonatomic) CIImage * secondaryDisplayImage;



@end

@implementation ImageFFTViewController

static void * AVCaptureStillImageIsCapturingStillImageContext = &AVCaptureStillImageIsCapturingStillImageContext;

- (BOOL)isSessionRunningAndDeviceAuthorized
{
    return [self.session isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
    return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.session = [[AVCaptureSession alloc] init];

    // Check for device authorization
    [self checkDeviceAuthorizationStatus];

    self.EAGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    self.CIContext = [CIContext contextWithEAGLContext:self.EAGLContext options:@{kCIContextOutputColorSpace: [NSNull null]} ];
    
    if (! self.EAGLContext) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView * view = (GLKView *)self.view;
    view.context = self.EAGLContext;
    
//    self.preferredFramesPerSecond = 60;
    
    view.contentScaleFactor = [UIScreen mainScreen].scale;
    
    self.sessionPreset = AVCaptureSessionPreset352x288;
    
    CGFloat width = view.frame.size.width * view.contentScaleFactor;
    CGFloat height = view.frame.size.height * view.contentScaleFactor;
    
    self.primaryViewerBounds = (CGRect){
        0
        , height - width
        , width
        , width
    };
    
    self.secondaryViewerBounds = (CGRect){
        0.5f * view.frame.size.width
        , 0.25f * view.frame.size.width
        , view.frame.size.width
        , view.frame.size.width
    };
    
    self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    
    self.primaryViewerDisplayImage = displayFFTImage;
    self.secondaryViewerDisplayImage = displayCameraImage;

    [self setupFFTAnalysis];
    [self setupGL];
    [self setupAVCapture];
}

- (BOOL)prefersStatusBarHidden
{
    return true;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void) setupGL
{
    [EAGLContext setCurrentContext:self.EAGLContext];
}

- (void) setupAVCapture
{
    dispatch_async(self.sessionQueue, ^{
    #if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.EAGLContext, NULL, &_videoTextureCache);
    #else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)_context, NULL, &_videoTextureCache);
    #endif
        if (err)
        {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
        
        [self.session beginConfiguration];
        
        [self.session setSessionPreset:self.sessionPreset];
        
        AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (nil == videoDevice) assert(0);
        NSError* error;
        AVCaptureDeviceInput* videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        if (error) assert(0);
        [self.session addInput:videoDeviceInput];
        

        self.stillImageOutput = [AVCaptureStillImageOutput new];
        [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:AVCaptureStillImageIsCapturingStillImageContext];
        [self.session addOutput:self.stillImageOutput];
        

        AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
        [videoDataOutput setVideoSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            }
         ];
        [videoDataOutput setSampleBufferDelegate:self queue:self.sessionQueue];
        [self.session addOutput:videoDataOutput];

        self.effectiveScale = 1.0;

        [self.session commitConfiguration];
        
        [self.session startRunning];
    });
}

- (void) setupFFTAnalysis
{
    CGRect bounds = {0,0, 256,256};
    
    self.aFFT2D = [FFT2D FFT2DWithBounds:bounds context:self.CIContext];
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput
	didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection *)connection
{
    if (! self.videoTextureCache) {
        NSLog(@"No video texture cache");
        return;
    }

    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    self.cameraImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    self.cameraImage = [self filterImage:self.cameraImage];

    self.fftImage = [self.aFFT2D FFTWithCIImage:self.cameraImage];
    
    if (self.primaryViewerDisplayImage == displayCameraImage) {
        self.primaryDisplayImage = self.cameraImage;
    }
    else {
        self.primaryDisplayImage = self.fftImage;
    }
    
    if (self.secondaryViewerDisplayImage == displayFFTImage) {
        self.secondaryDisplayImage = self.fftImage;
    }
    else {
        self.secondaryDisplayImage = self.cameraImage;
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.CIContext drawImage:self.primaryDisplayImage inRect:self.primaryViewerBounds fromRect:self.primaryDisplayImage.extent];
        [self.CIContext drawImage:self.secondaryDisplayImage inRect:self.secondaryViewerBounds fromRect:self.secondaryDisplayImage.extent];

        [(GLKView *)self.view display];
    });
    
    [self cleanUpTextures];
}

/**
 Create a CIImage from sample buffer data
 */
- (CIImage *) filterImage:(CIImage *)image
{
    image = [self filterSquareImage:image];
    image = [self filterGrayscaleImage:image];
    image = [self filterScaleImage:image fromSize:image.extent.size.width toSize:256];

    return image;
}

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

- (CIImage *) filterGrayscaleImage:(CIImage *)inImage
{
    return [CIFilter filterWithName:@"CIMaximumComponent"
        keysAndValues:
            kCIInputImageKey, inImage
            , nil
        ].outputImage;
}

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

- (CIImage *) filterRotateImage:(CIImage *)inImage withDegree:(CGFloat)degree
{
    return [inImage imageByApplyingTransform:CGAffineTransformMakeRotation(GLKMathDegreesToRadians(degree))];
}

- (CIImage *) filterRotateImage90CW:(CIImage *)inImage
{
    return [self filterRotateImage:inImage withDegree:-90.0f];
}

- (void) cleanUpTextures
{
    CVOpenGLESTextureCacheFlush(self.videoTextureCache, 0);
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    AVCaptureVideoOrientation result = (AVCaptureVideoOrientation)deviceOrientation;
    if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
        result = AVCaptureVideoOrientationLandscapeRight;
    else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
        result = AVCaptureVideoOrientationLandscapeLeft;
    else if ( deviceOrientation == UIDeviceOrientationPortraitUpsideDown)
        result = AVCaptureVideoOrientationPortraitUpsideDown;
    else
        result = AVCaptureVideoOrientationPortrait;
    return result;
}

- (UIImageOrientation)uiOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    UIImageOrientation result = (UIImageOrientation)deviceOrientation;
    if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
        result = UIImageOrientationLeft;
    else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
        result = UIImageOrientationRight;
    else if ( deviceOrientation == UIDeviceOrientationPortraitUpsideDown)
        result = UIImageOrientationDown;
    else // UIDeviceOrientationPortraitUp
        result = UIImageOrientationUp;
    return result;
}

// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                                            message:[error localizedDescription]
                                                           delegate:nil
                                                  cancelButtonTitle:@"Dismiss"
                                                  otherButtonTitles:nil];
        [alertView show];
    });
}

- (IBAction)takePicture:(id)sender
{
    AVCaptureConnection * stillImageConnection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    UIDeviceOrientation currentDeviceOrientation = [[UIDevice currentDevice] orientation];
    
    [self.stillImageOutput setOutputSettings:@{
        (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        }];
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError * error) {
        if (error) {
            [self displayErrorOnMainQueue:error withMessage:@"Take picture failed"];
        }
        else {
            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer);
            if (! imageBuffer) {
                NSLog(@"Unable to get imageBuffer from data sample");
            }

            CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);

            CIImage * image = [CIImage imageWithCVPixelBuffer:imageBuffer options:(__bridge NSDictionary *)attachments];
            
            image = [self filterRotateImage90CW:image]; // rotate image to match video portrait orientation
            image = [self filterImage:image];

            CGImageRef aCGImage = [self.CIContext createCGImage:image fromRect:image.extent];

            if (! aCGImage) {
                NSLog(@"cannot get a CGImage from image");
            }

            UIImage * imageToSave = [UIImage imageWithCGImage:aCGImage scale:0 orientation:[self uiOrientationForDeviceOrientation:currentDeviceOrientation]];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageWriteToSavedPhotosAlbum(imageToSave, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
            });

            CGImageRelease(aCGImage);

            if (attachments) CFRelease(attachments);
        }
    }];
}
- (IBAction)swapDisplayWindows:(id)sender {
    if (self.primaryViewerDisplayImage == displayCameraImage) {
        self.primaryViewerDisplayImage = displayFFTImage;
        self.secondaryViewerDisplayImage = displayCameraImage;
    }
    else { //if (self.primaryViewerDisplayImage == displayFFTImage) {
        self.primaryViewerDisplayImage = displayCameraImage;
        self.secondaryViewerDisplayImage = displayFFTImage;
    }
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo: (void *) contextInfo
{
    
    if (error) {
        [self displayErrorOnMainQueue:error withMessage:@"Save to camera roll failed"];
    }
}

// perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == AVCaptureStillImageIsCapturingStillImageContext ) {
        BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
        
        if ( isCapturingStillImage ) {
            // do flash bulb like animation
            self.flashView = [[UIView alloc] initWithFrame:self.view.frame];
            [self.flashView setBackgroundColor:[UIColor whiteColor]];
            [self.flashView setAlpha:0.f];
            [[[self view] window] addSubview:self.flashView];
            
            [UIView animateWithDuration:.4f
                             animations:^{
                                 [self.flashView setAlpha:1.f];
                             }
             ];
        }
        else {
            [UIView animateWithDuration:.4f
                             animations:^{
                                 [self.flashView setAlpha:0.f];
                             }
                             completion:^(BOOL finished){
                                 [self.flashView removeFromSuperview];
                                 //                                 [flashView release];
                                 self.flashView = nil;
                             }
             ];
        }
    }
}

- (void) checkDeviceAuthorizationStatus
{
    NSString * mediaType = AVMediaTypeVideo;
    
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        NSLog(granted ? @"YES" : @"NO");
        if (granted) {
            self.deviceAuthorized = YES;
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[[UIAlertView alloc] initWithTitle:@"ImageFFT!" message:@"ImageFFT does not have permission to use Camera, please change privacy settings" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                self.deviceAuthorized = NO;
            });
        }
    }];
}


@end
