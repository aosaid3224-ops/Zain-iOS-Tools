#import "../HBDockCapacity.h"
@interface HBGridTest83:NSObject
@property(nonatomic) NSUInteger numberOfPortraitColumns,numberOfPortraitRows,numberOfLandscapeColumns,numberOfLandscapeRows;
@end
@implementation HBGridTest83 @end
@interface HBWrongGrid83:NSObject
@property(nonatomic) id numberOfPortraitColumns,numberOfPortraitRows,numberOfLandscapeColumns,numberOfLandscapeRows;
@end
@implementation HBWrongGrid83 @end
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"failed line %d\n",__LINE__);return 2;}}while(0)
int main(void){@autoreleasepool{
 HBGridTest83*g=[HBGridTest83 new];
 for(NSNumber*n in @[@5,@8,@12,@20,@100]){CHECK(HBApplyDockGridConfiguration(g,n.unsignedIntegerValue));CHECK(g.numberOfPortraitColumns==n.unsignedIntegerValue);CHECK(g.numberOfPortraitRows==1);CHECK(g.numberOfLandscapeColumns==1);CHECK(g.numberOfLandscapeRows==n.unsignedIntegerValue);}
 CHECK(!HBApplyDockGridConfiguration(g,0));CHECK(!HBApplyDockGridConfiguration(g,101));CHECK(g.numberOfPortraitColumns==100);
 CHECK(!HBApplyDockGridConfiguration(nil,12));CHECK(!HBApplyDockGridConfiguration([NSObject new],12));HBWrongGrid83*w=[HBWrongGrid83 new];CHECK(!HBApplyDockGridConfiguration(w,12));CHECK(w.numberOfPortraitColumns==nil);
 printf("{\"checks\":%d,\"capacitiesTested\":[5,8,12,20,100],\"realDockModified\":false}\n",checks);return 0;
}}
