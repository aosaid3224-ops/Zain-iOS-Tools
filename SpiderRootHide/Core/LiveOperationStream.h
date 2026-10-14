#import <Foundation/Foundation.h>
#import "OperationLog.h"

@interface LiveOperationEvent : NSObject
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, assign) NSUInteger sequence;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) NSDate *operationTimestamp;
@property (nonatomic, strong) NSDate *dispatchedAt;
@property (nonatomic, strong) NSDate *renderedAt;
@property (nonatomic, assign) NSTimeInterval renderLagMs;
@property (nonatomic, copy) NSString *stage;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, assign) int exitStatus;
@property (nonatomic, assign) BOOL finalEvent;
@property (nonatomic, assign) BOOL update;
@end

typedef void (^LiveOperationEventHandler)(LiveOperationEvent *event);

@interface LiveOperationStream : NSObject
- (void)startForTransactionID:(NSString *)transactionID handler:(LiveOperationEventHandler)handler;
- (void)close;
@property (nonatomic, assign, readonly, getter=isClosed) BOOL closed;
@end
