/*
 * Event.h
 *
 *  Created on: 2011-7-28
 *      Author: vforkkcai
 */

#ifndef EVENT_H_
#define EVENT_H_

#if !defined(__ORBIS__) && !defined(__PROSPERO__) && !defined(__NX__) //
#include "ACondition.h"
#include "AMutex.h"
#else
#include "ABasePal.h"
#include <pthread.h>
#include <sys/time.h>
#endif

namespace ABase
{
    class EXPORT_CLASS CEvent
    {
    public:
        CEvent();
	~CEvent();
    public:
	void Wait();
	void TimeWait(a_uint32 tw); //millisecond
	void Set();
	void Reset();
    private:
#if !defined(__ORBIS__) && !defined(__PROSPERO__) && !defined(__NX__)
    #if !defined(_WIN32) && !defined(_WIN64)
        CMutex m_Mutex;
        CCondition* m_pCond;
    #else //Win
        HANDLE m_hEvent;
    #endif
#else // console
        pthread_cond_t _cond;
        pthread_mutex_t _mutex;
        bool _set_flag;
#endif
    };
}

#endif /* EVENT_H_ */


