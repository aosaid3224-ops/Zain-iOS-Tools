//
//  MGPAPerformanceAdjuster.h
//  kgvmp
//
//  Created by zohnzliu(刘专) on 2018/7/10.
//  Copyright © 2018年 mgpa. All rights reserved.
//
#import "kgvmp.h"

#ifndef MGPAPerformanceAdjuster_h
#define MGPAPerformanceAdjuster_h


@interface MGPAPerformanceAdjuster : NSObject

+ (instancetype)getInstance;

+ (void)setLogAble:(BOOL)enable;
+ (void)enableDebugMode;
+ (NSInteger)getVersionCode;
+ (NSString*)getVersionName;

- (void)initMGPA;
- (BOOL)checkSdkCanWork;
- (void)registerVmpCallback:(VmpCallbackDelegate)callback;
- (void)updateGameInfoInt:(NSInteger)key theValue:(NSString *)value;
- (void)updateGameInfoString:(NSString *)key theValue:(NSString *)value;
- (void)updateGameFPS:(float[])fpsArr;
- (void)postMatchFPSData:(NSInteger)length fpsList:(NSMutableArray* )fpsArr;
- (NSString*)getDataFromMGPA:(NSString*)key theValue:(NSString*) value;

- (int)hapticSupport;
- (int)hapticAmplitudeSupport;
- (void)hapticPlayWithJson:(NSString*)heJson withLoop:(int)loop withInterval:(int)interval withAmplitude:(int)amplitude;
- (void)hapticPlayWithFile:(NSString*)heFilePath withLoop:(int)loop withInterval:(int)interval withAmplitude:(int)amplitude;
- (void)hapticStop;

@end


#endif /* MGPAPerformanceAdjuster_h */
