//
//  TRIPPaletteColorUtils.m
//  Atom
//
//  Created by dylan.tang on 17/4/14.
//  Copyright © 2017年 dylan.tang All rights reserved.
//

#import "PaletteColorUtils.h"

const NSInteger QUANTIZE_WORD_WIDTH_COLOR = 5;
const NSInteger QUANTIZE_WORD_MASK_COLOR = (1 << QUANTIZE_WORD_WIDTH_COLOR) - 1;

@implementation PaletteColorUtils
+ (NSInteger)quantizedRed:(NSInteger)color{
    NSInteger red =  (color >> (QUANTIZE_WORD_WIDTH_COLOR + QUANTIZE_WORD_WIDTH_COLOR)) & QUANTIZE_WORD_MASK_COLOR;
    return red;
}

+ (NSInteger)quantizedGreen:(NSInteger)color{
    NSInteger green = (color >> QUANTIZE_WORD_WIDTH_COLOR) & QUANTIZE_WORD_MASK_COLOR;
    return green;
}

+ (NSInteger)quantizedBlue:(NSInteger)color{
    NSInteger blue = color & QUANTIZE_WORD_MASK_COLOR;
    return blue;
}

+ (NSInteger)modifyWordWidthWithValue:(NSInteger)value currentWidth:(NSInteger)currentWidth targetWidth:(NSInteger)targetWidth{
    NSInteger newValue;
    if (targetWidth > currentWidth) {
        // If we're approximating up in word width, we'll use scaling to approximate the
        // new value
        newValue = value * ((1 << targetWidth) - 1) / ((1 << currentWidth) - 1);
    } else {
        // Else, we will just shift and keep the MSB
        newValue = value >> (currentWidth - targetWidth);
    }
    return newValue & ((1 << targetWidth) - 1);
}

NSArray * rgb555ToHSL(NSInteger rgb555){
    // RGB555 -> RGB888
    NSInteger red = [PaletteColorUtils quantizedRed:rgb555];
    NSInteger green = [PaletteColorUtils quantizedGreen:rgb555];
    NSInteger blue = [PaletteColorUtils quantizedBlue:rgb555];
    
    red = [PaletteColorUtils modifyWordWidthWithValue:red currentWidth:5 targetWidth:8];
    green = [PaletteColorUtils modifyWordWidthWithValue:green currentWidth:5 targetWidth:8];
    blue = [PaletteColorUtils modifyWordWidthWithValue:blue currentWidth:5 targetWidth:8];
    // RGB888 -> HSL
    return rgb888ToHSL(red,green,blue);
}

NSArray * rgb888ToHSL(NSInteger red,NSInteger green,NSInteger blue){
    float rf,gf,bf;
    rf = (float)red /255.0f, gf =  (float)green / 255.f, bf = (float)blue / 255.f;
    float max,min;
    max = MAX(rf, gf) > bf?MAX(rf, gf):bf;
    min = MIN(rf, gf) < bf?MIN(rf, gf):bf;
    float deltaMaxMin = max - min;
    
    float l = (max+min)/2.0;
    float h,s;
    
    if(max == min){
        h = s = 0.0F;
    }else{
        if (max == rf){
            h = truncatingRemainderDividing((gf - bf)/deltaMaxMin,6.0F);
//            h = (gf - bf)/deltaMaxMin % 6.0F;
        }else{
            if (max == gf){
                h = (bf - rf)/deltaMaxMin + 2.0F;
            }else{
                h = (rf - gf)/deltaMaxMin + 4.0F;
            }
        }
        
        s = deltaMaxMin / (1.0f - fabsf(2.0f * l - 1.0f));
    }

//    h = h * 60.0F % 360.0F;
    h = truncatingRemainderDividing(h * 60.0F,360.0F);
    if (h<0.0F){
        h += 360.0F;
    }
    NSArray *hsl = @[[NSNumber numberWithFloat:constrain(h, 0.0F, 360.0F)],
                     [NSNumber numberWithFloat:constrain(s, 0.0F, 1.0F)],
                     [NSNumber numberWithFloat:constrain(l, 0.0F, 1.0F)]];
    return hsl;
}

float truncatingRemainderDividing(float a,float b){
    NSInteger intA = a * 1000000;
    NSInteger intB = b * 1000000;
    NSInteger intC = intA % intB;
    return intC/1000000.0f;
}

float constrain(float amount,float low,float high){
    return amount > high ? high : amount < low ? low : amount;
}

@end
