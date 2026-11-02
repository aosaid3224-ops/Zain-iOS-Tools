#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
static inline BOOL HBHookTypesMatch(Class cls, NSDictionary<NSString*,NSArray<NSString*>*> *requirements) {
 if(!cls)return NO;
 for(NSString *name in requirements){
  Method method=class_getInstanceMethod(cls,NSSelectorFromString(name));if(!method)return NO;
  NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
  NSArray<NSString*> *types=requirements[name];if(!types.count||signature.numberOfArguments!=types.count+1)return NO;
  for(NSUInteger i=0;i<types.count;i++){
   const char*actual=i?[signature getArgumentTypeAtIndex:i+1]:signature.methodReturnType;
   while(*actual&&strchr("rnNoORV",*actual))actual++;
   const char*expected=types[i].UTF8String;
   if(!strcmp(expected,"@")){if(actual[0]!='@'||actual[1]=='?')return NO;}
   else if(strcmp(actual,expected))return NO;
  }
 }
 return YES;
}
