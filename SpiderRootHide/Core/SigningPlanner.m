#import "SigningPlanner.h"
#import "IPAStructuralResult.h"
#import "SigningPlan.h"
#import "SigningTarget.h"
#import "EntitlementSet.h"
#import "SignatureAnalyzer.h"
#import "JailbreakEnvironment.h"

@interface SigningPlanner ()
@end

@implementation SigningPlanner

+ (instancetype)sharedPlanner {
    static SigningPlanner *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (SigningPlan *)createPlanForStructuralResult:(IPAStructuralResult *)result {
    SigningPlan *plan = [[SigningPlan alloc] init];
    plan.ipaPath = result.ipaPath;

    NSMutableArray<SigningTarget *> *targets = [NSMutableArray array];

    NSString *appRoot = nil;
    for (IPAStructuralBundle *bundle in result.bundles) {
        if ([bundle.bundleType isEqualToString:@".app"] && bundle.nestingLevel == 0) {
            appRoot = bundle.path;
            break;
        }
    }

    for (IPAStructuralExecutable *exe in result.executables) {
        SigningTarget *target = [self analyzeExecutable:exe inResult:result];
        if (target) {
            IPAStructuralBundle *owner = nil;
            for (IPAStructuralBundle *bundle in result.bundles) {
                if (![bundle.path isKindOfClass:[NSString class]] || bundle.path.length == 0) continue;
                NSString *prefix = [bundle.path hasSuffix:@"/"] ? bundle.path : [bundle.path stringByAppendingString:@"/"];
                if ([target.filePath isEqualToString:bundle.path] || [target.filePath hasPrefix:prefix]) {
                    if (!owner || bundle.path.length > owner.path.length) owner = bundle;
                }
            }
            if (owner) {
                target.bundleIdentifier = owner.bundleIdentifier;
                target.bundlePath = owner.path;
                [self applyContainerAwarePolicyToTarget:target];
            }
            if (appRoot.length > 0 && [target.filePath hasPrefix:appRoot]) {
                NSString *relative = [target.filePath substringFromIndex:appRoot.length];
                while ([relative hasPrefix:@"/"]) relative = [relative substringFromIndex:1];
                target.filePath = relative;
            }
            [targets addObject:target];
        }
    }

    plan.targets = [targets copy];

    [self computeStatistics:plan];

    [self validatePlan:plan];

    [self generateRecommendations:plan result:result];

    return plan;
}

- (SigningTarget *)analyzeExecutable:(IPAStructuralExecutable *)exe inResult:(IPAStructuralResult *)result {
    SigningTarget *target = [[SigningTarget alloc] init];
    target.filePath = exe.path;
    target.targetName = exe.name;
    target.needsSigning = YES;

    target.targetType = [self classifyTargetType:exe path:exe.path bundles:result.bundles];
    target.targetTypeName = [target typeName];

    SignatureInfo *sigInfo = [[SignatureAnalyzer sharedAnalyzer] analyzeSignatureAtPath:exe.path];
    target.hasOriginalSignature = sigInfo.isSigned;
    target.originalTeamID = sigInfo.teamID;
    target.originalAuthority = sigInfo.authority;

    NSDictionary *rawEnts = [[SignatureAnalyzer sharedAnalyzer] extractEntitlementsAtPath:exe.path];
    if (rawEnts) {
        target.originalEntitlements = [[EntitlementSet alloc] initWithDictionary:rawEnts sourcePath:exe.path];
    }

    [self decideStrategyForTarget:target];

    [self buildPlannedEntitlementsForTarget:target];

    return target;
}

- (SigningTargetType)classifyTargetType:(IPAStructuralExecutable *)exe path:(NSString *)path bundles:(NSArray<IPAStructuralBundle *> *)bundles {
    NSString *lower = path.lowercaseString;

    if ([lower containsString:@".appex/"]) return SigningTargetTypeAppExtension;
    if ([lower containsString:@".xpc/"]) return SigningTargetTypeXPCService;
    if ([lower containsString:@".framework/"]) return SigningTargetTypeFramework;

    if ([exe.machOTypeName isEqualToString:@"MH_DYLIB"]) return SigningTargetTypeDylib;

    for (IPAStructuralBundle *bundle in bundles) {
        if ([bundle.bundleType isEqualToString:@".app"] && bundle.nestingLevel == 0) {
            if (bundle.executablePath && [path isEqualToString:bundle.executablePath]) {
                return SigningTargetTypeMainExecutable;
            }
        }
    }

    for (IPAStructuralBundle *bundle in bundles) {
        if ([bundle.bundleType isEqualToString:@".app"] && bundle.executablePath && [path isEqualToString:bundle.executablePath]) {
            return SigningTargetTypeMainExecutable;
        }
    }

    if ([lower containsString:@".bundle/"]) return SigningTargetTypeBundle;

    if ([exe.machOTypeName isEqualToString:@"MH_EXECUTE"]) {
        return SigningTargetTypeMainExecutable;
    }

    return SigningTargetTypeUnknown;
}

- (void)decideStrategyForTarget:(SigningTarget *)target {
    switch (target.targetType) {
        case SigningTargetTypeAppExtension:
        case SigningTargetTypeXPCService:
            [self decideExtensionStrategy:target];
            break;

        case SigningTargetTypeFramework:
            [self decideFrameworkStrategy:target];
            break;

        case SigningTargetTypeDylib:
            [self decideDylibStrategy:target];
            break;

        case SigningTargetTypeMainExecutable:
            [self decideMainAppStrategy:target];
            break;

        case SigningTargetTypeBundle:
            [self decideBundleStrategy:target];
            break;

        default:
            target.strategy = SigningStrategyGeneric;
            target.strategyReason = @"Unknown target type — defaulting to generic jailbreak entitlements";
            target.signingOrder = 4;
            break;
    }
}

- (void)decideExtensionStrategy:(SigningTarget *)target {
    target.signingOrder = 3;

    if (target.originalEntitlements && target.originalEntitlements.isComplex) {
        target.strategy = SigningStrategyPreserveOriginal;
        target.strategyReason = [NSString stringWithFormat:
            @"%@ requires original entitlements: %@",
            target.targetTypeName,
            [target.originalEntitlements.specialEntitlementKeys componentsJoinedByString:@", "]];
    } else if (target.originalEntitlements && target.originalEntitlements.entitlementCount > 0) {
        target.strategy = SigningStrategyPreserveOriginal;
        target.strategyReason = [NSString stringWithFormat:
            @"%@ has entitlements that must be preserved for proper functionality",
            target.targetTypeName];
    } else {
        target.strategy = SigningStrategyGeneric;
        target.strategyReason = [NSString stringWithFormat:
            @"%@ has no original entitlements — using generic (may lose functionality)",
            target.targetTypeName];
    }
}

- (void)decideFrameworkStrategy:(SigningTarget *)target {
    target.strategy = SigningStrategyMinimal;
    target.strategyReason = @"Frameworks only need minimal entitlements for code signature validation";
    target.signingOrder = 2;

    if (target.originalEntitlements && target.originalEntitlements.isComplex) {
        [self addWarningToTarget:target message:[NSString stringWithFormat:
            @"Framework %@ has complex entitlements — verify minimal signing is sufficient",
            target.targetName]];
    }
}

- (void)decideDylibStrategy:(SigningTarget *)target {
    target.strategy = SigningStrategyMinimal;
    target.strategyReason = @"Dylibs only need platform-application for code loading";
    target.signingOrder = 1;
}

- (void)decideMainAppStrategy:(SigningTarget *)target {
    target.signingOrder = 4;

    if (target.originalEntitlements && target.originalEntitlements.entitlementCount > 0) {
        target.strategy = SigningStrategyPreserveOriginal;
        if (target.originalEntitlements.isComplex) {
            target.strategyReason = [NSString stringWithFormat:
                @"Main app has service entitlements that must be preserved: %@",
                [target.originalEntitlements.specialEntitlementKeys componentsJoinedByString:@", "]];
        } else {
            target.strategyReason = @"Main app has source entitlements; preserving the complete set";
        }

        if (target.originalEntitlements.hasPushNotifications) {
            [self addRecommendationToTarget:target message:@"Push Notifications entitlement preserved — verify the original bundle identity remains valid"];
        }
        if (target.originalEntitlements.hasGameCenter) {
            [self addRecommendationToTarget:target message:@"Game Center entitlement preserved — verify Apple ID sign-in works"];
        }
        if (target.originalEntitlements.hasAppGroups) {
            [self addRecommendationToTarget:target message:@"App Groups entitlement preserved — shared containers may need manual setup"];
        }
        if (target.originalEntitlements.hasiCloud) {
            [self addRecommendationToTarget:target message:@"iCloud entitlement preserved — verify container identifiers match"];
        }
    } else {
        target.strategy = SigningStrategyGeneric;
        target.strategyReason = @"Main app has no source entitlements — using narrow generic jailbreak set";
    }
}

- (void)decideBundleStrategy:(SigningTarget *)target {
    target.strategy = SigningStrategyMinimal;
    target.strategyReason = @"Bundle only needs minimal entitlements";
    target.signingOrder = 2;
}

- (void)buildPlannedEntitlementsForTarget:(SigningTarget *)target {
    switch (target.strategy) {
        case SigningStrategyPreserveOriginal:
            if (target.originalEntitlements) {
                target.plannedEntitlements = target.originalEntitlements;
            } else {
                target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:[EntitlementSet genericJailbreakEntitlements] sourcePath:target.filePath];
                [self addWarningToTarget:target message:@"PreserveOriginal requested but no original entitlements found — falling back to generic"];
            }
            break;

        case SigningStrategyGeneric:
            target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:[EntitlementSet genericJailbreakEntitlements] sourcePath:target.filePath];
            break;

        case SigningStrategyMinimal:
            target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:[EntitlementSet minimalEntitlements] sourcePath:target.filePath];
            break;

        case SigningStrategySkip:
            target.plannedEntitlements = nil;
            target.needsSigning = NO;
            break;

        default:
            target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:[EntitlementSet genericJailbreakEntitlements] sourcePath:target.filePath];
            break;
    }
}

- (void)applyContainerAwarePolicyToTarget:(SigningTarget *)target {
    if (!target.bundleIdentifier.length || !target.plannedEntitlements) return;
    if (target.targetType == SigningTargetTypeFramework ||
        target.targetType == SigningTargetTypeDylib ||
        target.targetType == SigningTargetTypeBundle) return;

    NSMutableDictionary *ents = [target.plannedEntitlements.rawEntitlements mutableCopy];
    if (!ents) ents = [NSMutableDictionary dictionary];

    if (target.targetType == SigningTargetTypeMainExecutable &&
        target.strategy == SigningStrategyGeneric && !target.hasOriginalSignature) {
        NSString *appIdentifier = [NSString stringWithFormat:@"IPAINSTALLERPRO.%@", target.bundleIdentifier];
        if (![ents[@"application-identifier"] isKindOfClass:[NSString class]]) {
            ents[@"application-identifier"] = appIdentifier;
        }
        if (![ents[@"com.apple.developer.team-identifier"] isKindOfClass:[NSString class]]) {
            ents[@"com.apple.developer.team-identifier"] = @"IPAINSTALLERPRO";
        }
        if (![ents[@"keychain-access-groups"] isKindOfClass:[NSArray class]]) {
            ents[@"keychain-access-groups"] = @[appIdentifier, @"com.apple.token"];
        }
    }

    JailbreakEnvironment *environment = [JailbreakEnvironment sharedEnvironment];
    NSString *jbType = environment.jailbreakType.lowercaseString ?: @"";
    BOOL dopamineRootless = environment.isRootless && [jbType containsString:@"dopamine"];
    if (dopamineRootless &&
        (target.targetType == SigningTargetTypeMainExecutable ||
         target.targetType == SigningTargetTypeAppExtension ||
         target.targetType == SigningTargetTypeXPCService)) {
        ents[@"jb.pmap_cs.custom_trust"] = @"PMAP_CS_APP_STORE";
    }

    BOOL sourceNoContainer = [target.originalEntitlements.rawEntitlements[@"com.apple.private.security.no-container"] boolValue];
    BOOL sourceNoSandbox = [target.originalEntitlements.rawEntitlements[@"com.apple.private.security.no-sandbox"] boolValue];
    id existing = ents[@"com.apple.private.security.container-required"];
    if ((sourceNoContainer || sourceNoSandbox) && ![existing isKindOfClass:[NSString class]]) {
        target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:ents sourcePath:target.filePath];
        return;
    }
    if ([existing isKindOfClass:[NSString class]] && [(NSString *)existing length] > 0) {
        target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:ents sourcePath:target.filePath];
        return;
    }

    ents[@"com.apple.private.security.container-required"] = target.bundleIdentifier;
    [ents removeObjectForKey:@"com.apple.private.security.no-container"];
    [ents removeObjectForKey:@"com.apple.private.security.no-sandbox"];
    target.plannedEntitlements = [[EntitlementSet alloc] initWithDictionary:ents sourcePath:target.filePath];
}

- (void)computeStatistics:(SigningPlan *)plan {
    plan.totalTargets = plan.targets.count;

    NSInteger preserve = 0, generic = 0, minimal = 0, skip = 0, complex = 0;
    for (SigningTarget *t in plan.targets) {
        switch (t.strategy) {
            case SigningStrategyPreserveOriginal: preserve++; break;
            case SigningStrategyGeneric: generic++; break;
            case SigningStrategyMinimal: minimal++; break;
            case SigningStrategySkip: skip++; break;
            default: break;
        }
        if (t.originalEntitlements && t.originalEntitlements.isComplex) {
            complex++;
        }
    }

    plan.preserveCount = preserve;
    plan.genericCount = generic;
    plan.minimalCount = minimal;
    plan.skipCount = skip;
    plan.complexTargetsCount = complex;
}

- (void)validatePlan:(SigningPlan *)plan {
    for (SigningTarget *t in plan.targets) {
        if (t.targetType == SigningTargetTypeAppExtension || t.targetType == SigningTargetTypeXPCService) {
            if (t.strategy != SigningStrategyPreserveOriginal && t.strategy != SigningStrategyGeneric) {
                [plan.warnings addObject:[NSString stringWithFormat:
                    @"⚠️ %@ (%@) is not using PreserveOriginal — may crash due to missing entitlements",
                    t.targetName, t.targetTypeName]];
            }
        }
    }

    for (SigningTarget *t in plan.targets) {
        if (t.targetType == SigningTargetTypeMainExecutable) {
            if (!t.plannedEntitlements || t.plannedEntitlements.entitlementCount == 0) {
                plan.isViable = NO;
                plan.viabilityReason = @"Main executable has no planned entitlements — plan is not viable";
                return;
            }
        }
    }

    plan.isViable = YES;
    plan.viabilityReason = @"All critical targets have valid signing strategies";
}

- (void)generateRecommendations:(SigningPlan *)plan result:(IPAStructuralResult *)result {
    if (plan.complexTargetsCount > 0) {
        [plan.recommendations addObject:[NSString stringWithFormat:
            @"📋 %ld target(s) have complex entitlements — verify functionality after install",
            (long)plan.complexTargetsCount]];
    }

    if (result.frameworkCount > 5) {
        [plan.recommendations addObject:@"📦 Many frameworks detected — ensure all are properly signed in order"];
    }

    BOOL hasFatBinary = NO;
    for (IPAStructuralExecutable *executable in result.executables) {
        if (executable.slices.count > 1) {
            hasFatBinary = YES;
            break;
        }
    }
    if (hasFatBinary) {
        [plan.recommendations addObject:@"FAT binary detected — verify device architecture compatibility"];
    }

    if (plan.preserveCount > 0) {
        [plan.recommendations addObject:[NSString stringWithFormat:
            @"🔒 %ld target(s) will preserve original entitlements — these apps should function normally",
            (long)plan.preserveCount]];
    }

    if (plan.genericCount > 0) {
        [plan.recommendations addObject:[NSString stringWithFormat:
            @"⚙️ %ld target(s) will use generic entitlements — simple apps should work fine",
            (long)plan.genericCount]];
    }
}

- (void)addWarningToTarget:(SigningTarget *)target message:(NSString *)message {
    NSLog(@"[SigningPlanner] Warning for %@: %@", target.targetName, message);
}

- (void)addRecommendationToTarget:(SigningTarget *)target message:(NSString *)message {
    NSLog(@"[SigningPlanner] Recommendation for %@: %@", target.targetName, message);
}

@end
