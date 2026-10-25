//
//  UQMCompatLayer.hpp
//  Crashot
//
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMCompatLayer_hpp
#define UQMCompatLayer_hpp

#include <sstream>
#include "UQMMacros.h"
#include "UQMMacroExpand.h"

#if UQM_PLATFORM_WINDOWS
#define uqm_strncpy(deestination,source,sourceLen) \
do { \
strncpy_s(deestination, sourceLen+1, source, sourceLen); \
} while (0)
#define uqm_strncat(deestination,source,sourceLen) \
do {\
strncat_s(deestination, sourceLen+1, source, sourceLen); \
} while (0)
#endif

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable: 4996)
#elif defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated"
#endif

NS_UQM_BEGIN

class UQMString
{
private:
    char *data;
    unsigned long len;
    
public:
    UQMString() : len(0)
    {
        data = UQM_SAFE_MALLOC(1, char);
        data[0] = '\0';
    }
    
    UQMString(const std::string &str)
    {
        len = str.size();
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, str.c_str(), len);
        data[len] = '\0';
    }
    
    UQMString(const char *strPtr)
    {
        if (strPtr == NULL)
        {
            len = 0;
            data = UQM_SAFE_MALLOC(1, char);
            data[0] = '\0';
            return;
        }
        
        len = (unsigned int) strlen(strPtr);
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, strPtr, len);
        data[len] = '\0';
    }
    
    UQMString(const UQMString &str)
    {
        len = (unsigned int) str.size();
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, str.c_str(), len);
        data[len] = '\0';
    }
    
    // 析构函数
    ~UQMString()
    {
        UQM_SAFE_FREE(data);
        len = 0;
    }
    
    // 重载+
    UQMString operator+(const UQMString &str) const
    {
        UQMString newStr;
        UQM_SAFE_FREE(newStr.data);
        newStr.len = len + (unsigned int) str.size();
        newStr.data = UQM_SAFE_MALLOC(newStr.len + 1, char);
        strncpy(newStr.data, data, len);
        strncat(newStr.data, str.data, str.length());
        newStr.data[newStr.len] = '\0';
        
        return newStr;
    }
    
    // 重载=
    UQMString &operator=(const UQMString &str)
    {
        if (this == &str)
        {
            return *this;
        }
        
        UQM_SAFE_FREE(data);
        len = str.len;
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, str.c_str(), len);
        data[len] = '\0';
        
        return *this;
    }
    
    // 重载=
    UQMString &operator=(const char *strPtr)
    {
        if (strPtr == NULL)
        {
            len = 0;
            data = UQM_SAFE_MALLOC(1, char);
            data[0] = '\0';
            return *this;
        }
        UQM_SAFE_FREE(data);
        len = (unsigned int) strlen(strPtr);
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, strPtr, len);
        data[len] = '\0';
        
        return *this;
    }
    
    // 重载=
    UQMString &operator=(const std::string &str)
    {
        UQM_SAFE_FREE(data);
        len = str.length();
        data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(data, str.c_str(), len);
        data[len] = '\0';
        
        return *this;
    }
    
    // 重载+=
    UQMString &operator+=(const UQMString &str)
    {
        len += str.len;
        char *new_data = UQM_SAFE_MALLOC(len + 1, char);
        strncpy(new_data, data, len);
        strncat(new_data, str.data,str.size());
        UQM_SAFE_FREE(data);
        data = new_data;
        data[len] = '\0';
        
        return *this;
    }
    
    // 重载==
    inline bool operator==(const UQMString &str) const
    {
        if (len != str.len)
        {
            return false;
        }
        return strcmp(data, str.data) == 0;
    }
    
    // 获取长度
    inline size_t size() const
    {
        return len;
    }
    
    inline size_t length() const
    {
        return len;
    }
    
    const std::string toString() const
    {
        if (data)
        {
            return data;
        }
        
        return "";
    }
    
    bool empty() const
    {
        return size() <= 0;
    }
    
    // 获取C字符串
    inline const char *c_str() const
    {
        return data;
    }
    
};

class UQMKVPair
{
public:
    UQMString key;
    UQMString value;
#if UQM_PLATFORM_WINDOWS
#else
    UQM_AutoParser("", O(key, value));
#endif
};

// 重新定义vector
template<typename T, unsigned int SPARE_CAPACITY = 16>
class UQMVector
{
public:
    //将构造函数声明为explicit ,是为了抑制由构造函数定义的隐式转换
    explicit UQMVector(unsigned long initSize = 0) : vectorSize(0), vectorCapacity(
                                                                                (unsigned int) initSize + SPARE_CAPACITY), objects(NULL)
    {
        objects = UQM_SAFE_MALLOC(initSize + SPARE_CAPACITY, T);
        
    }
    
    UQMVector(const UQMVector &rhs) : objects(NULL)
    {
        vectorSize = rhs.vectorSize;
        vectorCapacity = rhs.vectorCapacity;
        
        objects = UQM_SAFE_MALLOC(vectorCapacity, T);
        for (unsigned int k = 0; k < vectorSize; k++)
        {
            objects[k] = rhs.objects[k];
        }
    }
    
    ~UQMVector()
    {
        for (unsigned int i = 0; i < vectorSize; i++)
        {
            objects[i].~T();
        }
        UQM_SAFE_FREE(objects);
    }
    
    const UQMVector &operator=(const UQMVector &rhs)
    {
        if (this != &rhs)
        {
            for (unsigned int i = 0; i < vectorSize; i++)
            {
                objects[i].~T();
            }
            UQM_SAFE_FREE(objects);
            vectorSize = rhs.vectorSize;
            vectorCapacity = rhs.vectorCapacity;
            
            objects = UQM_SAFE_MALLOC(vectorCapacity, T);
            for (unsigned int k = 0; k < vectorSize; k++)
            {
                objects[k] = rhs.objects[k];
            }
        }
        
        return *this;
    }
    
    const UQMVector &operator=(const typename std::vector<T> &rhs)
    {
        if (!rhs.empty())
        {
            for (unsigned int i = 0; i < vectorSize; i++)
            {
                objects[i].~T();
            }
            UQM_SAFE_FREE(objects);
            vectorSize = rhs.size();
            vectorCapacity = rhs.capacity();
            
            objects = UQM_SAFE_MALLOC(vectorCapacity, T);
            for (unsigned int k = 0; k < vectorSize; k++)
            {
                objects[k] = rhs[k];
            }
        }
        
        return *this;
    }
    
    // 如果index错误，直接返回0的数据
    T &operator[](int index)
    {
        if (index < 0 || index >= vectorSize)
        {
            return objects[0];
        }
        return objects[index];
    }
    
    const T &operator[](int index) const
    {
        return objects[index];
    }
    
    //检测是否需要扩容
    void reserve()
    {
        reserve(vectorSize);
    }
    
    // 扩容数据
    void reserve(unsigned int newSize)
    {
        if (vectorCapacity > newSize)
        {
            return;
        }
        unsigned int newCapacity = newSize * 2 + 1;
        T *oldArr = objects;
        
        objects = UQM_SAFE_MALLOC(newCapacity, T);
        for (unsigned int k = 0; k < vectorSize; k++)
        {
            objects[k] = oldArr[k];
        }
        vectorCapacity = newCapacity;
        for (unsigned int i = 0; i < vectorSize; i++)
        {
            oldArr[i].~T();
        }
        UQM_SAFE_FREE(oldArr);  // 删除原来的数据
    }
    
    unsigned int size() const
    {
        return vectorSize;
    }
    
    unsigned int capacity() const
    {
        return vectorCapacity;
    }
    
    bool empty() const
    {
        return vectorSize == 0;
    }
    
    bool find(const T &t) const
    {
        for (int i = 0; i < vectorSize; i++)
        {
            if (objects[i] == t)
            {
                return true;
            }
        }
        
        return false;
    }
    
    void resize(unsigned int newSize)
    {
        reserve(newSize);
        vectorSize = newSize;
    }
    
    void push_back(const T &obj)
    {
        reserve();  // 检测容器大小
        objects[vectorSize++] = obj;
    }
    
    void pop_back()
    {
        objects[vectorSize].~T();
        vectorSize--;
    }
    
    const T &back() const
    {
        return objects[vectorSize - 1];
    }
    
    const T *begin()
    {
        return &objects[0];
    }
    
    T *end()
    {
        return &objects[vectorSize];
    }
    
    bool clear()
    {
        for (int i = 0; i < vectorSize; i++)
        {
            objects[i].~T();
        }
        vectorSize = 0;
        UQM_SAFE_FREE(objects);
        objects = UQM_SAFE_MALLOC(SPARE_CAPACITY, T);
        vectorCapacity = SPARE_CAPACITY;
        
        return true;
    }
    
    const T *end() const
    {
        return &objects[vectorSize];
    }
    
    std::string toString()
    {
        std::stringstream out;
        out << "Vector length:" << size() << ",capacity:" << capacity() << std::endl;
        for (int i = 0; i < vectorSize; i++)
        {
            out << "objects[" << i << "]:" << objects[i] << std::endl;
        }
        
        return out.str();
    }
    
    typedef T *iterator;
private:
    unsigned int vectorSize;
    unsigned int vectorCapacity;
    T *objects;
};

class UQMRetAdapter
{
public:
    
    void convert(bool &val, const bool &innerVal);
    
    void convert(double &val, const double &innerVal);
    
    void convert(float &val, const float &innerVal);
    
    void convert(int &val, const int &innerVal);
    
    //    void convert(long &val, const long &innerVal);
    
    void convert(int64_t &val, const int64_t &innerVal);
    
    void convert(std::string &val, const UQMString &innerVal)
    {
        val = innerVal.c_str();
    }
    
    void convert(UQMString &innerVal, const std::string &val)
    {
        innerVal = val;
    }
    
    void convert(std::map<std::string, std::string> &val, const UQMVector<UQMKVPair> &innerVal)
    {
        for (unsigned int i = 0; i < innerVal.size(); i++)
        {
            val.insert(std::make_pair(innerVal[i].key.c_str(), innerVal[i].value.c_str()));
        }
    }
    
    template<typename OutTypeRet, typename InnerTypeRet>
    void convert(std::vector<OutTypeRet> &val, const UQMVector<InnerTypeRet> &innerVal)
    {
        size_t s = innerVal.size();
        val.resize(s);
        for (unsigned int i = 0; i < s; ++i)
        {
            convert(val[i], innerVal[i]);        // operator[](size_t)
        }
    }
    
    template<typename OutTypeRet, typename InnerTypeRet>
    void convert(OutTypeRet &outTypeRet, const InnerTypeRet &innerTypeRet)
    {
#if UQM_PLATFORM_WINDOWS
#else
        outTypeRet.innerRetConvert(*this, innerTypeRet);
#endif
    };
};

class UQM_EXPORT UQMCompatManager
{
public:
    template<typename OutTypeRet, typename InnerTypeRet>
    static bool compatConvert(OutTypeRet &outTypeRet, const InnerTypeRet &innerTypeRet)
    {
        UQMRetAdapter ret;
        ret.convert(outTypeRet, innerTypeRet);
        return true;
    }
};

NS_UQM_END

#ifdef _MSC_VER
#pragma warning(pop)
#elif defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif
#endif /* UQMCompatLayer_hpp */
