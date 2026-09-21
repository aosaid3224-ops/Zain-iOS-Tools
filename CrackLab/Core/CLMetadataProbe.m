//
//  CLMetadataProbe.m
//

#import "CLMetadataProbe.h"

@implementation CLMetadataProbeResult
@end

@implementation CLMetadataProbe

+ (CLMetadataProbeResult *)probeProxy:(id)proxy bundlePath:(NSString *)bundlePath {
    CLMetadataProbeResult *r = [CLMetadataProbeResult new];
    r.bundlePath = bundlePath ?: @"";
    NSFileManager *fm = [NSFileManager defaultManager];

    // ── 1. Bundle path reality ──
    r.bundleExists = bundlePath.length > 0 && [fm fileExistsAtPath:bundlePath];

    // ── 2. Data container from LaunchServices ──
    NSString *container = nil;
    @try {
        NSURL *cu = [proxy valueForKey:@"dataContainerURL"];
        container = cu.path;
        if (!container.length) {
            NSURL *ou = [proxy valueForKey:@"containerURL"];   // older name
            container = ou.path;
        }
    } @catch (__unused NSException *e) {}
    r.dataContainerPath = container ?: @"";

    // ── 3. Candidate paths (bundle + container; NOT hardcoded single path) ──
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (bundlePath.length) [candidates addObject:[bundlePath stringByAppendingPathComponent:@"iTunesMetadata.plist"]];
    if (container.length) {
        [candidates addObject:[container stringByAppendingPathComponent:@"iTunesMetadata.plist"]];
        [candidates addObject:[container stringByAppendingPathComponent:@"Documents/iTunesMetadata.plist"]];
        [candidates addObject:[container stringByAppendingPathComponent:@"Library/iTunesMetadata.plist"]];
    }

    // Shallow search (depth 2) in container for any *iTunesMetadata* file.
    if (container.length && [fm fileExistsAtPath:container]) {
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:container];
        NSString *rel;
        NSInteger depth;
        while ((rel = [en nextObject])) {
            depth = [[rel pathComponents] count];
            if (depth > 2) { [en skipDescendants]; continue; }
            if ([rel.lowercaseString containsString:@"itunesmetadata"]) {
                NSString *full = [container stringByAppendingPathComponent:rel];
                if (![candidates containsObject:full]) [candidates addObject:full];
            }
        }
    }

    // ── 4. Probe each candidate: existence → readability → parseability ──
    NSMutableArray<NSString *> *checked = [NSMutableArray array];
    NSDictionary *parsed = nil;
    NSString *winPath = nil;
    NSString *winState = container.length ? @"missing" : @"no-container";
    long long winSize = 0;

    for (NSString *path in candidates) {
        BOOL exists = [fm fileExistsAtPath:path];
        [checked addObject:[NSString stringWithFormat:@"%@:%@", exists ? @"Y" : @"N", path]];
        if (!exists) continue;

        if (!winPath) {
            winPath = path;
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            winSize = attrs ? [attrs fileSize] : 0;

            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            r.metadataReadable = (data != nil);
            if (!data) {
                winState = @"unreadable";
            } else {
                NSError *perr = nil;
                id obj = [NSPropertyListSerialization propertyListWithData:data
                                                                   options:NSPropertyListImmutable
                                                                    format:nil
                                                                     error:&perr];
                if ([obj isKindOfClass:[NSDictionary class]]) {
                    parsed = obj;
                    winState = @"ok";
                    r.metadataParseable = YES;
                } else {
                    winState = @"unparseable";
                }
            }
        }
    }
    r.candidatesChecked = checked;
    r.metadataPath = winPath;
    r.metadataState = winState;
    r.metadataSize = winSize;
    r.metadataKeys = parsed ? [[parsed allKeys] sortedArrayUsingSelector:@selector(compare:)] : @[];
    r.genreId = parsed[@"genreId"];
    r.genre = parsed[@"genre"];

    // ── 5. Receipt presence (diagnostic only, never a classification signal) ──
    if (bundlePath.length) {
        r.receiptPresent =
            [fm fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@"StoreKit/sapreceipt"]] ||
            [fm fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@"StoreKit/receipt"]];
    }

    // ── 6. Info.plist store/genre/category keys — raw facts, no guessing ──
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSMutableDictionary *storeKeys = [NSMutableDictionary dictionary];
    for (NSString *key in info.allKeys) {
        NSString *low = key.lowercaseString;
        if ([low containsString:@"genre"] || [low containsString:@"category"] ||
            [low containsString:@"store"] || [low containsString:@"itunes"]) {
            id v = info[key];
            storeKeys[key] = [v isKindOfClass:[NSString class]] ? v : [v description];
        }
    }
    r.infoPlistStoreKeys = storeKeys;

    return r;
}

@end
