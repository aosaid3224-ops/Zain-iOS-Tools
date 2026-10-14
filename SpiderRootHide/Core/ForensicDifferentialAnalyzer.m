#import "ForensicDifferentialAnalyzer.h"
#import "IPAStructuralAnalyzer.h"
#import "IPAStructuralResult.h"

@implementation ForensicDifferentialAnalyzer

+ (instancetype)sharedAnalyzer {
    static ForensicDifferentialAnalyzer *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSString *)normalizedPath:(NSString *)path {
    if (!path.length) return @"";
    NSString *standard = [path stringByStandardizingPath];
    NSRange payload = [standard rangeOfString:@"/Payload/"];
    if (payload.location != NSNotFound) {
        return [standard substringFromIndex:payload.location + 9];
    }
    NSRange payloadRoot = [standard rangeOfString:@"Payload/"];
    if (payloadRoot.location != NSNotFound) {
        return [standard substringFromIndex:payloadRoot.location + 8];
    }
    return standard.lastPathComponent ?: standard;
}

- (NSString *)bundleKey:(NSDictionary *)bundle {
    NSString *bundleID = bundle[@"bundleIdentifier"];
    if (bundleID.length) return [NSString stringWithFormat:@"id:%@", bundleID];
    return [NSString stringWithFormat:@"path:%@|type:%@", [self normalizedPath:bundle[@"path"]], bundle[@"bundleType"] ?: @""];
}

- (NSString *)executableKey:(NSDictionary *)executable {
    NSString *path = [self normalizedPath:executable[@"path"]];
    NSString *uuid = executable[@"uuid"];
    if (uuid.length) return [NSString stringWithFormat:@"path:%@|uuid:%@", path, uuid];
    return [NSString stringWithFormat:@"path:%@", path];
}

- (NSArray *)sortedStringsFromArray:(NSArray *)array key:(NSString *)key {
    NSMutableArray *strings = [NSMutableArray array];
    for (id item in array ?: @[]) {
        if ([item isKindOfClass:[NSString class]]) {
            [strings addObject:item];
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *value = [item[key] isKindOfClass:[NSString class]] ? item[key] : [item description];
            if (value.length) [strings addObject:value];
        }
    }
    [strings sortUsingSelector:@selector(compare:)];
    return strings;
}

- (NSArray *)normalizedSlices:(NSArray *)slices {
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *slice in slices ?: @[]) {
        [values addObject:@{
            @"architectureName": slice[@"architectureName"] ?: @"",
            @"cputype": slice[@"cputype"] ?: @0,
            @"cpusubtype": slice[@"cpusubtype"] ?: @0,
            @"uuid": slice[@"uuid"] ?: @""
        }];
    }
    [values sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[NSString stringWithFormat:@"%@|%@", a[@"architectureName"], a[@"uuid"]] compare:[NSString stringWithFormat:@"%@|%@", b[@"architectureName"], b[@"uuid"]]];
    }];
    return values;
}

- (NSArray *)normalizedLoadCommands:(NSArray *)commands {
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *command in commands ?: @[]) {
        [values addObject:@{
            @"cmd": command[@"cmd"] ?: @0,
            @"cmdsize": command[@"cmdsize"] ?: @0,
            @"description": command[@"description"] ?: @""
        }];
    }
    [values sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[a description] compare:[b description]];
    }];
    return values;
}

- (NSDictionary *)indexByKey:(NSArray *)items keyBlock:(NSString *(^)(NSDictionary *item))keyBlock {
    NSMutableDictionary *indexed = [NSMutableDictionary dictionary];
    for (NSDictionary *item in items ?: @[]) {
        NSString *key = keyBlock(item);
        if (key.length) indexed[key] = item;
    }
    return indexed;
}

- (void)addDifference:(NSMutableArray *)differences category:(NSString *)category key:(NSString *)key field:(NSString *)field working:(id)working crash:(id)crash {
    [differences addObject:@{
        @"category": category ?: @"unknown",
        @"key": key ?: @"",
        @"field": field ?: @"",
        @"working": working ?: [NSNull null],
        @"crash": crash ?: [NSNull null]
    }];
}

- (void)compareScalarFields:(NSArray<NSString *> *)fields
                   category:(NSString *)category
                         key:(NSString *)key
                    working:(NSDictionary *)working
                       crash:(NSDictionary *)crash
                 differences:(NSMutableArray *)differences {
    for (NSString *field in fields) {
        id left = working[field] ?: [NSNull null];
        id right = crash[field] ?: [NSNull null];
        if (![left isEqual:right]) [self addDifference:differences category:category key:key field:field working:left crash:right];
    }
}

- (void)compareArrayField:(NSString *)field
                 category:(NSString *)category
                       key:(NSString *)key
                  working:(NSDictionary *)working
                     crash:(NSDictionary *)crash
               differences:(NSMutableArray *)differences
                    mapper:(NSArray *(^)(NSArray *items))mapper {
    NSArray *left = mapper(working[field] ?: @[]);
    NSArray *right = mapper(crash[field] ?: @[]);
    if (![left isEqual:right]) [self addDifference:differences category:category key:key field:field working:left crash:right];
}

- (void)compareBundlesWorking:(NSDictionary *)working
                         crash:(NSDictionary *)crash
                  differences:(NSMutableArray *)differences {
    NSDictionary *left = [self indexByKey:working[@"bundles"] keyBlock:^NSString *(NSDictionary *item) { return [self bundleKey:item]; }];
    NSDictionary *right = [self indexByKey:crash[@"bundles"] keyBlock:^NSString *(NSDictionary *item) { return [self bundleKey:item]; }];
    NSMutableSet *keys = [NSMutableSet setWithArray:left.allKeys];
    [keys addObjectsFromArray:right.allKeys];
    for (NSString *key in [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *a = left[key];
        NSDictionary *b = right[key];
        if (!a || !b) {
            [self addDifference:differences category:@"bundle" key:key field:@"presence" working:a ? @YES : @NO crash:b ? @YES : @NO];
            continue;
        }
        [self compareScalarFields:@[@"bundleType", @"bundleIdentifier", @"executableName", @"executableExists", @"nestingLevel"] category:@"bundle" key:key working:a crash:b differences:differences];
    }
}

- (void)compareExecutablesWorking:(NSDictionary *)working
                             crash:(NSDictionary *)crash
                      differences:(NSMutableArray *)differences {
    NSDictionary *left = [self indexByKey:working[@"executables"] keyBlock:^NSString *(NSDictionary *item) { return [self executableKey:item]; }];
    NSDictionary *right = [self indexByKey:crash[@"executables"] keyBlock:^NSString *(NSDictionary *item) { return [self executableKey:item]; }];
    NSMutableSet *keys = [NSMutableSet setWithArray:left.allKeys];
    [keys addObjectsFromArray:right.allKeys];
    NSArray *sortedKeys = [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        NSDictionary *a = left[key];
        NSDictionary *b = right[key];
        if (!a || !b) {
            [self addDifference:differences category:@"executable" key:key field:@"presence" working:a ? @YES : @NO crash:b ? @YES : @NO];
            continue;
        }
        [self compareScalarFields:@[@"machOType", @"machOTypeName", @"fileSize", @"uuid", @"minOSVersion", @"sdkVersion", @"platform", @"platformName", @"hasCodeSignature", @"hasEncryptedSlice", @"encryptedSliceCount", @"hasEncryptedArm64Slice", @"encryptedArm64SliceCount", @"parseStatus", @"parseError"] category:@"mach-o" key:key working:a crash:b differences:differences];
        [self compareArrayField:@"slices" category:@"architecture" key:key working:a crash:b differences:differences mapper:^NSArray *(NSArray *items) { return [self normalizedSlices:items]; }];
        [self compareArrayField:@"dependencies" category:@"linked-libraries" key:key working:a crash:b differences:differences mapper:^NSArray *(NSArray *items) { return [self sortedStringsFromArray:items key:@"rawInstallName"]; }];
        [self compareArrayField:@"rpaths" category:@"rpath" key:key working:a crash:b differences:differences mapper:^NSArray *(NSArray *items) { return [self sortedStringsFromArray:items key:@"rawPath"]; }];
        [self compareArrayField:@"loadCommands" category:@"load-commands" key:key working:a crash:b differences:differences mapper:^NSArray *(NSArray *items) { return [self normalizedLoadCommands:items]; }];
    }
}

- (NSDictionary *)factsForResult:(IPAStructuralResult *)result {
    return result ? [result dictionaryRepresentation] : @{
        @"success": @NO,
        @"errors": @[@"Structural analysis returned no result"],
        @"warnings": @[]
    };
}

- (NSDictionary *)compareWorkingIPA:(NSString *)workingIPA crashIPA:(NSString *)crashIPA {
    NSDate *started = [NSDate date];
    IPAStructuralAnalyzer *analyzer = [IPAStructuralAnalyzer sharedAnalyzer];
    IPAStructuralResult *workingResult = [analyzer analyzeIPAAtPath:workingIPA keepExtracted:NO];
    IPAStructuralResult *crashResult = [analyzer analyzeIPAAtPath:crashIPA keepExtracted:NO];
    NSDictionary *working = [self factsForResult:workingResult];
    NSDictionary *crash = [self factsForResult:crashResult];
    NSMutableArray *differences = [NSMutableArray array];

    [self compareScalarFields:@[@"success", @"ipaSize", @"bundleCount", @"executableCount", @"frameworkCount", @"dylibCount", @"appexCount", @"xpcCount", @"dependencyCount", @"rpathCount", @"sliceCount"] category:@"aggregate" key:@"IPA" working:working crash:crash differences:differences];
    if (![working[@"errors"] isEqual:crash[@"errors"]]) [self addDifference:differences category:@"analysis" key:@"IPA" field:@"errors" working:working[@"errors"] crash:crash[@"errors"]];
    if (![working[@"warnings"] isEqual:crash[@"warnings"]]) [self addDifference:differences category:@"analysis" key:@"IPA" field:@"warnings" working:working[@"warnings"] crash:crash[@"warnings"]];
    [self compareBundlesWorking:working crash:crash differences:differences];
    [self compareExecutablesWorking:working crash:crash differences:differences];

    return @{
        @"schemaVersion": @1,
        @"generatedAt": @([[NSDate date] timeIntervalSince1970]),
        @"analysisDurationMs": @([[NSDate date] timeIntervalSinceDate:started] * 1000.0),
        @"workingIPA": workingIPA ?: @"",
        @"crashIPA": crashIPA ?: @"",
        @"workingFacts": working,
        @"crashFacts": crash,
        @"differences": differences,
        @"differenceCount": @(differences.count),
        @"readOnly": @YES,
        @"policyDecision": @"NONE — facts only; no install/signing decision is inferred"
    };
}

- (NSString *)reportForComparison:(NSDictionary *)comparison {
    NSMutableString *report = [NSMutableString stringWithString:@"=== Spider Forensic Differential Report ===\n"];
    [report appendFormat:@"Working IPA: %@\nCrash IPA: %@\nRead-only: %@\nDifferences: %@\n\n",
     comparison[@"workingIPA"] ?: @"", comparison[@"crashIPA"] ?: @"", [comparison[@"readOnly"] boolValue] ? @"YES" : @"NO", comparison[@"differenceCount"] ?: @0];
    NSArray *differences = comparison[@"differences"];
    for (NSDictionary *difference in differences ?: @[]) {
        [report appendFormat:@"[%@] %@ field=%@\n  working: %@\n  crash: %@\n",
         difference[@"category"] ?: @"unknown", difference[@"key"] ?: @"", difference[@"field"] ?: @"", difference[@"working"] ?: [NSNull null], difference[@"crash"] ?: [NSNull null]];
    }
    return report;
}

@end
