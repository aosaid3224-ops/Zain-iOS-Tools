//
//  UQMSingleton.hpp
//  Crashot
//
//  Created by joyfyzhang on 2020/9/3.
//  Copyright © 2020 joyfyzhang. All rights reserved.
//

#ifndef UQMSingleton_hpp
#define UQMSingleton_hpp

#include <stdio.h>
#include "UQMMacros.h"

template<class T>
class UQMSingleton
{
protected:
    UQMSingleton() {};
private:
    UQMSingleton(const UQMSingleton &) {};
    
    UQMSingleton &operator=(const UQMSingleton &) {};
    static T *mInstance;
#if UQM_PLATFORM_WINDOWS
#else
    static pthread_mutex_t mMutex;
#endif
public:
    static T *GetInstance();
};


template<class T>
T *UQMSingleton<T>::GetInstance()
{
    if (mInstance == NULL)
    {
#if UQM_PLATFORM_WINDOWS
#else
        pthread_mutex_lock(&mMutex);
#endif
        if (mInstance == NULL)
        {
            T *tmp = new T();
            mInstance = tmp;
        }
#if UQM_PLATFORM_WINDOWS
#else
        pthread_mutex_unlock(&mMutex);
#endif
    }
    return mInstance;
}

#if UQM_PLATFORM_WINDOWS
#else
template<class T>
pthread_mutex_t UQMSingleton<T>::mMutex = PTHREAD_MUTEX_INITIALIZER;
#endif

template<class T>
T *UQMSingleton<T>::mInstance = NULL;


#endif /* UQMSingleton_hpp */
