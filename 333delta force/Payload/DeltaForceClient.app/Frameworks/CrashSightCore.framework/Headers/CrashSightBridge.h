//
// Created by joyfyzhang on 2021/6/13.
//

#ifndef UQM_CRASH_INTERFACE_H
#define UQM_CRASH_INTERFACE_H

#include "UQMMacros.h"

#ifdef __cplusplus
extern "C" {
#endif

    /**
     * 初始化函数
     * @param app_id CrashSight平台注册的AppID.
     * @param unexpected_terminating_detection_enable iOS异常退出检测，Android无效
     * @param debug_mode 是否开启调试模式，线上建议关闭
     * @param server_url 崩溃上报地址
     */
    void UQM_EXPORT cs_init(const char* app_id, bool unexpected_terminating_detection_enable, bool debug_mode, const char* server_url);


    /**
     * 打印日志
     * @param level 日志级别 0-silent, 1-error, 2-warning, 3-info, 4-debug, 5-verbose
     * @param tag 日志标签
     * @param log 日志内容
     */
    void UQM_EXPORT cs_log_info(int level, const char* tag, const char* log);

    /**
     * 添加用户数据，崩溃时上报
     * @param key 键
     * @param value 值
     */
    void UQM_EXPORT cs_set_user_value(const char* key, const char* value);

    /**
     * 设置用户ID
     * @param user_id 用户ID
     */
    void UQM_EXPORT cs_set_user_id(const char* user_id);

    /**
     * 上报捕获到的异常
     * @param type 异常类型
     * @param exception_name 异常名
     * @param exception_msg 异常消息
     * @param exception_stack 异常堆栈
     */
    void UQM_EXPORT cs_report_exception(int type, const char* exception_name, const char* exception_msg, const char* exception_stack, bool is_dump_nativeStack= false);


    /**
     * 测试崩溃
     */
    void UQM_EXPORT cs_trigger_crash();

#ifdef __cplusplus
}
#endif

#endif //UQM_CRASH_INTERFACE_H
