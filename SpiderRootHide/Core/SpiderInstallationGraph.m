#import "SpiderInstallationGraph.h"

@implementation SpiderBundleNode
- (NSDictionary *)evidence {
    return @{
        @"path": self.path ?: @"",
        @"bundleID": self.bundleIdentifier ?: @"",
        @"executable": self.executablePath ?: @"",
        @"role": self.roleName ?: @"unknown",
        @"launchCritical": @(self.launchCritical),
        @"executableExists": @(self.executableExists),
        @"machOValid": @(self.machOValid),
        @"arm64Compatible": @(self.arm64Compatible),
        @"hasCodeSignature": @(self.hasCodeSignature),
        @"hasEncryptedSlice": @(self.hasEncryptedSlice),
        @"encryptedSliceCount": @(self.encryptedSliceCount),
        @"hasEncryptedArm64Slice": @(self.hasEncryptedArm64Slice),
        @"encryptedArm64SliceCount": @(self.encryptedArm64SliceCount),
        @"fatalFindings": self.fatalFindings ?: @[],
        @"warnings": self.warnings ?: @[]
    };
}
@end

@implementation SpiderInstallationGraph

+ (instancetype)graphFromStructuralResult:(IPAStructuralResult *)result {
    SpiderInstallationGraph *graph = [[self alloc] init];
    NSMutableArray<SpiderBundleNode *> *nodes = [NSMutableArray array];
    NSMutableArray<NSString *> *fatal = [NSMutableArray array];
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];

    if (!result || !result.success || result.bundles.count == 0) {
        [fatal addObject:@"structural analysis did not produce a usable bundle graph"];
    }

    IPAStructuralBundle *hostBundle = nil;
    for (IPAStructuralBundle *bundle in result.bundles) {
        NSString *type = bundle.bundleType.lowercaseString ?: @"";
        SpiderBundleRole role = SpiderBundleRoleUnknown;
        NSString *roleName = @"unknown";
        BOOL launchCritical = NO;
        if ([type isEqualToString:@".app"]) {
            if (!hostBundle || bundle.nestingLevel < hostBundle.nestingLevel) hostBundle = bundle;
            role = SpiderBundleRoleHostApplication;
            roleName = @"host-app";
        } else if ([type isEqualToString:@".appex"]) {
            role = SpiderBundleRoleAppExtension;
            roleName = @"app-extension";
        } else if ([type isEqualToString:@".xpc"]) {
            role = SpiderBundleRoleXPCService;
            roleName = @"xpc-service";
        } else if ([type isEqualToString:@".framework"]) {
            role = SpiderBundleRoleFramework;
            roleName = @"framework";
        } else if ([type isEqualToString:@".dylib"]) {
            role = SpiderBundleRoleDylib;
            roleName = @"dylib";
        } else {
            role = SpiderBundleRoleResourceBundle;
            roleName = @"resource-bundle";
        }
        SpiderBundleNode *node = [[SpiderBundleNode alloc] init];
        node.path = bundle.path;
        node.bundleIdentifier = bundle.bundleIdentifier;
        node.executablePath = bundle.executablePath;
        node.role = role;
        node.roleName = roleName;
        node.launchCritical = launchCritical;
        node.executableExists = bundle.executableExists;
        node.fatalFindings = @[];
        node.warnings = @[];
        [nodes addObject:node];
    }

    NSUInteger hostCount = 0;
    for (SpiderBundleNode *node in nodes) {
        if (node.role == SpiderBundleRoleHostApplication && [node.path isEqualToString:hostBundle.path]) {
            node.launchCritical = YES;
            hostCount++;
        } else if (node.role == SpiderBundleRoleHostApplication) {
            node.role = SpiderBundleRoleResourceBundle;
            node.roleName = @"nested-app-bundle";
        }
    }
    if (hostCount != 1) [fatal addObject:[NSString stringWithFormat:@"expected exactly one top-level host app, found %lu", (unsigned long)hostCount]];

    for (SpiderBundleNode *node in nodes) {
        IPAStructuralExecutable *match = nil;
        for (IPAStructuralExecutable *executable in result.executables) {
            if (node.executablePath.length && [executable.path isEqualToString:node.executablePath]) {
                match = executable;
                break;
            }
        }
        NSMutableArray<NSString *> *nodeFatal = [NSMutableArray array];
        NSMutableArray<NSString *> *nodeWarnings = [NSMutableArray array];
        node.executableExists = node.executableExists && node.executablePath.length > 0;
        node.machOValid = (match != nil && match.parseStatus != IPAStructuralParseFailed);
        node.hasCodeSignature = (match != nil && match.hasCodeSignature);
        node.hasEncryptedSlice = (match != nil && match.hasEncryptedSlice);
        node.encryptedSliceCount = match ? match.encryptedSliceCount : 0;
        node.hasEncryptedArm64Slice = (match != nil && match.hasEncryptedArm64Slice);
        node.encryptedArm64SliceCount = match ? match.encryptedArm64SliceCount : 0;
        node.arm64Compatible = NO;
        if (match.slices.count == 0) {
            node.arm64Compatible = YES;
        } else {
            for (IPAStructuralExecutableSlice *slice in match.slices) {
                NSString *archName = slice.architectureName;
                NSString *arch = (archName && archName.length > 0) ? archName.lowercaseString : @"";
                if ([arch containsString:@"arm64"] || slice.cputype == 0x0100000c ||
                    [arch containsString:@"armv7"] || slice.cputype == 0x0000000c ||
                    [arch containsString:@"x86"] || slice.cputype == 0x01000007 || slice.cputype == 0x00000007) {
                    node.arm64Compatible = YES;
                    break;
                }
            }
        }
        if (node.hasEncryptedArm64Slice && match != nil) {
            [nodeWarnings addObject:[NSString stringWithFormat:@"arm64 Mach-O slice is encrypted (cryptid!=0, slices=%u); will be re-signed by ldid", node.encryptedArm64SliceCount]];
        } else if (node.hasEncryptedSlice && match != nil) {
            [nodeWarnings addObject:[NSString stringWithFormat:@"non-arm64 Mach-O slice(s) are encrypted (cryptid!=0, slices=%u); target arm64 slice remains unencrypted", node.encryptedSliceCount]];
        }
        if (node.launchCritical || node.role == SpiderBundleRoleAppExtension || node.role == SpiderBundleRoleXPCService) {
            if (!node.executableExists) [nodeFatal addObject:@"required executable is missing"];
            if (!node.machOValid && match != nil && match.slices.count == 0 && !node.hasEncryptedSlice) {
                [nodeFatal addObject:@"required executable has no recognizable Mach-O slices"];
            } else if (!node.machOValid && match == nil) {
                [nodeFatal addObject:@"required executable is not a valid parsed Mach-O"];
            } else if (!node.machOValid && node.hasEncryptedSlice) {
                [nodeWarnings addObject:@"executable is encrypted; ldid will strip and re-sign"];
            }
            if (!node.arm64Compatible) {
                if (node.role == SpiderBundleRoleAppExtension || node.role == SpiderBundleRoleXPCService) {
                    [nodeFatal addObject:@"required executable has no arm64-compatible slice"];
                } else {
                    [nodeWarnings addObject:@"executable has no arm64-compatible slice; may fail on modern devices"];
                }
            }
        } else if (node.role == SpiderBundleRoleFramework || node.role == SpiderBundleRoleDylib) {
            if (!node.machOValid) [nodeFatal addObject:@"code library is not a valid parsed Mach-O"];
            if (!node.arm64Compatible) [nodeFatal addObject:@"code library has no arm64-compatible slice"];
        } else if (node.executablePath.length && !node.machOValid) {
            [nodeWarnings addObject:@"non-code bundle executable was not classified as a valid Mach-O"];
        }
        if (!node.hasCodeSignature && (node.launchCritical || node.role != SpiderBundleRoleResourceBundle)) {
            [nodeWarnings addObject:@"original signature absent; signing stage must establish final signature"];
        }
        node.fatalFindings = [nodeFatal copy];
        node.warnings = [nodeWarnings copy];
        for (NSString *item in nodeFatal) [fatal addObject:[NSString stringWithFormat:@"%@ (%@): %@", node.path.lastPathComponent, node.roleName, item]];
        for (NSString *item in nodeWarnings) [warnings addObject:[NSString stringWithFormat:@"%@ (%@): %@", node.path.lastPathComponent, node.roleName, item]];
    }

    graph.nodes = [nodes copy];
    graph.fatalFindings = [fatal copy];
    graph.warnings = [warnings copy];
    return graph;
}

- (BOOL)coherent {
    return self.fatalFindings.count == 0;
}

- (NSDictionary *)evidence {
    NSMutableArray *nodeEvidence = [NSMutableArray arrayWithCapacity:self.nodes.count];
    for (SpiderBundleNode *node in self.nodes) [nodeEvidence addObject:node.evidence];
    return @{
        @"coherent": @(self.coherent),
        @"nodeCount": @(self.nodes.count),
        @"fatalFindings": self.fatalFindings ?: @[],
        @"warnings": self.warnings ?: @[],
        @"nodes": nodeEvidence
    };
}

- (NSString *)summary {
    NSMutableString *text = [NSMutableString stringWithFormat:@"Spider graph: nodes=%lu coherent=%@\n", (unsigned long)self.nodes.count, self.coherent ? @"YES" : @"NO"];
    for (SpiderBundleNode *node in self.nodes) {
        [text appendFormat:@"[%@] %@ id=%@ exe=%@ machO=%@ arm64=%@ signed=%@ encrypted=%@\n", node.roleName, node.path.lastPathComponent ?: @"", node.bundleIdentifier ?: @"-", node.executablePath.lastPathComponent ?: @"-", node.machOValid ? @"YES" : @"NO", node.arm64Compatible ? @"YES" : @"NO", node.hasCodeSignature ? @"YES" : @"NO", node.hasEncryptedArm64Slice ? @"YES" : (node.hasEncryptedSlice ? @"NON-ARM64" : @"NO")];
    }
    if (self.fatalFindings.count) [text appendFormat:@"Fatal findings: %@\n", [self.fatalFindings componentsJoinedByString:@" | "]];
    if (self.warnings.count) [text appendFormat:@"Warnings: %@\n", [self.warnings componentsJoinedByString:@" | "]];
    return text;
}
@end
