#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "HBHookCompatibility.h"
static inline BOOL HBApplyDockGridConfiguration(id configuration,NSUInteger columns){
 if(!configuration||columns<1||columns>100)return NO;
 NSDictionary*requirements=@{@"setNumberOfPortraitColumns:":@[@"v",@"Q"],@"setNumberOfPortraitRows:":@[@"v",@"Q"],@"setNumberOfLandscapeColumns:":@[@"v",@"Q"],@"setNumberOfLandscapeRows:":@[@"v",@"Q"]};
 if(!HBHookTypesMatch([configuration class],requirements))return NO;
 ((void(*)(id,SEL,NSUInteger))objc_msgSend)(configuration,NSSelectorFromString(@"setNumberOfPortraitColumns:"),columns);
 ((void(*)(id,SEL,NSUInteger))objc_msgSend)(configuration,NSSelectorFromString(@"setNumberOfPortraitRows:"),1);
 ((void(*)(id,SEL,NSUInteger))objc_msgSend)(configuration,NSSelectorFromString(@"setNumberOfLandscapeColumns:"),1);
 ((void(*)(id,SEL,NSUInteger))objc_msgSend)(configuration,NSSelectorFromString(@"setNumberOfLandscapeRows:"),columns);
 return YES;
}
