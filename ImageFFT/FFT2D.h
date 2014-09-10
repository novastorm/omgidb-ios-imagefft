//
//  FFT2D.h
//  ImageFFT
//
//  Created by Adland Lee on 9/8/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFT2D : NSObject

+ (FFT2D *) FFT2DWithImage:(CIImage *)image;

- (id) init;
- (id) initWithImage:(CIImage *)image;

- (void) reinitWithImage:(CIImage *)image;

- (CIImage *) filterFFTForImage:(CIImage *)inImage;

@end
