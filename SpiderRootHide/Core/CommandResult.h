#import <Foundation/Foundation.h>

@interface CommandResult : NSObject

@property (nonatomic, assign, readonly) BOOL success;
@property (nonatomic, assign, readonly) int exitCode;
@property (nonatomic, assign, readonly) int signalNumber;
@property (nonatomic, assign, readonly) int spawnError;
@property (nonatomic, copy, readonly) NSString *stdoutText;
@property (nonatomic, copy, readonly) NSString *stderrText;
@property (nonatomic, copy, readonly) NSData *stdoutData;
@property (nonatomic, copy, readonly) NSData *stderrData;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) BOOL timedOut;
@property (nonatomic, copy, readonly) NSString *commandPath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

- (instancetype)initWithCommandPath:(NSString *)path
                          arguments:(NSArray<NSString *> *)arguments
                           exitCode:(int)exitCode
                       signalNumber:(int)signalNumber
                         spawnError:(int)spawnError
                         stdoutText:(NSString *)stdoutText
                         stderrText:(NSString *)stderrText
                         stdoutData:(NSData *)stdoutData
                         stderrData:(NSData *)stderrData
                           duration:(NSTimeInterval)duration
                           timedOut:(BOOL)timedOut;

- (NSDictionary *)diagnosticDictionary;
- (NSString *)failureCategory;

@end
