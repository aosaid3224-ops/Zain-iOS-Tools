#import <Foundation/Foundation.h>
#import "../HBCompatibility.h"
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"failed line %d\n",__LINE__);return 2;}}while(0)
int main(void){@autoreleasepool{
 for(NSNumber*n in @[@15,@17,@18,@26]){long major=n.longValue;CHECK(HBSupportsOSMajor(major));CHECK(!HBDefaultEnabledForOS(major));CHECK(!HBEngineEnabledForOS(major,1,0));CHECK(!HBStartupAllowedForOS(major,1,16));CHECK(!HBStartupAllowedForOS(major,0,major));CHECK(HBStartupAllowedForOS(major,1,major));CHECK(HBEngineEnabledForOS(major,1,major));}
 CHECK(HBDefaultEnabledForOS(16));CHECK(HBEngineEnabledForOS(16,1,0));CHECK(!HBEngineEnabledForOS(16,0,16));CHECK(HBStartupAllowedForOS(16,0,0));
 for(NSNumber*n in @[@14,@19,@25,@27]){CHECK(!HBSupportsOSMajor(n.longValue));CHECK(!HBStartupAllowedForOS(n.longValue,1,n.longValue));CHECK(!HBEngineEnabledForOS(n.longValue,1,n.longValue));}
 printf("{\"checks\":%d,\"unverifiedOSStartsDisabled\":true,\"staleEnabledPreferenceBlocked\":true,\"perOSOptInVerified\":true,\"realPreferencesWritten\":false}\n",checks);return 0;
}}
