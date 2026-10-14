#import <Foundation/Foundation.h>
@class EntitlementSet;

typedef NS_ENUM(NSInteger, SigningTargetType) {
    SigningTargetTypeUnknown = 0,
    SigningTargetTypeMainExecutable = 1,
    SigningTargetTypeAppExtension = 2,
    SigningTargetTypeXPCService = 3,
    SigningTargetTypeFramework = 4,
    SigningTargetTypeDylib = 5,
    SigningTargetTypeBundle = 6
};

typedef NS_ENUM(NSInteger, SigningStrategy) {
    SigningStrategyUnknown = 0,
    SigningStrategyPreserveOriginal = 1,
    SigningStrategyGeneric = 2,
    SigningStrategyMinimal = 3,
    SigningStrategySkip = 4
};

@interface SigningTarget : NSObject

@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSString *targetName;
@property (nonatomic, assign) SigningTargetType targetType;
@property (nonatomic, strong) NSString *targetTypeName;

@property (nonatomic, strong) NSString *bundleIdentifier;
@property (nonatomic, strong) NSString *bundlePath;

@property (nonatomic, strong) EntitlementSet *originalEntitlements;
@property (nonatomic, assign) BOOL hasOriginalSignature;
@property (nonatomic, strong) NSString *originalTeamID;
@property (nonatomic, strong) NSString *originalAuthority;

@property (nonatomic, strong) EntitlementSet *plannedEntitlements;
@property (nonatomic, assign) SigningStrategy strategy;
@property (nonatomic, strong) NSString *strategyName;
@property (nonatomic, strong) NSString *strategyReason;
@property (nonatomic, assign) NSInteger signingOrder;
@property (nonatomic, assign) BOOL needsSigning;

- (NSString *)typeName;
- (NSString *)strategyNameString;
- (NSDictionary *)dictionaryRepresentation;

@end
