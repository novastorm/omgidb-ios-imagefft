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
+ (instancetype) FFT2DWithImage:(CIImage *)image;

- (id) init;
- (id) initWithBounds:(CGRect)bounds;
- (id) initWithImage:(CIImage *)image;

- (void) reinitWithBounds:(CGRect)bounds;
- (void) reinitWithImage:(CIImage *)image;

- (CIImage *) FFTWithCGImage:(CGImageRef)image;
- (CIImage *) FFTWithCIImage:(CIImage *)image context:(CIContext *)context;

@end
