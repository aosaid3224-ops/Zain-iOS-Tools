//
//  CLOperationLog.m
//

#import "CLOperationLog.h"

@implementation CLOperationEntry
@end

@implementation CLOperationLog {
    NSMutableArray<CLOperationEntry *> *_entries;
    NSString *_path;
}

+ (instancetype)sharedLog {
    static CLOperationLog *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _entries = [NSMutableArray array];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    _path = [docs stringByAppendingPathComponent:@"CLOperationLog.plist"];
    NSArray *raw = [NSArray arrayWithContentsOfFile:_path] ?: @[];
    for (NSDictionary *d in raw) {
        CLOperationEntry *e = [CLOperationEntry new];
        e.date = d[@"date"] ?: [NSDate date];
        e.kind = [d[@"kind"] integerValue];
        e.status = [d[@"status"] integerValue];
        e.title = d[@"title"] ?: @"";
        e.detail = d[@"detail"] ?: @"";
        [_entries insertObject:e atIndex:0];
    }
    return self;
}

- (void)addEntryWithKind:(CLOperationKind)kind status:(CLOperationStatus)status
                   title:(NSString *)title detail:(NSString *)detail {
    CLOperationEntry *e = [CLOperationEntry new];
    e.date = [NSDate date]; e.kind = kind; e.status = status;
    e.title = title ?: @""; e.detail = detail ?: @"";
    [_entries insertObject:e atIndex:0];
    if (_entries.count > 500) [_entries removeObjectsInRange:NSMakeRange(500, _entries.count - 500)];
    [self persist];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CLOperationLogDidAdd" object:e];
}

- (NSArray<CLOperationEntry *> *)allEntries { return [_entries copy]; }

- (void)clear { [_entries removeAllObjects]; [self persist]; }

- (void)persist {
    NSMutableArray *raw = [NSMutableArray array];
    for (CLOperationEntry *e in _entries) {
        [raw addObject:@{@"date": e.date ?: [NSDate date],
                         @"kind": @(e.kind), @"status": @(e.status),
                         @"title": e.title ?: @"", @"detail": e.detail ?: @""}];
    }
    [raw writeToFile:_path atomically:YES];
}

@end
