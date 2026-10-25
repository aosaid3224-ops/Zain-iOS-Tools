/*
 * Critical.h
 *
 *  Created on: 2011-7-28
 *      Author: vforkkcai
 */

#ifndef CRITICAL_H_
#define CRITICAL_H_

#include "AMutex.h"
#include "ACondition.h"

namespace ABase
{
	class EXPORT_CLASS CCritical
	{
	public:
		CCritical(CMutex* pMutex);
		~CCritical();

	private:
		CMutex* m_pMutex;
	};

	//Read Write Lock
	enum LockMode
	{
		LockModeRead, LockModeWrite,
	};

	class EXPORT_CLASS CRWMutex
	{
	public:
		CRWMutex(bool bRecursive = true);
		~CRWMutex();
		
		void readLock();
		void readUnlock();
        void writeLock();
		void writeUnlock();

	private:
        int m_readCount;
        int m_writeCount;
		CMutex* m_pMutex;
        CCondition* m_pCondition;
        CMutex* m_writeMutex;
	};

	class EXPORT_CLASS CRWCritical
	{
	public:
		CRWCritical(CRWMutex* pMutex, LockMode type);
		~CRWCritical();

	private:
		LockMode m_type;
		CRWMutex* m_pMutex;
	};

}


#endif /* CRITICAL_H_ */
