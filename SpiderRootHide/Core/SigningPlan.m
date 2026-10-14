#import "SigningPlan.h"
#import "SigningTarget.h"
#import "EntitlementSet.h"

@implementation SigningPlan

- (instancetype)init {
    self = [super init];
    if (self) {
        _warnings = [NSMutableArray array];
        _recommendations = [NSMutableArray array];
        _targets = @[];
        _isViable = YES;
        _plannerVersion = @"1.0";
        _planCreatedAt = [NSDate date];
    }
    return self;
}

- (NSArray<SigningTarget *> *)targetsOrderedForSigning {
    return [self.targets sortedArrayUsingComparator:^NSComparisonResult(SigningTarget *a, SigningTarget *b) {
        NSComparisonResult orderResult = [@(a.signingOrder) compare:@(b.signingOrder)];
        if (orderResult != NSOrderedSame) return orderResult;
        return [a.filePath ?: @"" compare:b.filePath ?: @"" options:NSCaseInsensitiveSearch];
    }];
}

- (NSString *)detailedReport {
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"========================================\n"];
    [r appendFormat:@"  SMART SIGNING PLAN v%@\n", self.plannerVersion];
    [r appendFormat:@"========================================\n"];
    [r appendFormat:@"IPA: %@\n", self.ipaPath.lastPathComponent];
    [r appendFormat:@"Viable: %@ | %@\n", self.isViable ? @"YES" : @"NO", self.viabilityReason ?: @"N/A"];
    [r appendFormat:@"Total Targets: %ld\n", (long)self.totalTargets];
    [r appendFormat:@"  Preserve Original: %ld\n", (long)self.preserveCount];
    [r appendFormat:@"  Generic: %ld\n", (long)self.genericCount];
    [r appendFormat:@"  Minimal: %ld\n", (long)self.minimalCount];
    [r appendFormat:@"  Skip: %ld\n", (long)self.skipCount];
    [r appendFormat:@"Complex Targets: %ld\n", (long)self.complexTargetsCount];
    [r appendFormat:@"\n"];

    [r appendFormat:@"--- SIGNING ORDER ---\n"];
    NSArray *ordered = [self targetsOrderedForSigning];
    for (NSInteger i = 0; i < ordered.count; i++) {
        SigningTarget *t = ordered[i];
        [r appendFormat:@"%ld. [%@] %@\n", (long)(i + 1), [t strategyNameString], t.targetName];
        [r appendFormat:@"   Type: %@ | Order: %ld\n", [t typeName], (long)t.signingOrder];
        [r appendFormat:@"   Path: %@\n", t.filePath];
        [r appendFormat:@"   Original Sig: %@ | Team: %@\n", t.hasOriginalSignature ? @"YES" : @"NO", t.originalTeamID ?: @"N/A"];
        [r appendFormat:@"   Reason: %@\n", t.strategyReason];
        if (t.originalEntitlements && t.originalEntitlements.isComplex) {
            [r appendFormat:@"   ⚠️ Complex Entitlements: %@\n", [t.originalEntitlements.specialEntitlementKeys componentsJoinedByString:@", "]];
        }
        [r appendFormat:@"\n"];
    }

    if (self.warnings.count > 0) {
        [r appendFormat:@"--- WARNINGS ---\n"];
        for (NSString *w in self.warnings) { [r appendFormat:@"⚠️ %@\n", w]; }
        [r appendFormat:@"\n"];
    }

    if (self.recommendations.count > 0) {
        [r appendFormat:@"--- RECOMMENDATIONS ---\n"];
        for (NSString *rec in self.recommendations) { [r appendFormat:@"💡 %@\n", rec]; }
        [r appendFormat:@"\n"];
    }

    return r;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.ipaPath) d[@"ipaPath"] = self.ipaPath;
    d[@"isViable"] = @(self.isViable);
    if (self.viabilityReason) d[@"viabilityReason"] = self.viabilityReason;
    d[@"totalTargets"] = @(self.totalTargets);
    d[@"preserveCount"] = @(self.preserveCount);
    d[@"genericCount"] = @(self.genericCount);
    d[@"minimalCount"] = @(self.minimalCount);
    d[@"skipCount"] = @(self.skipCount);
    d[@"complexTargetsCount"] = @(self.complexTargetsCount);
    d[@"plannerVersion"] = self.plannerVersion ?: @"1.0";

    NSMutableArray *tArr = [NSMutableArray array];
    for (SigningTarget *t in self.targets) { [tArr addObject:[t dictionaryRepresentation]]; }
    d[@"targets"] = tArr;

    NSMutableArray *oArr = [NSMutableArray array];
    for (SigningTarget *t in [self targetsOrderedForSigning]) { [oArr addObject:[t dictionaryRepresentation]]; }
    d[@"targetsOrdered"] = oArr;

    d[@"warnings"] = [self.warnings copy];
    d[@"recommendations"] = [self.recommendations copy];
    return d;
}

@end
