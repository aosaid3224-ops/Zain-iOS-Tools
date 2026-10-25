#pragma once

#include "GCloudPal.h"

#if defined (ANDROID) || defined (_IOS)
namespace GCloud
{
   class GCLOUD_EXPORT_CPP IQRCodeObserver
    {
    public:
        virtual ~IQRCodeObserver(){};
		
        virtual void onLaunchInfo(const char* url)=0;
		
		virtual void onGenQRImgInfo(int tag, int ret, const char* imgPath)=0;
    };
	   
   class GCLOUD_EXPORT_CPP IQRCodeService
	 {
      protected:
         IQRCodeService();
         virtual ~IQRCodeService(); 
         
      public:
        static IQRCodeService& GetInstance();
         
        virtual bool AddObserver(const IQRCodeObserver* callback)=0;

		virtual void GenerateQRImage(const int tag, const int size, const char* content, const char* logoPath)=0;
     };
}

#endif
