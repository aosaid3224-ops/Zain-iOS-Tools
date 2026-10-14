#import "EntitlementSet.h"

@implementation EntitlementSet

- (instancetype)initWithDictionary:(NSDictionary *)dict sourcePath:(NSString *)path {
    self = [super init];
    if (self) {
        _sourcePath = path;
        _rawEntitlements = dict ?: @{};
        _entitlementCount = _rawEntitlements.count;
        _specialEntitlementKeys = @[];
        _allEntitlementKeys = [_rawEntitlements.allKeys sortedArrayUsingSelector:@selector(compare:)];

        NSMutableArray *special = [NSMutableArray array];

        _hasPlatformApplication = [self boolForKey:@"platform-application"];
        _hasGetTaskAllow = [self boolForKey:@"get-task-allow"];
        _hasNoContainer = [self boolForKey:@"com.apple.private.security.no-container"];
        _hasNoSandbox = [self boolForKey:@"com.apple.private.security.no-sandbox"];
        _hasSkipLibraryValidation = [self boolForKey:@"com.apple.private.skip-library-validation"];
        _hasRunUnsignedCode = [self boolForKey:@"run-unsigned-code"];

        _hasPushNotifications = [self boolForKey:@"aps-environment"];
        if (_hasPushNotifications) [special addObject:@"aps-environment"];

        _hasGameCenter = [self boolForKey:@"com.apple.developer.game-center"];
        if (_hasGameCenter) [special addObject:@"com.apple.developer.game-center"];

        _hasAppGroups = [self boolForKey:@"com.apple.security.application-groups"];
        if (_hasAppGroups) [special addObject:@"com.apple.security.application-groups"];

        _hasHealthKit = [self boolForKey:@"com.apple.developer.healthkit"];
        if (_hasHealthKit) [special addObject:@"com.apple.developer.healthkit"];

        _hasiCloud = [self boolForKey:@"com.apple.developer.icloud-services"];
        if (_hasiCloud) [special addObject:@"com.apple.developer.icloud-services"];

        _hasSiri = [self boolForKey:@"com.apple.developer.siri"];
        if (_hasSiri) [special addObject:@"com.apple.developer.siri"];

        _hasNetworkExtension = [self boolForKey:@"com.apple.developer.networking.networkextension"];
        if (_hasNetworkExtension) [special addObject:@"com.apple.developer.networking.networkextension"];

        _hasAssociatedDomains = [self boolForKey:@"com.apple.developer.associated-domains"];
        if (_hasAssociatedDomains) [special addObject:@"com.apple.developer.associated-domains"];

        _hasKeychainAccess = [self boolForKey:@"keychain-access-groups"];
        if (_hasKeychainAccess) [special addObject:@"keychain-access-groups"];

        _hasCarPlay = [self boolForKey:@"com.apple.developer.carplay"];
        if (_hasCarPlay) [special addObject:@"com.apple.developer.carplay"];

        _hasHomeKit = [self boolForKey:@"com.apple.developer.homekit"];
        if (_hasHomeKit) [special addObject:@"com.apple.developer.homekit"];

        _hasWirelessAccessory = [self boolForKey:@"com.apple.external-accessory.wireless"];
        if (_hasWirelessAccessory) [special addObject:@"com.apple.external-accessory.wireless"];

        _hasInAppPurchase = [self boolForKey:@"com.apple.developer.in-app-purchase"];
        if (_hasInAppPurchase) [special addObject:@"com.apple.developer.in-app-purchase"];

        _hasApplePay = [self boolForKey:@"com.apple.developer.in-app-payments"];
        if (_hasApplePay) [special addObject:@"com.apple.developer.in-app-payments"];

        _hasVPN = [self boolForKey:@"com.apple.developer.networking.vpn.api"];
        if (_hasVPN) [special addObject:@"com.apple.developer.networking.vpn.api"];

        _hasMultipath = [self boolForKey:@"com.apple.developer.networking.multipath"];
        if (_hasMultipath) [special addObject:@"com.apple.developer.networking.multipath"];

        _hasFamilyControls = [self boolForKey:@"com.apple.developer.family-controls"];
        if (_hasFamilyControls) [special addObject:@"com.apple.developer.family-controls"];

        _hasCommunicationNotifications = [self boolForKey:@"com.apple.developer.usernotifications.communication"];
        if (_hasCommunicationNotifications) [special addObject:@"com.apple.developer.usernotifications.communication"];

        _hasGroupActivities = [self boolForKey:@"com.apple.developer.group-session"];
        if (_hasGroupActivities) [special addObject:@"com.apple.developer.group-session"];

        _specialEntitlementKeys = [special copy];
        _isComplex = special.count > 0;
    }
    return self;
}

- (BOOL)boolForKey:(NSString *)key {
    id val = self.rawEntitlements[key];
    if ([val isKindOfClass:[NSNumber class]]) return [val boolValue];
    if ([val isKindOfClass:[NSString class]]) return [val isEqualToString:@"true"] || [val isEqualToString:@"YES"];
    return val != nil;
}

+ (NSDictionary *)genericJailbreakEntitlements {
    return @{
        @"platform-application": @YES,
        @"get-task-allow": @YES,
        @"com.apple.private.skip-library-validation": @YES,
        @"run-unsigned-code": @YES
    };
}

+ (NSDictionary *)minimalEntitlements {
    return @{};
}

+ (NSDictionary *)emptyEntitlements {
    return @{};
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.sourcePath) d[@"sourcePath"] = self.sourcePath;
    d[@"entitlementCount"] = @(self.entitlementCount);
    d[@"isComplex"] = @(self.isComplex);
    d[@"hasPlatformApplication"] = @(self.hasPlatformApplication);
    d[@"hasGetTaskAllow"] = @(self.hasGetTaskAllow);
    d[@"hasNoContainer"] = @(self.hasNoContainer);
    d[@"hasNoSandbox"] = @(self.hasNoSandbox);
    d[@"hasPushNotifications"] = @(self.hasPushNotifications);
    d[@"hasGameCenter"] = @(self.hasGameCenter);
    d[@"hasAppGroups"] = @(self.hasAppGroups);
    d[@"hasHealthKit"] = @(self.hasHealthKit);
    d[@"hasiCloud"] = @(self.hasiCloud);
    d[@"hasSiri"] = @(self.hasSiri);
    d[@"hasNetworkExtension"] = @(self.hasNetworkExtension);
    d[@"hasAssociatedDomains"] = @(self.hasAssociatedDomains);
    d[@"hasKeychainAccess"] = @(self.hasKeychainAccess);
    d[@"hasInAppPurchase"] = @(self.hasInAppPurchase);
    d[@"specialEntitlementKeys"] = self.specialEntitlementKeys ?: @[];
    d[@"allEntitlementKeys"] = self.allEntitlementKeys ?: @[];
    return d;
}

@end
