//
//  FFT2D.h
//  ImageFFT
//
//  Created by Adland Lee on 9/8/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFT2D : NSObject

+ (instancetype) FFT2DWithBounds:(CGRect)bounds;
+ (instancetype) FFT2DWithBounds:(CGRect)bounds context:(CIContext *)context;

- (instancetype) init;
- (instancetype) initWithBounds:(CGRect)bounds;
- (instancetype) initWithBounds:(CGRect)bounds context:(CIContext *)context;

@property (nonatomic) CIContext * context;
@property CGRect bounds;

- (CIImage *) FFTWithCGImage:(CGImageRef)image;

- (CIImage *) FFTWithCIImage:(CIImage *)image;
- (CIImage *) FFTWithCIImage:(CIImage *)image context:(CIContext *)context;

@end
