#import <Foundation/Foundation.h>

@interface JailbreakEnvironment : NSObject

+ (instancetype)sharedEnvironment;
- (void)detectEnvironment;

@property (readonly, nonatomic) BOOL isJailbroken;
@property (readonly, nonatomic) BOOL isRootless;
@property (readonly, nonatomic) NSString *jailbreakType;
@property (readonly, nonatomic) NSString *rootPath;

@property (readonly, nonatomic) NSString *applicationsPath;
@property (readonly, nonatomic) NSString *usrBinPath;
@property (readonly, nonatomic) NSString *mobileDocumentsPath;

@property (readonly, nonatomic) NSString *osVersion;
@property (readonly, nonatomic) NSString *deviceModel;
@property (readonly, nonatomic) NSString *iosVersion;
@property (readonly, nonatomic) NSString *architecture;

@property (readonly, nonatomic) id lsApplicationWorkspace;

@end
