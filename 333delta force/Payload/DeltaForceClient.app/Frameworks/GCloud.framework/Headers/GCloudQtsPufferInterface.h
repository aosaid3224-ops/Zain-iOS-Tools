#ifndef GCLOUD_QTS_PUFFER_INTERFACE_H
#define GCLOUD_QTS_PUFFER_INTERFACE_H

#include "GCloudPal.h"

#ifdef CU_OS_WIN32
#define PUFFEREXPORTAPI __declspec(dllexport)
#else
#define PUFFEREXPORTAPI
#endif

#define PUFFER_INITSTRINGLENGTH 256
#define PUFFER_CONFIG_DICT_LENGTH 512

namespace GCloud {
typedef enum QtsPufferInitStage {
  kStart = 0,
  kDownIFSSnapshot,   // 1, for qts puffer
  kUpdateFileList,    // 2
  kGetResURL,
  kGETFILELIST,
  kDownloadQTCVFSDB,  
  kUpdateQTCVFSDB,    // 2~6: not used for qts puffer
  kQtsParseJson,      // 7, for qts puffer
  kQtsCreateEifs,     // 8, for qts puffer
} QTSPUFFERINITSTAGE;

typedef enum QtsPufferSystemParameterKey {
  QtsPufferHttpCurlSigleDownloadTimeout = 1,
  QtsPufferHttpCurlRecvBufferSize,
  QtsPufferMaxDownloadSpeed,
} QTSPUFFERSYSTEMPARAMETERKEY;

typedef struct PufferQtsInitConfig {
  PufferQtsInitConfig() {
    puffer_imp_type = 0;
    product_id = 0;
    memset(download_path, 0, PUFFER_INITSTRINGLENGTH);
    memset(config_path, 0, PUFFER_INITSTRINGLENGTH);
    memset(diff_extract_path, 0, PUFFER_INITSTRINGLENGTH);
    memset(package_extract_path, 0, PUFFER_INITSTRINGLENGTH);
    max_download_speed = 100 * 1024 * 1024;
    max_tasks = 6;
    max_downloads_per_task = 3;
    memset(puffer_download_config_dic, 0, PUFFER_CONFIG_DICT_LENGTH);
  }
  // 0 - kNormalPuffer, 1 - kCustomizePuffer_QTCVFS ,2 - qtspuffer
  cu_uint32 puffer_imp_type;
  // channelId in gcloud console
  cu_uint32 product_id;
  // The local resource directory downloaded by Puffer, the downloaded file will be saved in this path.
  char download_path[PUFFER_INITSTRINGLENGTH];
  // The local config path
  char config_path[PUFFER_INITSTRINGLENGTH];
  // diff file extract path
  char diff_extract_path[PUFFER_INITSTRINGLENGTH];
  // package file extract path
  char package_extract_path[PUFFER_INITSTRINGLENGTH];

  // Puffer maximum download speed, default is 100M/s
  cu_uint32 max_download_speed;
  // The maximum number of concurrent Puffer tasks. The default is 6
  cu_uint32 max_tasks;
  // Puffer single task maximum number of concurrent download links, the default is 3
  cu_uint32 max_downloads_per_task;
  // Puffer Opti spped config dict json string
  char puffer_download_config_dic[PUFFER_CONFIG_DICT_LENGTH];

} QTSPUFFERINITCONFIG;
typedef struct _PACKAGEINFO{
  bool enable;
  cu_uint64 package_id;
  char version[PUFFER_INITSTRINGLENGTH];
  _PACKAGEINFO(){
    enable=true;
    package_id=-1;
    memset(version, 0, PUFFER_INITSTRINGLENGTH);
  }
}PackageInfo;

class GCLOUD_EXPORT_CPP IQTSPufferCallback{
 public:
  virtual ~IQTSPufferCallback() {}
  /// @brief one init one return callback.
  /// @param isSuccess 
  /// @param errorCode 
  virtual void OnInitReturn(bool isSuccess, cu_uint32 errorCode) = 0;
  
  /// @brief init progress
  /// @param stage 
  /// @param nowSize 
  /// @param totalSize 
  virtual void OnInitProgress(QtsPufferInitStage stage, cu_uint64 nowSize, cu_uint64 totalSize) = 0;
  
  /// @brief notice update information of package task
  /// @param task_id: task_id return by DownloadPackage(List)
  /// @param fileinfo: pkg_list json string
  /// @param needDownloadSize/totalSize: unit: Byte
  virtual void OnGetPackageInfo(cu_uint64 task_id,const char* fileinfo,cu_uint64 needDownloadSize,cu_uint64 totalSize) = 0;
  
  /// @brief download progress
  /// @param task_id: task_id return by DownloadPackage(List)
  /// @param nowSize/totalSize: download size, unit: Byte
  virtual void OnDownloadProgress(cu_uint64 task_id, cu_uint64 nowSize, cu_uint64 totalSize) = 0;
  
  /// @brief extract progress
  /// @param task_id: task_id return by DownloadPackage(List)
  /// @param nowSize/totalSize: decompressed size, unit: Byte
  virtual void OnExtractProgress(cu_uint64 task_id, cu_uint64 nowSize, cu_uint64 totalSize) {}
  
  /// @brief notice result of package task
  /// @param task_id: task_id return by DownloadPackage(List)
  /// @param filename: return filename when signle file download failed, return "" when whole batch task download completely
  /// @param error_code
  virtual void OnDownloadPackageReturn(cu_uint64 task_id, const char* filename, cu_uint32 error_code) = 0;
};
class GCLOUD_EXPORT_CPP IQTSPufferInterface{
 public:
  virtual ~IQTSPufferInterface() {}
  virtual bool Init(const PufferQtsInitConfig& init_config, IQTSPufferCallback* callback) = 0;
  virtual void Uninit() = 0;

  /// @brief Need to call this interface in every frame of the game Update()
  virtual void Update() = 0;

  /// @brief start a Download task of signle package
  /// @param package_info 
  /// @param force_sync 
  /// @param priority 
  /// @return task id
  virtual cu_uint64 DownloadPackage(const GCloud::PackageInfo& package_info, bool force_sync, cu_uint32 priority) = 0;
  
  /// @brief start a Download task of multi packages
  /// @param package_list_pointer
  /// @param package_list lenghth
  /// @param force_sync
  /// @param priority
  /// @return task id
  virtual cu_uint64 DownloadPackageList(const GCloud::PackageInfo* package_list_ptr, cu_uint32 length, bool force_sync, cu_uint32 priority) = 0;
  
  /// @brief get errorcode if DownloadPackage/DownloadPackageList return -1
  /// @return last errorcode
  virtual cu_uint32 GetLastError() = 0;

  /// @brief every task end whatever fail or success, we should call RemoveTask, suggest call this in OnDownloadReturn
  /// @param task_id 
  /// @return 
  virtual bool RemoveTask(cu_uint64 task_id) = 0;

  /// @brief Dynamically adjust task priority
  /// @param task_id 
  /// @param priority 
  /// @return 
  virtual bool SetTaskPriority(cu_uint64 task_id, cu_uint32 priority) = 0;

  /// @brief Dynamically set the maximum download speed in byte/s
  /// @param max_speed 
  /// @return 
  virtual bool SetMaxSpeed(cu_uint64 max_speed) = 0;

  /// @brief Pause a download task
  /// @param task_id 
  /// @return 
  virtual bool PauseTask(cu_uint64 task_id) = 0;

  /// @brief Resume a download task
  /// @param task_id 
  /// @return 
  virtual bool ResumeTask(cu_uint64 task_id) = 0;

  /// @brief Get need download size and total size of a package in byte
  /// @param package_info 
  /// @param needDownloadSize 
  /// @param totalSize 
  /// @return 
  virtual bool GetPackageDownloadSize(const GCloud::PackageInfo& package_info, cu_uint64& needDownloadSize, cu_uint64& totalSize) = 0;
  
  /// @brief Get current download speed in byte/s
  /// @return 
  virtual double GetCurrentSpeed() = 0;

  /// @brief Dynamically set the maximum number of download tasks
  /// @param maxTask
  /// @return 
  virtual bool SetImmDLMaxTask(cu_uint32 maxTask) = 0;

  /// @brief Dynamically set the maximum downloads of pre download task
  /// @param maxDownloadsPerTask 
  /// @return 
  virtual bool SetImmDLMaxDownloadsPerTask(cu_uint32 maxDownloadsPerTask) = 0;

  /// @brief adjust Puffer system parameter, eg: curl recv buffer size
  /// @param key the detail parameter type
  /// @param value a protocol for the type,it can be a interger or a string
  virtual void DynamicAdjustPufferSystemParamater(QTSPUFFERSYSTEMPARAMETERKEY key, char* value) = 0;
};
GCLOUD_EXPORT_API IQTSPufferInterface* CreateQtsPuffer();
GCLOUD_EXPORT_API void ReleaseQtsPuffer(IQTSPufferInterface** puffer);
}  // namespace GCloud

// for dll
#ifdef CU_OS_WIN32
extern "C" PUFFEREXPORTAPI GCloud::IQTSPufferInterface* CreateQtsDllPuffer();
extern "C" PUFFEREXPORTAPI void ReleaseQtsDllPuffer(GCloud::IQTSPufferInterface** puffer);
#endif

#endif//GCLOUD_PUFFER_INTERFACE_H
