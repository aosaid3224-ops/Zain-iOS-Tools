#import "SigningTarget.h"
#import "EntitlementSet.h"

@implementation SigningTarget

- (NSString *)typeName {
    switch (self.targetType) {
        case SigningTargetTypeMainExecutable: return @"Main Executable";
        case SigningTargetTypeAppExtension: return @"App Extension";
        case SigningTargetTypeXPCService: return @"XPC Service";
        case SigningTargetTypeFramework: return @"Framework";
        case SigningTargetTypeDylib: return @"Dylib";
        case SigningTargetTypeBundle: return @"Bundle";
        default: return @"Unknown";
    }
}

- (NSString *)strategyNameString {
    switch (self.strategy) {
        case SigningStrategyPreserveOriginal: return @"Preserve Original";
        case SigningStrategyGeneric: return @"Generic Jailbreak";
        case SigningStrategyMinimal: return @"Minimal";
        case SigningStrategySkip: return @"Skip";
        default: return @"Unknown";
    }
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.filePath) d[@"filePath"] = self.filePath;
    if (self.targetName) d[@"targetName"] = self.targetName;
    d[@"targetType"] = [self typeName];
    if (self.bundleIdentifier) d[@"bundleIdentifier"] = self.bundleIdentifier;
    if (self.bundlePath) d[@"bundlePath"] = self.bundlePath;
    d[@"hasOriginalSignature"] = @(self.hasOriginalSignature);
    if (self.originalTeamID) d[@"originalTeamID"] = self.originalTeamID;
    if (self.originalAuthority) d[@"originalAuthority"] = self.originalAuthority;
    d[@"strategy"] = [self strategyNameString];
    if (self.strategyReason) d[@"strategyReason"] = self.strategyReason;
    d[@"signingOrder"] = @(self.signingOrder);
    d[@"needsSigning"] = @(self.needsSigning);
    if (self.originalEntitlements) d[@"originalEntitlements"] = [self.originalEntitlements dictionaryRepresentation];
    if (self.plannedEntitlements) d[@"plannedEntitlements"] = [self.plannedEntitlements dictionaryRepresentation];
    return d;
}

@end
