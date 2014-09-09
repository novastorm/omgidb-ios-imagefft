//
//  FFT2D.h
//  ImageFFT
//
//  Created by Adland Lee on 9/8/14.
//  Copyright (c) 2014 Adland Lee. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFT2D : NSObject

+ (id) initWithImage:(CIImage *)image;

- (id) init;
- (void) setupForImage:(CIImage *)image;
- (CIImage *) filterFFTForImage:(CIImage *)inImage;

@end
