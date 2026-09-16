//
//  SpiderJBHideStateStore.m
//

#import "SpiderJBHideStateStore.h"

@implementation SpiderJBHideAppState
@end

@implementation SpiderJBHideStateStore {
    NSMutableDictionary *_cache;
    NSString *_plistPath;
}

+ (instancetype)sharedStore {
    static SpiderJBHideStateStore *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    _plistPath = [docs stringByAppendingPathComponent:@"SpiderJBHideState.plist"];
    [self load];
    return self;
}

- (void)load {
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:_plistPath] ?: @{};
    _cache = [NSMutableDictionary dictionary];
    [raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        SpiderJBHideAppState *st = [SpiderJBHideAppState new];
        st.enabled = [obj[@"enabled"] boolValue];
        st.status = [obj[@"status"] integerValue];
        st.lastError = obj[@"lastError"];
        st.lastAppliedAt = obj[@"lastAppliedAt"];
        st.lastVerifiedAt = obj[@"lastVerifiedAt"];
        _cache[key] = st;
    }];
}

- (void)save {
    NSMutableDictionary *raw = [NSMutableDictionary dictionary];
    [_cache enumerateKeysAndObjectsUsingBlock:^(id key, SpiderJBHideAppState *st, BOOL *stop) {
        raw[key] = @{
            @"enabled": @(st.enabled),
            @"status": @(st.status),
            @"lastError": st.lastError ?: @"",
            @"lastAppliedAt": st.lastAppliedAt ?: [NSNull null],
            @"lastVerifiedAt": st.lastVerifiedAt ?: [NSNull null]
        };
    }];
    // Remove NSNull values for plist validity
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [raw enumerateKeysAndObjectsUsingBlock:^(id k, NSDictionary *d, BOOL *s) {
        NSMutableDictionary *m = [d mutableCopy];
        [m removeObjectsForKeys:[m allKeysForObject:[NSNull null]]];
        clean[k] = m;
    }];
    [clean writeToFile:_plistPath atomically:YES];
}

- (SpiderJBHideAppState *)stateForBundleID:(NSString *)bundleID {
    if (!bundleID.length) return [SpiderJBHideAppState new];
    SpiderJBHideAppState *st = _cache[bundleID];
    if (!st) { st = [SpiderJBHideAppState new]; st.status = SpiderJBHideStatusOff; }
    return st;
}

- (void)setEnabled:(BOOL)enabled forBundleID:(NSString *)bundleID {
    if (!bundleID.length) return;
    SpiderJBHideAppState *st = [self stateForBundleID:bundleID];
    st.enabled = enabled;
    if (!enabled) { st.status = SpiderJBHideStatusOff; st.lastError = nil; }
    else if (st.status == SpiderJBHideStatusOff) st.status = SpiderJBHideStatusConfigured;
    _cache[bundleID] = st;
    [self save];
}

- (void)updateStatus:(SpiderJBHideStatus)status error:(NSString *)error forBundleID:(NSString *)bundleID {
    if (!bundleID.length) return;
    SpiderJBHideAppState *st = [self stateForBundleID:bundleID];
    st.status = status;
    st.lastError = error;
    if (status == SpiderJBHideStatusApplied) st.lastAppliedAt = [NSDate date];
    _cache[bundleID] = st;
    [self save];
}

- (void)markVerifiedForBundleID:(NSString *)bundleID {
    if (!bundleID.length) return;
    SpiderJBHideAppState *st = [self stateForBundleID:bundleID];
    st.status = SpiderJBHideStatusVerified;
    st.lastError = nil;
    st.lastVerifiedAt = [NSDate date];
    _cache[bundleID] = st;
    [self save];
}

- (NSDictionary<NSString *, SpiderJBHideAppState *> *)allStates {
    return [_cache copy];
}

@end
