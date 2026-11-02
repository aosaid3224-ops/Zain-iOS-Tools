#import "HBIconColor.h"
#import <math.h>
// Sample icon artwork only; ignore transparent pixels and neutral backgrounds.
UIColor *HBSelectionColorForImage(UIImage *image) {
    if (!image) return nil;
    static NSMapTable *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    @synchronized(cache) { UIColor *saved = [cache objectForKey:image]; if (saved) return saved; }
    const size_t side = 24;
    uint8_t pixels[24 * 24 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    UIGraphicsPushContext(context);
    [image drawInRect:CGRectMake(0, 0, side, side)];
    UIGraphicsPopContext();
    CGContextRelease(context);
    double weight[12]={0}, red[12]={0}, green[12]={0}, blue[12]={0};
    for (size_t i=0;i<side*side;i++) {
        double alpha=pixels[i*4+3]/255.0;
        if (alpha < .2) continue;
        double r=MIN(1,pixels[i*4]/255.0/alpha),g=MIN(1,pixels[i*4+1]/255.0/alpha),b=MIN(1,pixels[i*4+2]/255.0/alpha);
        double hi=MAX(r,MAX(g,b)),lo=MIN(r,MIN(g,b)),delta=hi-lo;
        if (hi<.12 || delta<.10 || delta/MAX(.001,hi)<.18) continue;
        double hue=hi==r?fmod((g-b)/delta+6,6):hi==g?(b-r)/delta+2:(r-g)/delta+4;
        int bucket=((int)floor(hue*2+.5))%12;
        double w=alpha*(delta/hi)*(.35+hi);
        weight[bucket]+=w;red[bucket]+=r*w;green[bucket]+=g*w;blue[bucket]+=b*w;
    }
    int best=0;for(int i=1;i<12;i++)if(weight[i]>weight[best])best=i;
    UIColor *result;
    if(weight[best]<.5) result=[UIColor colorWithWhite:.72 alpha:1];
    else {
        double r=red[best]/weight[best],g=green[best]/weight[best],b=blue[best]/weight[best];
        double hi=MAX(r,MAX(g,b));if(hi<.55){double scale=.55/MAX(.001,hi);r*=scale;g*=scale;b*=scale;}
        result=[UIColor colorWithRed:r green:g blue:b alpha:1];
    }
    @synchronized(cache) { [cache setObject:result forKey:image]; }
    return result;
}
