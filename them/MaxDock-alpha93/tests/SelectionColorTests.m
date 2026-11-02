#import "../HBIconColor.h"
#import "../HBCompatibility.h"
#import "../HBHookCompatibility.h"
static int checks=0;
#define CHECK(x) do {checks++;if(!(x)){fprintf(stderr,"failed line %d\n",__LINE__);return 2;}}while(0)
static UIImage *Icon(UIColor *color, BOOL whiteBackground) {
 UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(48,48)];
 return [renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;if(whiteBackground){[UIColor.whiteColor setFill];UIRectFill(CGRectMake(0,0,48,48));}[color setFill];UIRectFill(CGRectMake(whiteBackground?12:0,whiteBackground?12:0,whiteBackground?24:48,whiteBackground?24:48));}];
}
int main(void){@autoreleasepool{
 CHECK(HBHookTypesMatch(UIView.class, @{@"layoutSubviews":@[@"v"],@"setHidden:":@[@"v",@"B"]}));
 CHECK(!HBHookTypesMatch(UIView.class, @{@"missingMaxDockSelector":@[@"v"]}));
 CHECK(!HBHookTypesMatch(UIView.class, @{@"setHidden:":@[@"v",@"@"]}));
 CHECK(!HBHookTypesMatch(UIView.class, @{@"setHidden:":@[@"v"]}));
 CHECK(!HBHookTypesMatch(UIView.class, @{@"layoutSubviews":@[@"@"]}));
 CHECK(!HBHookTypesMatch(Nil, @{@"layoutSubviews":@[@"v"]}));
 CHECK(HBHookTypesMatch(UIView.class, @{@"bounds":@[@(@encode(CGRect))]}));
 CHECK(!HBHookTypesMatch(UIView.class, @{@"bounds":@[@(@encode(CGPoint))]}));
 CHECK(HBSupportsOSMajor(15));CHECK(HBSupportsOSMajor(16));CHECK(HBSupportsOSMajor(17));CHECK(HBSupportsOSMajor(26));CHECK(!HBSupportsOSMajor(-1));
 CHECK(HBSelectionColorForImage(nil)==nil);
 for(NSNumber *background in @[@NO,@YES])for(NSUInteger index=0;index<3;index++){
 UIImage *icon=Icon(@[UIColor.redColor,UIColor.greenColor,UIColor.blueColor][index],background.boolValue);
 UIColor *color=HBSelectionColorForImage(icon);CGFloat r,g,b,a;CHECK([color getRed:&r green:&g blue:&b alpha:&a]);
 CHECK((index==0?r:index==1?g:b)>.8);CHECK((index==0?g:index==1?b:r)<.2);CHECK(a==1);CHECK([HBSelectionColorForImage(icon)isEqual:color]);
 }
 for(UIColor *color in @[UIColor.blackColor,UIColor.whiteColor,UIColor.clearColor]){
 UIColor *selection=HBSelectionColorForImage(Icon(color,NO));CGFloat r,g,b,a;CHECK([selection getRed:&r green:&g blue:&b alpha:&a]);CHECK(fabs(r-g)<.001&&fabs(g-b)<.001);CHECK(r>.5&&a==1);
 }
 printf("{\"checks\":%d,\"syntheticArtworkOnly\":true,\"windowShown\":false}\n",checks);return 0;
}}
