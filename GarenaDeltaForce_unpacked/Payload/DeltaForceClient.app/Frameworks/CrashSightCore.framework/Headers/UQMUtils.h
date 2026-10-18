//
//  UQMUtils.hpp
//  Crashot
//(内部使用)简单的工具类声明，目前包含：
// 1. 生成通用唯一识别码
// 2. 格式化输出 Json 字符串
// 3. 字符串跟数字连接工具
// 4. 类型转换工具，将一个类型的值 <InType> 转换为另一个类型 <OutType>
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMUtils_hpp
#define UQMUtils_hpp

#include "UQMDefine.h"

NS_UQM_BEGIN

class UQM_EXPORT UQMUtils
{
public:
    // 移除空格
    static const char *Trim(const char *name);
};

NS_UQM_END

#endif /* UQMUtils_hpp */
