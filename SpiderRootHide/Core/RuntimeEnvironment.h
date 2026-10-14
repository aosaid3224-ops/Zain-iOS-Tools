#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SpiderJailbreakType) {
    SpiderJailbreakTypeUnknown,
    SpiderJailbreakTypeCheckra1n,
    SpiderJailbreakTypeUnc0ver,
    SpiderJailbreakTypeDopamine,
    SpiderJailbreakTypePalera1n,
    SpiderJailbreakTypeTaurine,
    SpiderJailbreakTypeOdyssey,
    SpiderJailbreakTypeXinaA15,
    SpiderJailbreakTypeRelaxin,
    SpiderJailbreakTypeOther
};

@interface RuntimeEnvironment : NSObject

+ (instancetype)sharedEnvironment;

@property (nonatomic, copy, readonly) NSString *bootstrapPath;

@property (nonatomic, assign, readonly) BOOL isRootless;

@property (nonatomic, assign, readonly) BOOL isRootHide;

@property (nonatomic, assign, readonly) SpiderJailbreakType jailbreakType;

@property (nonatomic, copy, readonly) NSString *jailbreakTypeName;

@property (nonatomic, copy, readonly) NSString *iosVersion;

@property (nonatomic, copy, readonly) NSString *architecture;

@property (nonatomic, copy, readonly) NSArray<NSString *> *binSearchPaths;

@property (nonatomic, copy, readonly) NSArray<NSString *> *librarySearchPaths;

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environmentVariables;

@property (nonatomic, assign, readonly) BOOL isCharacterized;

- (NSDictionary *)diagnosticSnapshot;

- (NSString *)resolvePath:(NSString *)logicalPath;

@end
