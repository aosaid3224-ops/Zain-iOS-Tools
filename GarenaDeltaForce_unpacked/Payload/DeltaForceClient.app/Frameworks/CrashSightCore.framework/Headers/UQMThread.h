/*!
 * @header UQMThread.h
 * @Version 2.0.0
 * @date 2018/4/25
 * @abstract
 * thread 的简单封装声明
 * 
 * @copyright
 * Copyright © 2018年. All rights reserved.
 */

#ifndef UQM_THREAD_H
#define UQM_THREAD_H

#include <sstream>
#include "UQMLog.h"
#include "UQMMacros.h"

NS_UQM_BEGIN
/*
* 设置当前线程名字
* @param module 模块名称
* 为使用iOS，只能在当前线程内调用
*/
bool thread_set_msdk_name(const std::string &module);


#ifdef ANDROID
/*
 * 线程获取自己的名字
 * @return 当前线程名称
 */
std::string thread_self_get_name();


/*
 * 线程设置自己的名称
 */
bool thread_self_set_name(const std::string &name);
#endif
NS_UQM_END

#endif //UQM_THREAD_H
