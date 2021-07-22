//
//  Palette.m
//
//  Created by dylan.tang on 17/4/11.
//  Copyright © 2017年 dylan.tang All rights reserved.
//

#import "Palette.h"
#import "PaletteSwatch.h"
#import "PaletteColorUtils.h"
#import "PriorityBoxArray.h"

typedef NS_ENUM(NSInteger,COMPONENT_COLOR){
    COMPONENT_RED = 0,
    COMPONENT_GREEN = 1,
    COMPONENT_BLUE = 2
};

const NSInteger QUANTIZE_WORD_WIDTH = 5;
const NSInteger QUANTIZE_WORD_MASK = (1 << QUANTIZE_WORD_WIDTH) - 1;
const CGFloat resizeArea = 112 * 112;

int hist[32768];// 2进制 2的15次幂 1000000000000000

/**
 VBox是一个新的概念，它理解起来稍微抽象一点。
 可以这样来理解，我们拥有的颜色过多，但是我们只需要提取出例如16种颜色，
 用16个“筐”把颜色相近的颜色筐在一起，最终用每个筐的平均颜色来代表提取出来的16种主色调
 */

@interface VBox()

// lowerIndex和upperIndex指的是在所有的颜色数组distinctColors中，VBox所持有的颜色范围
// distinctColors中，VBox所持有的lowerIndex。
@property (nonatomic,assign) NSInteger lowerIndex;
// distinctColors中，VBox所持有的upperIndex。
@property (nonatomic,assign) NSInteger upperIndex;

@property (nonatomic,strong) NSMutableArray *distinctColors;
// VBox所持有的颜色范围中，一共有多少个像素点
@property (nonatomic,assign) NSInteger population;
// 以下为R,G,B值各自的最大最小值。
@property (nonatomic,assign) NSInteger minRed;

@property (nonatomic,assign) NSInteger maxRed;

@property (nonatomic,assign) NSInteger minGreen;

@property (nonatomic,assign) NSInteger maxGreen;

@property (nonatomic,assign) NSInteger minBlue;

@property (nonatomic,assign) NSInteger maxBlue;

@end

@implementation VBox

- (instancetype)initWithLowerIndex:(NSInteger)lowerIndex upperIndex:(NSInteger)upperIndex colorArray:(NSMutableArray*)colorArray{
    self = [super init];
    if (self){
        
        _lowerIndex = lowerIndex;
        _upperIndex = upperIndex;
        _distinctColors = colorArray;
    
        [self fitBox];
        
    }
    return self;
}

- (NSInteger)getVolume{
    NSInteger volume = (_maxRed - _minRed + 1) * (_maxGreen - _minGreen + 1) *
    (_maxBlue - _minBlue + 1);
    return volume;
}

/**
 * Split this color box at the mid-point along it's longest dimension
 *
 * @return the new ColorBox
 */
- (VBox*)splitBox{
    if (![self canSplit]) {
        return nil;
    }
    
    // find median along the longest dimension
    NSInteger splitPoint = [self findSplitPoint];
    
    VBox *newBox = [[VBox alloc]initWithLowerIndex:splitPoint+1 upperIndex:_upperIndex colorArray:_distinctColors];
    
    // Now change this box's upperIndex and recompute the color boundaries
    _upperIndex = splitPoint;
    [self fitBox];
    
    return newBox;
}

- (NSInteger)findSplitPoint{
    NSInteger longestDimension = [self getLongestColorDimension];
    
    // We need to sort the colors in this box based on the longest color dimension.
    // As we can't use a Comparator to define the sort logic, we modify each color so that
    // it's most significant is the desired dimension
    [self modifySignificantOctetWithDismension:longestDimension lowerIndex:_lowerIndex upperIndex:_upperIndex];
    
    [self sortColorArray];
    
    // Now revert all of the colors so that they are packed as RGB again
    [self modifySignificantOctetWithDismension:longestDimension lowerIndex:_lowerIndex upperIndex:_upperIndex];

//    modifySignificantOctet(colors, longestDimension, mLowerIndex, mUpperIndex);
    
    NSInteger midPoint = _population / 2;
    for (NSInteger i = _lowerIndex, count = 0; i <= _upperIndex; i++)  {
        NSInteger population = hist[[_distinctColors[i] intValue]];
        count += population;
        if (count >= midPoint) {
            return i;
        }
    }
    
    return _lowerIndex;
}

- (void)sortColorArray{
    
    // Now sort... Arrays.sort uses a exclusive toIndex so we need to add 1
    
    NSInteger sortCount = (_upperIndex - _lowerIndex) + 1;
    NSInteger sortArray[sortCount];
    NSInteger sortIndex = 0;
    
    for (NSInteger index = _lowerIndex;index<= _upperIndex ;index++){
        sortArray[sortIndex] = [_distinctColors[index] integerValue];
        sortIndex++;
    }
    
    NSInteger arrayLength = sortIndex;
    
    //bubble sort
    for(NSInteger i = 0; i < arrayLength-1; i++)
    {
        BOOL isSorted = YES;
        for(NSInteger j=0; j<arrayLength-1-i; j++)
        {
            if(sortArray[j] > sortArray[j+1])
            {
                isSorted = NO;
                NSInteger temp = sortArray[j];
                sortArray[j] = sortArray[j+1];
                sortArray[j+1]=temp;
            }
        }
        if(isSorted)
            break;
    }
    
    sortIndex = 0;
    for (NSInteger index = _lowerIndex;index<= _upperIndex ;index++){
        _distinctColors[index] = [NSNumber numberWithInteger:sortArray[sortIndex]];
        sortIndex++;
    }
}

/**
 * @return the dimension which this box is largest in
 */
- (NSInteger) getLongestColorDimension{
    NSInteger redLength = _maxRed - _minRed;
    NSInteger greenLength = _maxGreen - _minGreen;
    NSInteger blueLength = _maxBlue - _minBlue;
    
    if (redLength >= greenLength && redLength >= blueLength) {
        return COMPONENT_RED;
    } else if (greenLength >= redLength && greenLength >= blueLength) {
        return COMPONENT_GREEN;
    } else {
        return COMPONENT_BLUE;
    }
}

/**
 * Modify the significant octet in a packed color int. Allows sorting based on the value of a
 * single color component. This relies on all components being the same word size.
 *
 * @see Vbox#findSplitPoint()
 */
- (void) modifySignificantOctetWithDismension:(NSInteger)dimension lowerIndex:(NSInteger)lower upperIndex:(NSInteger)upper{
    switch (dimension) {
        case COMPONENT_RED:
            // Already in RGB, no need to do anything
            break;
        case COMPONENT_GREEN:
            // We need to do a RGB to GRB swap, or vice-versa
            for (NSInteger i = lower; i <= upper; i++) {
                NSInteger color = [_distinctColors[i] intValue];
                NSInteger newColor = [PaletteColorUtils quantizedGreen:color] << (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH)
                | [PaletteColorUtils quantizedRed:color]  << QUANTIZE_WORD_WIDTH | [PaletteColorUtils quantizedBlue:color];
                _distinctColors[i] = [NSNumber numberWithInteger:newColor];
            }
            break;
        case COMPONENT_BLUE:
            // We need to do a RGB to BGR swap, or vice-versa
            for (NSInteger i = lower; i <= upper; i++) {
                NSInteger color = [_distinctColors[i] intValue];
                NSInteger newColor =  [PaletteColorUtils quantizedBlue:color] << (QUANTIZE_WORD_WIDTH + QUANTIZE_WORD_WIDTH)
                | [PaletteColorUtils quantizedGreen:color]  << QUANTIZE_WORD_WIDTH
                | [PaletteColorUtils quantizedRed:color];
                _distinctColors[i] = [NSNumber numberWithInteger:newColor];
            }
            break;
    }
}

/**
 * @return the average color of this box.
 */
- (PaletteSwatch*)getAverageColor{
    NSInteger redSum = 0;
    NSInteger greenSum = 0;
    NSInteger blueSum = 0;
    NSInteger totalPopulation = 0;
    
    for (NSInteger i = _lowerIndex; i <= _upperIndex; i++) {
        NSInteger color = [_distinctColors[i] intValue];
        NSInteger colorPopulation = hist[color];
        
        totalPopulation += colorPopulation;
        
        redSum += colorPopulation * [PaletteColorUtils quantizedRed:color];
        greenSum += colorPopulation * [PaletteColorUtils quantizedGreen:color];
        blueSum += colorPopulation * [PaletteColorUtils quantizedBlue:color];
    }
    
    //in case of totalPopulation equals to 0
    if (totalPopulation <= 0){
        return nil;
    }
    
    NSInteger redMean = redSum / totalPopulation;
    NSInteger greenMean = greenSum / totalPopulation;
    NSInteger blueMean = blueSum / totalPopulation;
    
    redMean = [PaletteColorUtils modifyWordWidthWithValue:redMean currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];
    greenMean = [PaletteColorUtils modifyWordWidthWithValue:greenMean currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];
    blueMean = [PaletteColorUtils modifyWordWidthWithValue:blueMean currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];

    NSInteger rgb888Color = redMean << 2 * 8 | greenMean << 8 | blueMean;
    
    PaletteSwatch *swatch = [[PaletteSwatch alloc]initWithColorInt:rgb888Color population:totalPopulation];
    
    return swatch;
}

- (BOOL)canSplit{
    if ((_upperIndex - _lowerIndex) <= 0){
        return NO;
    }
    return YES;
}

- (void)fitBox{
    
    // Reset the min and max to opposite values
    NSInteger minRed, minGreen, minBlue;
    minRed = minGreen = minBlue = 32768;
    NSInteger maxRed, maxGreen, maxBlue;
    maxRed = maxGreen = maxBlue = 0;
    NSInteger count = 0;
    
    for (NSInteger i = _lowerIndex; i <= _upperIndex; i++) {
        NSInteger color = [_distinctColors[i] intValue];
        count += hist[color];
        
        NSInteger r = [PaletteColorUtils quantizedRed:color];
        NSInteger g =  [PaletteColorUtils quantizedGreen:color];
        NSInteger b =  [PaletteColorUtils quantizedBlue:color];
        
        if (r > maxRed) {
            maxRed = r;
        }
        if (r < minRed) {
            minRed = r;
        }
        if (g > maxGreen) {
            maxGreen = g;
        }
        if (g < minGreen) {
            minGreen = g;
        }
        if (b > maxBlue) {
            maxBlue = b;
        }
        if (b < minBlue) {
            minBlue = b;
        }
    }
    
    _minRed = minRed;
    _maxRed = maxRed;
    _minGreen = minGreen;
    _maxGreen = maxGreen;
    _minBlue = minBlue;
    _maxBlue = maxBlue;
    _population = count;
}

@end

@interface PFilter : NSObject
- (BOOL)isAllowed:(NSArray *)hsl;
- (BOOL)isBlack:(NSArray *)hsl;
- (BOOL)isWhite:(NSArray *)hsl;
- (BOOL)isNearRedILine:(NSArray *)hsl;
@end

@interface Palette ()

@property (nonatomic,strong) UIImage *image;

@property (nonatomic,strong) PriorityBoxArray *priorityArray;

@property (nonatomic,strong) NSArray *swatchArray;

@property (nonatomic,strong) NSArray *targetArray;

@property (nonatomic,assign) NSInteger maxPopulation;

@property (nonatomic,strong) NSMutableArray *distinctColors;

/** the pixel count of the image */
@property (nonatomic,assign) NSInteger pixelCount;

/** callback */
@property (nonatomic,copy) GetColorBlock getColorBlock;

/** specify mode */
@property (nonatomic,assign) PaletteTargetMode mode;

/** needColorDic */
@property (nonatomic,assign) BOOL isNeedColorDic;

@property (nonatomic, strong) NSMutableArray <PFilter *> *mFilters;

@end

@implementation Palette

-(instancetype)initWithImage:(UIImage *)image{
    self = [super init];
    if (self){
        _image = image;
    }
    return self;
}

#pragma mark - Core code to analyze the main color of a image

- (void)startToAnalyzeImage:(GetColorBlock)block{
    [self startToAnalyzeForTargetMode:DEFAULT_NON_MODE_PALETTE withCallBack:block];
}

- (void)startToAnalyzeForTargetMode:(PaletteTargetMode)mode withCallBack:(GetColorBlock)block{
    // 创建mFiletes，后面过滤用
    self.mFilters = [NSMutableArray arrayWithArray:@[[PFilter new]]];
    
    // 创建要生成的目标颜色数组 NSArray * <PaletteTarget *>targetArray
    [self initTargetsWithMode:mode];
    
    //检测图片是否为空
    if (!_image){
        NSDictionary *userInfo = @{
            NSLocalizedDescriptionKey: NSLocalizedString(@"Operation fail", nil),
            NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The image is nill.", nil),
            NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Check the image input please", nil)
        };
        NSError *nullImageError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:userInfo];
        block(nil,nil,nullImageError);
        return;
    }
    _getColorBlock = block;
    [self startToAnalyzeImage];
}

// 开始分析图片
- (void)startToAnalyzeImage{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self clearHistArray]; // 清空Hist数组
        
        // 压缩图片，从图像中获取原始像素数据，将image转为rawData
        unsigned char *rawData = [self rawPixelDataFromImage:_image];
        if (!rawData || self.pixelCount <= 0){
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: NSLocalizedString(@"Operation fail", nil),
                NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The image is nill.", nil),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Check the image input please", nil)
            };
            NSError *nullImageError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:userInfo];
            _getColorBlock(nil,nil,nullImageError);
            return;
        }
        
        // 压缩图片，遍历图片像素，引出颜色直方图的概念。并将不同的颜色存入新的颜色数组
        NSInteger red,green,blue;
        for (int pixelIndex = 0 ; pixelIndex < self.pixelCount; pixelIndex++){
            red   = (NSInteger)rawData[pixelIndex*4+0];
            green = (NSInteger)rawData[pixelIndex*4+1];
            blue  = (NSInteger)rawData[pixelIndex*4+2];
            
            /**
             将RGB888颜色空间的颜色转变成RGB555颜色空间，这样就会使整个直方图数组以及颜色数组长度大大减小，又不会太影响计算结果。
             注：正常的RGB24是由24位即3个字节来描述一个像素，R、G、B各8位。而实际使用中为了减少图像数据的尺寸，如视频领域，对R、G、B所使用的位数进行的缩减，如：
                 RGB565（16位） 就是R-5bit，G-6bit，B-5bit
                 RGB555（16位） 就是R-5bit，G-5bit，B-5bit ；有1位未用
                 RGB888（24位） 就是R-8bit，G-8bit，B-8bit ；其实这就是RGB24
             */
            red = [PaletteColorUtils modifyWordWidthWithValue:red currentWidth:8 targetWidth:QUANTIZE_WORD_WIDTH];
            green = [PaletteColorUtils modifyWordWidthWithValue:green currentWidth:8 targetWidth:QUANTIZE_WORD_WIDTH];
            blue = [PaletteColorUtils modifyWordWidthWithValue:blue currentWidth:8 targetWidth:QUANTIZE_WORD_WIDTH];
            
            NSInteger quantizedColor = red << 2*QUANTIZE_WORD_WIDTH | green << QUANTIZE_WORD_WIDTH | blue;
            // 通过累加实现 ： hist [color] = color出现的次数
            hist [quantizedColor] ++;
        }
        
        free(rawData);
        
        // 将不同的颜色存进数组 distinctColors，留在后面进行判断。
        NSInteger distinctColorCount = 0; // 不同颜色的数量
        NSInteger length = sizeof(hist)/sizeof(hist[0]);
        _distinctColors = [[NSMutableArray alloc]init];
        
        for (NSInteger color = 0; color < length; color++){
            // 除去忽略的颜色
            if (hist[color] > 0 && [self shouldIgnoreColor:color]){
                hist[color] = 0;
            }
            if (hist[color] > 0){
                [_distinctColors addObject: [NSNumber numberWithInteger:color]];
                distinctColorCount ++;
            }
        }
       
        if (distinctColorCount <= kMaxColorNum){
            /**
             这里引出了一个新的概念，叫Swatch(样本)。
             Swatch是最终被作为参考进行模式筛选的数据结构，它有两个最主要的属性:
                1. Color：这个Color是最终要被展示出来的Color，所以需要的是RGB888空间的颜色。
                2. Population：它来自于hist直方图。是作为之后进行模式筛选的时候一个重要的权重因素。
             */
            NSMutableArray *swatchs = [[NSMutableArray alloc]init];
            for (NSInteger i = 0;i < distinctColorCount ; i++){
                NSInteger color = [_distinctColors[i] integerValue];
                NSInteger population = hist[color];
                
                NSInteger red = [PaletteColorUtils quantizedRed:color];
                NSInteger green = [PaletteColorUtils quantizedGreen:color];
                NSInteger blue = [PaletteColorUtils quantizedBlue:color];
                
                red = [PaletteColorUtils modifyWordWidthWithValue:red currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];
                green = [PaletteColorUtils modifyWordWidthWithValue:green currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];
                blue = [PaletteColorUtils modifyWordWidthWithValue:blue currentWidth:QUANTIZE_WORD_WIDTH targetWidth:8];
                
                color = red << 2 * 8 | green << 8 | blue;
                
                PaletteSwatch *swatch = [[PaletteSwatch alloc]initWithColorInt:color population:population];
                [swatchs addObject:swatch];
            }
            
            _swatchArray = [swatchs copy];
        }else{
            /**
                如果颜色个数超出了最大颜色数，则需要通过VBox分裂的方式，找到代表平均颜色的Swatch。
             */
            _priorityArray = [[PriorityBoxArray alloc]init];
            VBox *colorVBox = [[VBox alloc]initWithLowerIndex:0 upperIndex:distinctColorCount-1 colorArray:_distinctColors];
            [_priorityArray addVBox:colorVBox];
            // 分裂 VBox
            [self splitBoxes:_priorityArray];
            //将VBox 转为 Swatch样本，生成平均色数组
            self.swatchArray = [self generateAverageColors:_priorityArray];
        }
        
        [self findMaxPopulation];
        
        [self getSwatchForTarget];
    });

}

- (void)splitBoxes:(PriorityBoxArray*)queue{
    //queue is a priority queue.
    while (queue.count < kMaxColorNum) {
        VBox *vbox = [queue poll];
        if (vbox != nil && [vbox canSplit]) {
            // First split the box, and offer the result
            [queue addVBox:[vbox splitBox]];
            // Then offer the box back
            [queue addVBox:vbox];
        }else{
            NSLog(@"All boxes split");
            return;
        }
    }
}

- (NSArray*)generateAverageColors:(PriorityBoxArray*)array{
    NSMutableArray *swatchs = [[NSMutableArray alloc]init];
    NSMutableArray *vboxArray = [array getVBoxArray];
    for (VBox *vbox in vboxArray){
        PaletteSwatch *swatch = [vbox getAverageColor];
        if (swatch && ![self shouldIgnoreColorByHSL:swatch.getHsl]){
            [swatchs addObject:swatch];
        }
    }
    return [swatchs copy];
}

#pragma mark - image compress
//将image转为rawData
- (unsigned char *)rawPixelDataFromImage:(UIImage *)image{
    // 压缩图片至 resizeArea
    image = [self scaleDownImage:image];
    
    // 获取cgImage和其大小
    CGImageRef cgImage = [image CGImage];
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    
    // 创建rawData，为像素数据分配内存
    unsigned char *rawData = (unsigned char *)malloc(height * width * 4);
    
    // 如果失败，返回NULL
    if (!rawData) return NULL;
    
    // 创建色彩空间 (3色)
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Set some metrics
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    
    // 利用rawData创建 context 上下文
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    
    // 释放colorSpace
    CGColorSpaceRelease(colorSpace);
    
    // 绘制图像
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    
    // We are done with the context
    CGContextRelease(context);
    
    // 像素点数量
    self.pixelCount = (NSInteger)width * (NSInteger)height;
    
    // Return pixel data (needs to be freed)
    return rawData;
}

// 压缩图片
- (UIImage*)scaleDownImage:(UIImage*)image{
    CGImageRef cgImage = [image CGImage];
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    double scaleRatio;
    CGFloat imageSize = width * height;
    if (imageSize > resizeArea){
        scaleRatio = sqrt(resizeArea / ((double)imageSize));
        CGSize scaleSize = CGSizeMake((CGFloat)(width * scaleRatio),(CGFloat)(height * scaleRatio));
        UIGraphicsBeginImageContext(scaleSize);
        [_image drawInRect:CGRectMake(0.0f, 0.0f, scaleSize.width, scaleSize.height)];
        // 从当前context中创建一个改变大小后的图片
        UIImage* scaledImage =UIGraphicsGetImageFromCurrentImageContext();
        // 使当前的context出堆栈
        UIGraphicsEndImageContext();
        return scaledImage;
    }else{
        return image;
    }
}

- (void)initTargetsWithMode:(PaletteTargetMode)mode{
    NSMutableArray *targets = [[NSMutableArray alloc]init];
    
    if (mode < VIBRANT_PALETTE || mode > ALL_MODE_PALETTE || mode == ALL_MODE_PALETTE){
        
        PaletteTarget *vibrantTarget = [[PaletteTarget alloc]initWithTargetMode:VIBRANT_PALETTE];
        [targets addObject:vibrantTarget];
        
        PaletteTarget *mutedTarget = [[PaletteTarget alloc]initWithTargetMode:MUTED_PALETTE];
        [targets addObject:mutedTarget];
        
        PaletteTarget *lightVibrantTarget = [[PaletteTarget alloc]initWithTargetMode:LIGHT_VIBRANT_PALETTE];
        [targets addObject:lightVibrantTarget];
        
        PaletteTarget *lightMutedTarget = [[PaletteTarget alloc]initWithTargetMode:LIGHT_MUTED_PALETTE];
        [targets addObject:lightMutedTarget];

        PaletteTarget *darkVibrantTarget = [[PaletteTarget alloc]initWithTargetMode:DARK_VIBRANT_PALETTE];
        [targets addObject:darkVibrantTarget];

        PaletteTarget *darkMutedTarget = [[PaletteTarget alloc]initWithTargetMode:DARK_MUTED_PALETTE];
        [targets addObject:darkMutedTarget];
        
    }else{
        if (mode & (1 << 0)){
            PaletteTarget *vibrantTarget = [[PaletteTarget alloc]initWithTargetMode:VIBRANT_PALETTE];
            [targets addObject:vibrantTarget];
        }
        if (mode & (1 << 1)){
            PaletteTarget *lightVibrantTarget = [[PaletteTarget alloc]initWithTargetMode:LIGHT_VIBRANT_PALETTE];
            [targets addObject:lightVibrantTarget];
        }
        if (mode & (1 << 2)){
            PaletteTarget *darkVibrantTarget = [[PaletteTarget alloc]initWithTargetMode:DARK_VIBRANT_PALETTE];
            [targets addObject:darkVibrantTarget];
        }
        if (mode & (1 << 3)){
            PaletteTarget *lightMutedTarget = [[PaletteTarget alloc]initWithTargetMode:LIGHT_MUTED_PALETTE];
            [targets addObject:lightMutedTarget];
        }
        if (mode & (1 << 4)){
            PaletteTarget *mutedTarget = [[PaletteTarget alloc]initWithTargetMode:MUTED_PALETTE];
            [targets addObject:mutedTarget];
        }
        if (mode & (1 << 5)){
            PaletteTarget *darkMutedTarget = [[PaletteTarget alloc]initWithTargetMode:DARK_MUTED_PALETTE];
            [targets addObject:darkMutedTarget];
        }
    }
    _targetArray = [targets copy];
    
    if (mode >= VIBRANT_PALETTE && mode <= ALL_MODE_PALETTE){
        _isNeedColorDic = YES;
    }
}

#pragma mark - utils method
- (void)clearHistArray{
    for (NSInteger i = 0;i<32768;i++){
        hist[i] = 0;
    }
}

- (BOOL)shouldIgnoreColor:(NSInteger)color{
    NSArray * hsl = rgb555ToHSL(color);
    return [self shouldIgnoreColorByHSL:hsl];
}

- (BOOL)shouldIgnoreColorByHSL:(NSArray *)hsl{
    if (_mFilters && _mFilters.count > 0) {
        for (PFilter *filter in _mFilters) {
            if (![filter isAllowed:hsl]) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)findMaxPopulation{
    NSInteger max = 0;
    
    for (NSInteger i = 0; i <_swatchArray.count ; i++){
        PaletteSwatch *swatch = [_swatchArray objectAtIndex:i];
        NSInteger swatchPopulation = [swatch getPopulation];
        max =  MAX(max, swatchPopulation);
    }
    _maxPopulation = max;
}

#pragma mark - generate score

- (void)getSwatchForTarget{
    NSMutableDictionary *finalDic = [[NSMutableDictionary alloc]init];
    PaletteColorModel *recommendColorModel;
    for (NSInteger i = 0;i<_targetArray.count;i++){
        PaletteTarget *target = [_targetArray objectAtIndex:i];
        [target normalizeWeights];
        PaletteSwatch *swatch = [self getMaxScoredSwatchForTarget:target];
        if (swatch){
            PaletteColorModel *colorModel = [[PaletteColorModel alloc]init];
            colorModel.imageColorString = [swatch getColorString];
            
            colorModel.percentage = (CGFloat)[swatch getPopulation]/(CGFloat)self.pixelCount;
            
//            colorModel.titleTextColorString = [swatch getTitleTextColorString];
//            colorModel.bodyTextColorString = [swatch getBodyTextColorString];
            
            if (colorModel){
                [finalDic setObject:colorModel forKey:[target getTargetKey]];
            }
            
            if (!recommendColorModel){
                recommendColorModel = colorModel;
                
                if (!_isNeedColorDic){
                    dispatch_async(dispatch_get_main_queue(), ^{
                        _getColorBlock(recommendColorModel,nil,nil);
                    });
                    return;
                }
            }
            
        }else{
            [finalDic setObject:@"unrecognized error" forKey:[target getTargetKey]];
        }
    }
    
    
    NSDictionary *finalColorDic = [finalDic copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        _getColorBlock(recommendColorModel,finalColorDic,nil);
    });

}

- (PaletteSwatch*)getMaxScoredSwatchForTarget:(PaletteTarget*)target{
    CGFloat maxScore = 0;
    PaletteSwatch *maxScoreSwatch = nil;
    for (NSInteger i = 0 ; i<_swatchArray.count; i++){
        PaletteSwatch *swatch = [_swatchArray objectAtIndex:i];
        if ([self shouldBeScoredForTarget:swatch target:target]){
            CGFloat score = [self generateScoreForTarget:target swatch:swatch];
            if (maxScore == 0 || score > maxScore){
                maxScoreSwatch = swatch;
                maxScore = score;
            }
        }
    }
    return maxScoreSwatch;
}

- (BOOL)shouldBeScoredForTarget:(PaletteSwatch*)swatch target:(PaletteTarget*)target{
    NSArray *hsl = [swatch getHsl];
    return [hsl[1] floatValue] >= [target getMinSaturation] && [hsl[1] floatValue]<= [target getMaxSaturation]
    && [hsl[2] floatValue]>= [target getMinLuma] && [hsl[2] floatValue] <= [target getMaxLuma];
    
}

- (CGFloat)generateScoreForTarget:(PaletteTarget*)target swatch:(PaletteSwatch*)swatch{
    NSArray *hsl = [swatch getHsl];
    
    float saturationScore = 0;
    float luminanceScore = 0;
    float populationScore = 0;
    
    if ([target getSaturationWeight] > 0) {
        saturationScore = [target getSaturationWeight]
        * (1.0f - fabsf([hsl[1] floatValue] - [target getTargetSaturation]));
    }
    if ([target getLumaWeight] > 0) {
        luminanceScore = [target getLumaWeight]
        * (1.0f - fabsf([hsl[2] floatValue] - [target getTargetLuma]));
    }
    if ([target getPopulationWeight] > 0) {
        populationScore = [target getPopulationWeight]
        * ([swatch getPopulation] / (float) _maxPopulation);
    }
    
    return saturationScore + luminanceScore + populationScore;
}

@end

@implementation PFilter

float BLACK_MAX_LIGHTNESS = 0.05f;
float WHITE_MIN_LIGHTNESS = 0.95f;

- (BOOL)isAllowed:(NSArray *)hsl{
    return ![self isBlack:hsl] && ![self isWhite:hsl] && ![self isNearRedILine:hsl];
}

- (BOOL)isBlack:(NSArray *)hsl{
    float value2 = [hsl[2] floatValue];
    return value2 <= BLACK_MAX_LIGHTNESS;
}

- (BOOL)isWhite:(NSArray *)hsl{
    float value2 = [hsl[2] floatValue];
    return value2 >= WHITE_MIN_LIGHTNESS;
}

- (BOOL)isNearRedILine:(NSArray *)hsl{
    float value0 = [hsl[0] floatValue];
    float value1 = [hsl[1] floatValue];
    return value0 >= 10.f && value0 <= 37.f && value1 <= 0.82f;
}

@end
