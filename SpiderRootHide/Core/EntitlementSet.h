#import <Foundation/Foundation.h>

@interface EntitlementSet : NSObject

@property (nonatomic, strong) NSString *sourcePath;
@property (nonatomic, strong) NSDictionary *rawEntitlements;
@property (nonatomic, assign) NSInteger entitlementCount;

@property (nonatomic, assign) BOOL hasPlatformApplication;
@property (nonatomic, assign) BOOL hasGetTaskAllow;
@property (nonatomic, assign) BOOL hasNoContainer;
@property (nonatomic, assign) BOOL hasNoSandbox;
@property (nonatomic, assign) BOOL hasSkipLibraryValidation;
@property (nonatomic, assign) BOOL hasRunUnsignedCode;

@property (nonatomic, assign) BOOL hasPushNotifications;
@property (nonatomic, assign) BOOL hasGameCenter;
@property (nonatomic, assign) BOOL hasAppGroups;
@property (nonatomic, assign) BOOL hasHealthKit;
@property (nonatomic, assign) BOOL hasiCloud;
@property (nonatomic, assign) BOOL hasSiri;
@property (nonatomic, assign) BOOL hasNetworkExtension;
@property (nonatomic, assign) BOOL hasAssociatedDomains;
@property (nonatomic, assign) BOOL hasKeychainAccess;
@property (nonatomic, assign) BOOL hasCarPlay;
@property (nonatomic, assign) BOOL hasHomeKit;
@property (nonatomic, assign) BOOL hasWirelessAccessory;
@property (nonatomic, assign) BOOL hasInAppPurchase;
@property (nonatomic, assign) BOOL hasApplePay;
@property (nonatomic, assign) BOOL hasVPN;
@property (nonatomic, assign) BOOL hasMultipath;
@property (nonatomic, assign) BOOL hasBackgroundModes;
@property (nonatomic, assign) BOOL hasFamilyControls;
@property (nonatomic, assign) BOOL hasCommunicationNotifications;
@property (nonatomic, assign) BOOL hasGroupActivities;

@property (nonatomic, assign) BOOL isComplex;
@property (nonatomic, strong) NSArray<NSString *> *specialEntitlementKeys;
@property (nonatomic, strong) NSArray<NSString *> *allEntitlementKeys;

- (instancetype)initWithDictionary:(NSDictionary *)dict sourcePath:(NSString *)path;

+ (NSDictionary *)genericJailbreakEntitlements;
+ (NSDictionary *)minimalEntitlements;
+ (NSDictionary *)emptyEntitlements;

- (NSDictionary *)dictionaryRepresentation;

@end
