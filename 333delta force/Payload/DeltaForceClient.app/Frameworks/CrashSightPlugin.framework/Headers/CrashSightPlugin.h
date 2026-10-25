//
//  CrashSight.h
//
//  Created by joyfyzhang on 2021/1/8.
//  Copyright © 2021 joyfyzhang. All rights reserved.
//

#ifndef CrashSight_h
#define CrashSight_h

#import <Foundation/Foundation.h>
#import <CrashSightCore/CrashSightCore.h>

/**
 * 异常上报模块
 * - 命名规则：固定为 UQMCrash + 渠道
 * - 必须实现 UQMCrashDelegate
 */
@interface CrashSightPlugin : NSObject <UQMCrashDelegate>

/** 插件必须是的单例的，建议使用 UQM 提供的宏定义进行处理
 * 单例宏处理 - 头文件部分
 */
SYNTHESIZE_SINGLETON_FOR_CLASS_HEADER(CrashSightPlugin)

@end

#endif /* CrashSight_h */
