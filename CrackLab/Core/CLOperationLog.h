//
//  CLOperationLog.h
//  Crack Lab — operation journal (discover/inspect/baseline…).
//  Same discipline as Spider: every action is a dated, kinded entry.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CLOperationKind) {
    CLOperationKindInfo = 0,
    CLOperationKindDiscovery,
    CLOperationKindInspect,
    CLOperationKindBaseline,
    CLOperationKindBackup,      // reserved (phase 2)
    CLOperationKindPatch        // reserved (phase 3)
};

typedef NS_ENUM(NSInteger, CLOperationStatus) {
    CLOperationStatusSuccess = 0,
    CLOperationStatusFailed,
    CLOperationStatusSkipped
};

@interface CLOperationEntry : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) CLOperationKind kind;
@property (nonatomic, assign) CLOperationStatus status;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *detail;
@end

@interface CLOperationLog : NSObject
+ (instancetype)sharedLog;
- (void)addEntryWithKind:(CLOperationKind)kind status:(CLOperationStatus)status
                   title:(NSString *)title detail:(NSString *)detail;
- (NSArray<CLOperationEntry *> *)allEntries;   // newest first
- (void)clear;
@end
