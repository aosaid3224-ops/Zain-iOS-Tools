#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
static int checks=0;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"failed line %d: %s\n",__LINE__,#x);return 2;}}while(0)
static id FakeDefault(id self,SEL cmd,id key,id fallback){(void)self;(void)cmd;(void)key;return fallback;}
int main(void){@autoreleasepool{@try{
 CHECK(NSThread.isMainThread);CHECK(dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences",RTLD_NOW)!=NULL);
 NSString*base=NSFileManager.defaultManager.currentDirectoryPath;NSBundle*bundle=nil;
 for(NSString*sub in @[@".theos/_/var/jb/Library/PreferenceBundles/harborprefs.bundle",@".theos/_/Library/PreferenceBundles/harborprefs.bundle"]){NSBundle*b=[NSBundle bundleWithPath:[base stringByAppendingPathComponent:sub]];if(b){bundle=b;break;}}
 CHECK(bundle!=nil);NSError*error=nil;BOOL loaded=[bundle loadAndReturnError:&error];if(!loaded)fprintf(stderr,"load: %s\n",error.description.UTF8String);CHECK(loaded);
 Class cls=bundle.principalClass;CHECK(cls!=Nil);CHECK([cls isSubclassOfClass:UIViewController.class]);
 Method getter=class_getInstanceMethod(cls,NSSelectorFromString(@"preferenceValueForKey:defaultValue:"));CHECK(getter!=NULL);method_setImplementation(getter,(IMP)FakeDefault);
 UIViewController*controller=[[cls alloc]init];CHECK(controller!=nil);SEL selector=NSSelectorFromString(@"specifiers");CHECK([controller respondsToSelector:selector]);
 NSArray*specifiers=((id(*)(id,SEL))objc_msgSend)(controller,selector);CHECK([specifiers isKindOfClass:NSArray.class]);CHECK(specifiers.count==43);
 for(id specifier in specifiers){CHECK([specifier respondsToSelector:@selector(name)]);id name=((id(*)(id,SEL))objc_msgSend)(specifier,@selector(name));CHECK([name isKindOfClass:NSString.class]);CHECK([name length]>0);}
 NSArray*again=((id(*)(id,SEL))objc_msgSend)(controller,selector);CHECK(again==specifiers);
 NSArray*definition=[NSDictionary dictionaryWithContentsOfFile:[bundle pathForResource:@"Root" ofType:@"plist"]][@"items"];CHECK(definition.count==43);
 for(NSDictionary*row in definition)for(NSString*key in @[@"get",@"set",@"action"]){NSString*name=row[key];if(name)CHECK([controller respondsToSelector:NSSelectorFromString(name)]);}
 [controller loadViewIfNeeded];CHECK(controller.isViewLoaded);CHECK([controller.title length]>0);
 printf("{\"checks\":%d,\"preferenceRows\":43,\"bundleLoaded\":true,\"viewLoaded\":true,\"realPreferencesRead\":false,\"preferencesWritten\":false,\"buttonsInvoked\":false,\"windowShown\":false}\n",checks);return 0;
 }@catch(NSException*e){fprintf(stderr,"exception %s: %s\n",e.name.UTF8String,e.reason.UTF8String);return 3;}}}
