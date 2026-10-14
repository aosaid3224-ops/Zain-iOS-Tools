#import "JailbreakEnvironment.h"
#import <UIKit/UIKit.h>
#import "RuntimeEnvironment.h"
#import "Logger.h"

@implementation JailbreakEnvironment

+ (instancetype)sharedEnvironment {
    static JailbreakEnvironment *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self detectEnvironment];
    }
    return self;
}

- (void)detectEnvironment {
    NSDate *start = [NSDate date];

    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];

    _isRootless = rt.isRootless;
    _rootPath = rt.bootstrapPath ?: @"";
    _jailbreakType = rt.jailbreakTypeName;
    _isJailbroken = (rt.jailbreakType != SpiderJailbreakTypeUnknown) || rt.isRootless;

    _iosVersion = rt.iosVersion;
    _architecture = rt.architecture;
    _osVersion = _iosVersion;

    _deviceModel = [UIDevice currentDevice].model ?: @"Unknown";

    if (rt.bootstrapPath) {
        _applicationsPath = [rt.bootstrapPath stringByAppendingPathComponent:@"Applications"];
        _usrBinPath = [rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin"];
    } else {
        _applicationsPath = @"/Applications";
        _usrBinPath = @"/usr/bin";
    }

    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    _mobileDocumentsPath = docPaths.firstObject ?: @"N/A";

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"JailbreakEnvironment: detected in %.3fs | jailbroken=%@ | rootless=%@ | type=%@ | root=%@ | iOS=%@ | arch=%@ | device=%@ | apps=%@ | usrbin=%@",
                                 duration,
                                 _isJailbroken ? @"YES" : @"NO",
                                 _isRootless ? @"YES" : @"NO",
                                 _jailbreakType,
                                 _rootPath,
                                 _iosVersion,
                                 _architecture,
                                 _deviceModel,
                                 _applicationsPath,
                                 _usrBinPath]];

    if (!rt.isCharacterized) {
        [[Logger sharedLogger] warning:@"JailbreakEnvironment: RuntimeEnvironment could not characterize the system"];
    }
}

- (NSDictionary *)environmentInfo {
    RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"isJailbroken"] = @(self.isJailbroken);
    info[@"isRootless"] = @(self.isRootless);
    info[@"jailbreakType"] = self.jailbreakType ?: @"Unknown";
    info[@"rootPath"] = self.rootPath ?: @"";
    info[@"iosVersion"] = self.iosVersion ?: @"";
    info[@"architecture"] = self.architecture ?: @"";
    info[@"deviceModel"] = self.deviceModel ?: @"";
    info[@"applicationsPath"] = self.applicationsPath ?: @"";
    info[@"usrBinPath"] = self.usrBinPath ?: @"";
    info[@"mobileDocumentsPath"] = self.mobileDocumentsPath ?: @"";
    info[@"bootstrapPath"] = rt.bootstrapPath ?: @"none";
    info[@"binSearchPathsCount"] = @(rt.binSearchPaths.count);
    info[@"librarySearchPathsCount"] = @(rt.librarySearchPaths.count);
    return info;
}

@end
