#ifndef GCLOUD_DOLPHINE_INTERFACE_H
#define GCLOUD_DOLPHINE_INTERFACE_H
#include "GCloudPal.h"
#define DOLPHIN_VERDESCRITIONLENGTH 256*5
#define DOLPHIN_USERDEFINESTRLENGTH 1024*50
#define DOLPHIN_UPDATEURLLENGTH 512
#define DOLPHIN_VEESIONURLLENGTH 1024
#define DOLPHIN_USERIDLENGTH 128
#define DOLPHIN_WORLDIDLENGTH 128
#define DOLPHIN_PATHLENGTH 256
#define DOLPHIN_VERSIONLENGTH 64
#define DOLPHIN_USERDATALENGTH 256
#define DOLPHIN_FUNC_DICT_LENGTH 512
#define DOLPHIN_TOKENLENGTH 1024

#ifdef CU_OS_WIN32
#define DOLPHINEXPORTAPI __declspec(dllexport)
#else
#define DOLPHINEXPORTAPI
#endif

namespace GCloud {
//--------------------------------  new version information  --------------------------------//
typedef struct dolphinVersionInfo {
  bool isAppUpdating;
  bool isNeedUpdating;
  bool isForcedUpdating;                                // Whether to force to update
  bool isApkDiffUpdating;                               // Whether Apk Diff Update
  cu_uint16 versionNumberOne;                           // versionNumberOne
  cu_uint16 versionNumberTwo;                           // versionNumberTwo
  cu_uint16 versionNumberThree;                         // versionNumberThree
  cu_uint16 versionNumberFour;                          // versionNumberFour
  cu_uint64 needDownloadSize;                           // Need to download size
  cu_uint64 totalDownloadSize;                          // Total ifs size
  cu_uint64 fullApkSize;                                // Full apk file size
  char versionDescrition[DOLPHIN_VERDESCRITIONLENGTH];  // version descrition
  char userDefineStr[DOLPHIN_USERDEFINESTRLENGTH];      // User-defined string on GCloud Server
  char userDefineStr2[DOLPHIN_USERDEFINESTRLENGTH];     // User-defined string2 on GCloud Server
  bool isAuditVersion;                                  // is audit version
  bool isGrayVersion;                                   // is gray version
  bool isNormalVersion;                                 // is normal version
  bool canPreUpdate;                                    // can pre-download update
  cu_int64 subidFilesizePtr;                            //for QTS engine
  cu_int32 arraySize;                                   //for QTS engine
  cu_int32 patchStartIndex;                             //for QTS engine
  dolphinVersionInfo() {
    isAppUpdating = false;
    isNeedUpdating = false;
    isForcedUpdating = false;
    isApkDiffUpdating = false;
    versionNumberOne = 0;
    versionNumberTwo = 0;
    versionNumberThree = 0;
    versionNumberFour = 0;
    needDownloadSize = 0;
    totalDownloadSize = 0;
    fullApkSize = 0;
    memset(versionDescrition, 0, DOLPHIN_VERDESCRITIONLENGTH);
    memset(userDefineStr, 0, DOLPHIN_USERDEFINESTRLENGTH);
    memset(userDefineStr2, 0, DOLPHIN_USERDEFINESTRLENGTH); 
    isAuditVersion = false;
    isGrayVersion = false;
    isNormalVersion = false;
    canPreUpdate = false;
    subidFilesizePtr = 0;
    arraySize = 0;
    patchStartIndex = 0;
  }
} DOLPHINVERSIONINFO;
#define QTS_STAGE_BASE_VALUE (100)
//--------------------------------  stages of the update process  --------------------------------//
typedef enum dolphinUpdateStage {
  VS_Start = 0,
  VS_DiffUpdate = 8,
  VS_FullUpdate = 9,
  VS_FirstExtract = 10,
  VS_FullUpdate_Extract,          // 11
  VS_FullUpdate_GetFileList,      // 12
  VS_FullUpdate_GetMetaFile,      // 13
  VS_FullUpdate_CompareMetaFile,  // 14
  VS_DownApkConfig,               // 15
  VS_CreateApk,                   // 16
  VS_CheckApkMd5,                 // 17
  VS_FullUpdate_CreateTask = 18,
  VS_Filelist_Check = 31,
  VS_Dolphin_Version = 69,
  VS_ApkUpdate = 70,
  VS_ApkUpdateDownConfig,
  VS_ApkUpdateDownDiffFile,
  VS_ApkUpdateDownFullApk,
  VS_ApkUpdateCheckCompletedApk,
  VS_ApkUpdateCheckLocalApk,
  VS_ApkUpdateCheckConfig,
  VS_ApkUpdateCheckDiff,
  VS_ApkUpdateMergeDiff,
  VS_ApkUpdateCheckFull,
  VS_ApkUpdateCheckPredownloadApk,
  VS_SourceUpdateCures = 90,
  VS_SourceUpdateDownloadList,
  VS_SourcePrepareUpdate,
  VS_SourceAnalyseDiff,
  VS_SourceDownload,
  VS_SourceExtract,
  VS_SourceDownload4IOSBGDownload,
  VS_SourceCheckPredownloadPatch,
  VS_SourceExtractPredownloadPatch,
  VS_Success = 99,
  VS_Fail = 100,

  VS_SourceUpdateCures_QTS = QTS_STAGE_BASE_VALUE + 90,
  VS_SourceUpdateDownloadList_QTS,
  VS_SourcePrepareUpdate_QTS,
  VS_SourceAnalyseDiff_QTS,
  VS_SourceExpandCures_QTS,
  VS_SourceDownload_QTS,
  VS_SourceExtract_QTS,
  VS_SourceCheckMD5_QTS,
  VS_SourceExtractAfterDownload_QTS,
} DOLPHINUPDATESTAGE;

//--------------------------------  UpdateInitType  --------------------------------//
typedef enum dolphinUpdateInitType {
  // Program Update
  UpdateInitType_OnlyProgram = 1,
  // Resource Update
  UpdateInitType_OnlySource,
  UpdateInitType_SourceCheckAndSync,                // find the files which is deleted or modified and then download it
  UpdateInitType_SourceCheckAndSync_Optimize_Full,  // find the files which is deleted or modified and check the deleted
                                                    // file whether exist or newest in app' first ifs,Final decide to
                                                    // download the files or not.
  UpdateInitType_SourceCheckAndSync_Optimize_Part,  // use with the UpdateType_Only_FirstExtract_Part ,beside the above
                                                    // consituation,when the file is partly extracted,it's function is
                                                    // the same as  'UpdateType_SourceCheckAndSync'
  UpdateInitType_SourceCheckAndSync_Optimize_Full_Scatter,  // if the resource in app is a scattered type,another word
                                                            // without IFS file.use this type can do the same as
                                                            // UpdateType_SourceCheckAndSync_Optimize_Full
  UpdateInitType_FirstExtract_All,   // All file will be extracted
  UpdateInitType_FirstExtract_Part,  // some files which specially delivered by user that the verbose 'mNeedExtractList'
                                     // in the init strcut 'UpdateInitInfo' will be extracted
  UpdateInitType_FirstExtract_Fix,  // Extract the files which is in app'ifs and which is the newest now to fill up the
                                    // outside resource.
  UpdateInitType_Normal,
} DOLPHINUPDATEINITTYPE;

typedef enum VersionUpdateMode {
  kUpdateVersionConnectNormal = 1,
  kUpdateVersionConnectParallel = 2,
  kUpdateVersionConnectMixAuto = 3,
  kUpdateVersionGetByCDN = 4,
} VERSIONUPDATEMODE;
typedef enum MergeFilelistType {
  kNormalNotMergeRes = 1,
  kMergeAppResIntoSDCARDRes,
  kModifyResInSDCARDRes,
} MERGEFILELISTTYPE;

typedef enum SystemParameterKey {
  HttpCurlSigleDownloadTimeout = 1,
  HttpCurlRecvBufferSize,
  MaxDownloadSpeed,

} SYSTEMPARAMETERKEY;

typedef enum DolphinImpType {
  kNormalDolphin,
  kCustomizeDolphin_QTCVFS,
} DOLPHINIMPTYPE;

typedef enum DolphinDownloadEngineType {
  kDownloadEngineType_Normal = 1,
  kDownloadEngineType_PCDN = 3,
  kDownloadEngineType_CrosCurl = 4,
} DOLPHINDOWNLOADENGINETYPE;

// a special download mode,reserved for now.
typedef enum _QtsDownloadMode {
  kStartUpdateWithServerMode = 1,
  kEnterGameUpdateSkipServerMode,
  kFixFileMode,
  kEnterGamePreUpdateDownloadJsonMode,
  kEnterGamePreUpdateDownloadResourceMode,
  kMultiProductDownloadMode = 12,
  kMultiProductDownloadModeOnlyJson = 13,
  kMultiProductDownloadModeWithoutServer = 14,
  kMultiProductDownloadFixMode = 15
} DownloadMode;

typedef enum GetPlayerVersionInfoResult {
  kGetPlayerVersionInfoResultNoSuchRecord = 0,
  kGetPlayerVersionInfoResultError,
  kGetPlayerVersionInfoResultIsNew,
  kGetPlayerVersionInfoResultNeedToUpdate,
} GetPlayerVersionInfoResult;

typedef struct qtsUpdateInfo {
  bool ClearDataAfterExtract;  // Whether enable ClearDataAtferExtract;
  bool useDolphinQts;          // Whether enable qts module.
  DownloadMode qtsUpdateMode;  // when use qts mode,there 3 function: 1-normal
                               // subpatch update; 2-skip server update subpatch;
                               // 3-subpatch fix source,default is 1.

} QTSUPDATEINFO;
typedef enum _CPUARCHType{
  kCPUArchTypeAuto = 0, //Decide by sdk 
  kCPUArchType64Bit, //64 bit cpu
  kCPUArchType32Bit //32 bit cpu
}CPUARCHType;
typedef struct qtsSubpatchInfo {
  bool should_download;
  char version[DOLPHIN_VERSIONLENGTH];
  cu_uint64 package_id;
  qtsSubpatchInfo() : should_download(true), package_id(0) { memset(version, 0, DOLPHIN_VERSIONLENGTH); }
  qtsSubpatchInfo(cu_uint64 id, const char* ver, bool enable) {
    package_id = id;
    should_download = enable;
    memset(version, 0, DOLPHIN_VERSIONLENGTH);
    memcpy(version, ver, strlen(ver));
  }
} QTSSUBPATCHINFO;
typedef struct ClientAuthInfo {
  cu_int32 msdkChannelId;
  char userId[DOLPHIN_USERIDLENGTH];
  char msdkToken[DOLPHIN_TOKENLENGTH];
  char moaToken[DOLPHIN_TOKENLENGTH];
  char appIdentityKey[DOLPHIN_TOKENLENGTH];
  ClientAuthInfo() : msdkChannelId(0) {
    memset(userId, 0, DOLPHIN_USERIDLENGTH);
    memset(msdkToken, 0, DOLPHIN_TOKENLENGTH);
    memset(moaToken, 0, DOLPHIN_TOKENLENGTH);
    memset(appIdentityKey, 0, DOLPHIN_TOKENLENGTH);
  }
} CLIENTAUTHINFO;

typedef enum DolphinSplitUpdateMode {
  kNotSplitUpdate = 0,
  kSplitFullUpdate = 1,
} DOLPHINSPLITUPDATEMODE;
//--------------------------------  UpdateInitInfo  --------------------------------//
typedef struct dolphinInitInfo {
  cu_uint32 channelId;               // Update channel ID
  dolphinUpdateInitType updateType;  // UpdateInitType
  bool isGrayUpdate;                 // gray update or not
  bool isCheckFileMd5;
  bool openDebugLog;
  bool openErrorLog;
  bool isCreateDiffFlist;  // Whether create diff file list when updating the resource
  bool enableIOSBgDownload;
  bool enableCDNGetVersion;
  bool enableSNI;
  bool enableApkDiffUpdate; /* Whether enable apk diff update, if it's value is false,
                               then apk update will download the whole full .apk file any way. */
  bool enableNoticeExtract;
  bool isSkipVersionServer;
  bool getChannelConfig;  // whether to get channel config
  bool getRegionid;       // whether to get region id
  VERSIONUPDATEMODE versionGetMode;
  MERGEFILELISTTYPE mergeFilelistType;
  char updateUrl[DOLPHIN_UPDATEURLLENGTH];    // GCloud server url
  char versionUrl[DOLPHIN_VEESIONURLLENGTH];  // Reserved field, not ope, Ignorable
  char appVersion[DOLPHIN_VERSIONLENGTH];     // app version
  char srcVersion[DOLPHIN_VERSIONLENGTH];     // resource version
  char userData[DOLPHIN_USERDATALENGTH];
  char needExtractList[DOLPHIN_PATHLENGTH];  // List of files that need to be extracted
  char sdCardPath[DOLPHIN_PATHLENGTH];
  char cdnVersionUrl[DOLPHIN_UPDATEURLLENGTH];
  char extraIfsUrl[DOLPHIN_VEESIONURLLENGTH];  // ifs url
  DOLPHINIMPTYPE dolphinImpType;
  char dolphinFuncDict[DOLPHIN_FUNC_DICT_LENGTH];             // func dict json string
  char strDolphinDownloadFuncDict[DOLPHIN_FUNC_DICT_LENGTH];  // func dict json string
  cu_uint32 uMaxDLTask;
  cu_uint32 uMaxDLPerTask;
  cu_uint32 uMinDLGapSize;
  cu_int32 max_concurrent_streams_;
  cu_int32 connectorType;
  cu_uint32 dns_mode_type_;
  cu_uint32 dolphin_download_engine_;
  QTSUPDATEINFO qtsUpdateInfo;
  bool use_qts_dolphin_;
  bool use_launcher_mode_;
  CPUARCHType cpu_arch_type; //  cpu arch,0:auto;1:64bit; 2:32bit
  bool enableAsyncExtract;   // only used in qts mode
  bool enable_remove_invalid_filelist_;
  CLIENTAUTHINFO clientAuthInfo;
  DOLPHINSPLITUPDATEMODE dolphinSplitUpdateMode;
  dolphinInitInfo() {
    channelId = 0;
    updateType = UpdateInitType_OnlyProgram;
    isGrayUpdate = false;
    isCheckFileMd5 = false;
    openDebugLog = true;
    openErrorLog = true;
    isCreateDiffFlist = false;
    enableIOSBgDownload = false;
    enableCDNGetVersion = false;
    enableSNI = false;
    enableApkDiffUpdate = true;
    enableNoticeExtract = false;
    isSkipVersionServer = false;
    getChannelConfig = false;
    getRegionid = false;
    versionGetMode = kUpdateVersionConnectNormal;
    mergeFilelistType = kNormalNotMergeRes;
    memset(updateUrl, 0, DOLPHIN_UPDATEURLLENGTH);
    memset(versionUrl, 0, DOLPHIN_VEESIONURLLENGTH);
    memset(appVersion, 0, DOLPHIN_VERSIONLENGTH);
    memset(srcVersion, 0, DOLPHIN_VERSIONLENGTH);
    memset(userData, 0, DOLPHIN_USERDATALENGTH);
    memset(needExtractList, 0, DOLPHIN_PATHLENGTH);
    memset(sdCardPath, 0, DOLPHIN_PATHLENGTH);
    memset(cdnVersionUrl, 0, DOLPHIN_UPDATEURLLENGTH);
    memset(extraIfsUrl, 0, DOLPHIN_VEESIONURLLENGTH);
    dolphinImpType = kNormalDolphin;
    memset(dolphinFuncDict, 0, DOLPHIN_FUNC_DICT_LENGTH);
    memset(strDolphinDownloadFuncDict, 0, DOLPHIN_FUNC_DICT_LENGTH);
    uMaxDLTask = 6;
    uMaxDLPerTask = 3;
    uMinDLGapSize = 256 * 1024;
    max_concurrent_streams_ = 1;
    connectorType = 1;
    dns_mode_type_ = 1;
    dolphin_download_engine_ = kDownloadEngineType_Normal;
    qtsUpdateInfo.useDolphinQts = false;
    qtsUpdateInfo.qtsUpdateMode = kStartUpdateWithServerMode;
    qtsUpdateInfo.ClearDataAfterExtract = false;
    use_qts_dolphin_ = false;
    use_launcher_mode_ = false;
    cpu_arch_type = kCPUArchTypeAuto;
    enableAsyncExtract = false;
    enable_remove_invalid_filelist_ = false;
    dolphinSplitUpdateMode = kNotSplitUpdate;
  }
} DOLPHININITINFO;

//--------------------------------  dolphin path info  --------------------------------//
typedef struct dolphinPathInfo {
  char updatePath[DOLPHIN_PATHLENGTH];
  char dolphinPath[DOLPHIN_PATHLENGTH];
  char curApkPath[DOLPHIN_PATHLENGTH];
  char ifsPath[DOLPHIN_PATHLENGTH];
  char diffExtractPath[DOLPHIN_PATHLENGTH];
  char packageExtractPath[DOLPHIN_PATHLENGTH];
  char ingameDiffExtractPath[DOLPHIN_PATHLENGTH];
  char predownloadPath[DOLPHIN_PATHLENGTH];
  dolphinPathInfo() {
    memset(updatePath, 0, DOLPHIN_PATHLENGTH);
    memset(dolphinPath, 0, DOLPHIN_PATHLENGTH);
    memset(curApkPath, 0, DOLPHIN_PATHLENGTH);
    memset(ifsPath, 0, DOLPHIN_PATHLENGTH);
    memset(diffExtractPath, 0, DOLPHIN_PATHLENGTH);
    memset(packageExtractPath, 0, DOLPHIN_PATHLENGTH);
    memset(ingameDiffExtractPath, 0, DOLPHIN_PATHLENGTH);
    memset(predownloadPath, 0, DOLPHIN_PATHLENGTH);
  }
} DOLPHINPATHINFO;

//--------------------------------  dolphin gray update info  --------------------------------//
typedef struct dolphinGrayInfo {
  char userID[DOLPHIN_USERIDLENGTH];    // user`s open ID , for gray update)
  char worldID[DOLPHIN_WORLDIDLENGTH];  // user`s world id,for gray update
  dolphinGrayInfo() {
    memset(userID, 0, DOLPHIN_USERIDLENGTH);
    memset(worldID, 0, DOLPHIN_WORLDIDLENGTH);
  }
} DOLPHINGRAYINFO;

typedef struct dolphinFirstExtractInfo {
  char ifsPath[DOLPHIN_PATHLENGTH];  // path of ifs file
  bool isAppendSourceUpdate;         // whether update resource after First Extract
  dolphinFirstExtractInfo() {
    isAppendSourceUpdate = true;
    memset(ifsPath, 0, DOLPHIN_PATHLENGTH);
  }
} DOLPHINFIRSTEXTRACTINFO;

// reserved for now.
typedef struct multiPlayInfo {
  int product_id;
  char res_ver[DOLPHIN_VERSIONLENGTH];
  bool need_download;
  multiPlayInfo() {
    product_id = -1;
    memset(res_ver, 0, DOLPHIN_VERSIONLENGTH);
    need_download = true;
  }
} MULTIPLAYINFO;

//--------------------------------  GCloudDolphinCallBackOri  --------------------------------//
class GCLOUD_EXPORT_CPP GCloudDolphinCallBackOri {
 public:
  virtual ~GCloudDolphinCallBackOri() {}
  /// <summary>
  /// After the new version information is obtained, the callback is triggered and the update process enters the wait
  /// phase. Need to implement the interface, manually call the mDolphin.Continue () interface to continue to perform
  /// the update, newVersionInfo is the new version information.
  /// </summary>
  /// <param name="newVersinInfo">New version information</param>
  virtual void OnDolphinVersionInfo(dolphinVersionInfo& newVersinInfo) = 0;

  /// <summary>
  /// Update process progress is obtained through this callback interface during the process of updating or repairing
  /// resources.
  /// </summary>
  /// <param name="curVersionStage">The stage at which the current version is upgraded</param>
  /// <param name="totalSize">Total size that needs to be downloaded</param>
  /// <param name="nowSize">Currently downloaded size</param>
  virtual void OnDolphinProgress(dolphinUpdateStage curVersionStage, cu_uint64 totalSize, cu_uint64 nowSize) = 0;

  /// <summary>
  /// Information in the process of updating or repairing resources. And the update process enters the waiting phase.
  /// </summary>
  /// <param name="curVersionStage">The stage at which the current version is upgraded</param>
  /// <param name="errorCode">Error code</param>
  virtual void OnDolphinError(dolphinUpdateStage curVersionStage, cu_uint32 errorCode) = 0;

  /// <summary>
  /// Tell the update or resource repair success with this callback
  /// </summary>
  virtual void OnDolphinSuccess() = 0;

  /// <summary>
  /// This callback interface informs the installation apk, after receiving this callback, the game can implement the
  /// apk installation logic.
  /// </summary>
  /// <param name="apkurl">Apk path</param>
  virtual void OnDolphinNoticeInstallApk(char* apkurl) = 0;

  /// <summary>
  /// Tell the First Extract success with this callback
  /// </summary>
  virtual void OnDolphinFirstExtractSuccess() = 0;

  /// <summary>
  /// After Dolphin Resource downloaded, OnNoticeSourceExtract callback will be triggered before extract resources.
  /// return 0 will return OnError, and return 1 will continue dolphin resource process.
  /// </summary>
  virtual bool OnNoticeExtract() = 0;

  virtual bool OnNoticeNextAction(int action_type) = 0;

  /// <summary>
  /// get channel config from server
  /// </summary>
  virtual void OnDolphinServerCfgInfo(const char* config) = 0;

  /// <summary>
  /// After Dolphin IOS background download completed, OnDolphinIOSBGDownloadDone callback will be triggered to notify
  /// app.
  /// </summary>
  virtual void OnDolphinIOSBGDownloadDone() = 0;

  /// <summary>
  /// get action msg
  /// </summary>
  virtual void OnActionMsgArrive(const char* msg) = 0;

  /// <summary>
  /// Reserved for now.
  /// After the new version information is obtained, the callback is triggered and the update process enters the wait
  /// phase.
  /// Need to implement the interface, manually call the mDolphin.Continue () interface to continue to perform the
  /// update, newVersionInfo is the new version information.
  /// </summary>
  /// <param name="newVersinInfo">New version information</param>
  virtual void OnQtsDolphinVersionInfo(dolphinVersionInfo& newVersinInfo, const char* fileInfo) = 0;

  /// <summary>
  /// Update process progress is obtained through this callback interface during the process of updating or repairing
  /// resources.
  /// </summary>
  /// <param name="curVersionStage">The stage at which the current version is upgraded</param>
  /// <param name="totalSize">Total size that needs to be downloaded</param>
  /// <param name="nowSize">Currently downloaded size</param>
  virtual void OnDolphinProgressDetail(int cur_version_stage, int file_info, cu_uint64 total_size,
                                       cu_uint64 now_size) = 0;
};

class GCLOUD_EXPORT_CPP GCloudDolphinCallBack : public GCloudDolphinCallBackOri {
 public:
  virtual ~GCloudDolphinCallBack() {}
  virtual void OnDolphinVersionInfo(dolphinVersionInfo& newVersinInfo) {}
  virtual void OnQtsDolphinVersionInfo(dolphinVersionInfo& newVersinInfo, const char* fileInfo) {}  // reserved for now.
  virtual void OnDolphinProgress(dolphinUpdateStage curVersionStage, cu_uint64 totalSize, cu_uint64 nowSize) {}
  virtual void OnDolphinError(dolphinUpdateStage curVersionStage, cu_uint32 errorCode) {}
  virtual void OnDolphinSuccess() {}
  virtual void OnDolphinNoticeInstallApk(char* apkurl) {}
  virtual void OnDolphinFirstExtractSuccess() {}
  virtual bool OnNoticeExtract() { return true; }
  virtual bool OnNoticeNextAction(int action_type) { return false; }
  virtual void OnDolphinServerCfgInfo(const char* config) {}
  virtual void OnDolphinIOSBGDownloadDone() {}
  virtual void OnActionMsgArrive(const char* msg) {}
  virtual void OnDolphinProgressDetail(int cur_version_stage, int file_info, cu_uint64 total_size, cu_uint64 now_size) {
  }
};

//--------------------------------  GCloudDolphinInterface  --------------------------------//
class GCLOUD_EXPORT_CPP GCloudDolphinInterface {
 public:
  virtual ~GCloudDolphinInterface() {}
  /// <summary>
  /// Initialize.program update, resource update, resource repair or first package decompression need to be initialized
  /// first, to inform the update related information.
  /// </summary>
  /// <returns>Whether the initialization was successful</returns>
  /// <param name="initInfo">Update related initialization information</param>
  /// <param name="pathInfo">Update related path</param>
  /// <param name="grayInfo">Gray update related information</param>
  /// <param name="feInfo">First Extract information</param>
  /// <param name="callBack">An object that implements the GCloudDolphinCallBack interface</param>
  virtual bool Init(const dolphinInitInfo* initInfo, const dolphinPathInfo* pathInfo, const dolphinGrayInfo* grayInfo,
                    const dolphinFirstExtractInfo* feInfo, GCloudDolphinCallBackOri* callBack) = 0;

  /// <summary>
  /// Deinitialize, release resource
  /// </summary>
  /// <returns>Whether uninit successful</returns>
  virtual bool Uninit() = 0;

  /// <summary>
  /// When receiving some callbacks from GCloudDolphinCallBack, the update service will be blocked, and you need to call
  /// ContinueUpdate to continue the update. <param name="bContinue">Continue to the next update phase</param>
  /// </summary>
  virtual void ContinueUpdate(bool bContinue) = 0;

  /// <summary>
  /// Call this interface to start the update service, check if the upgrade is needed, and return the result in callback
  /// OnDolphinVersionInfo
  /// </summary>
  virtual void CheckAppUpdate() = 0;

  /// <summary>
  /// Call this interface to stops the update service.
  /// </summary>
  virtual void CancelUpdate() = 0;

  /// <summary>
  /// This interface is temporarily reserved and can be ignored
  /// </summary>
  /// <returns></returns>
  virtual cu_uint32 GetLastError() = 0;

  /// <summary>
  /// In the game frame loop Update(), you need to call PollCallback() every frame to refresh the update process.
  /// </summary>
  /// <returns>whether succeed</returns>
  virtual bool PollCallback() = 0;

  /// <summary>
  /// Set IOS background download Attributes
  /// </summary>
  /// <returns>void</returns>
  /// <param name="bEnableCellularAccess">Whether Cellular Access is enabled</param>
  /// <param name="bEnableResumeData">Reserved</param>
  /// <param name="nSessionTimeout">Reserved</param>
  /// <param name="nRetry">Retry times when ios background download task failed. If don't want tasks to retry when
  /// failed then set it to 0; otherwise it is recommended to set it to 2</param>
  virtual void SetIOSBGDownloadAttribute(bool bEnableCellularAccess, bool bEnableResumeData,
                                         unsigned int nSessionTimeout, unsigned int nRetry) = 0;

  /// <summary>
  /// adjust Dolphin system parameter,eg:download engine,file system
  /// </summary>
  /// <param name="key">the detail parameter type
  /// <param name="value">a protocol for the type,it can be a interger or a string.
  /// <returns>void</returns>

  virtual void DynamicAdjustDolphinSystemParameter(SystemParameterKey key, char* value) = 0;

  /// <summary>
  /// Get download progress detail
  /// This interface is used to retrieve progress detail info.
  /// </summary>
  /// <returns>whether succeed</returns>
  virtual bool GetProgressDetail(int* curStage, int* file_info, cu_uint64* totalSize, cu_uint64* nowSize) = 0;

  /// <summary>
  /// Reserved for now.
  /// add one play info into this lifecycle,can be called many times.
  /// </summary>
  /// <param name="playInfo">the detail play info,include product id and version info
  /// <returns>void</returns>
  virtual bool AddPlayInfo(multiPlayInfo playInfo) = 0;

  /// <summary>
  /// Reserved for now.
  /// add one subpatch info into this lifecycle,can be called many times.
  /// </summary>
  /// <param name="subpatchInfo">the detail subpatch info,include subpatch id and version
  /// info <returns>void</returns>
  virtual void AddSubpatchInfo(const qtsSubpatchInfo& playInfo) = 0;

  /// <summary>
  /// Reserved for now.
  /// add one play info into this lifecycle,can be called many times.
  /// </summary>
  /// <param name="playInfo">input--the detail play info,include product id and version info
  /// <param name="filesize">output---All filesize.
  /// <returns>return enum GetPlayerVersionInfoResult</returns>
  virtual int GetPlayerVersionInfo(multiPlayInfo& playInfo, int64_t& fileSize, int sourceType = 0) = 0;

  /// <summary>
  /// Check local download cache
  /// </summary>
  /// <param name="productId">product id
  /// <returns>bool</returns>
  virtual bool IsDownloadCacheExist(int productId, const char* version) = 0;
};

GCLOUD_EXPORT_API GCloudDolphinInterface* CreateDolphin();
GCLOUD_EXPORT_API void ReleaseDolphin(GCloudDolphinInterface** dolphin);

GCLOUD_EXPORT_API GCloudDolphinInterface* CreateQtsDolphin();
GCLOUD_EXPORT_API void ReleaseQtsDolphin(GCloudDolphinInterface** dolphin);
}  // namespace GCloud

// for dll
#ifdef CU_OS_WIN32
extern "C" DOLPHINEXPORTAPI GCloud::GCloudDolphinInterface* CreateDllDolphin();
extern "C" DOLPHINEXPORTAPI void ReleaseDllDolphin(GCloud::GCloudDolphinInterface** dolphin);

extern "C" DOLPHINEXPORTAPI GCloud::GCloudDolphinInterface* CreateQtsDllDolphin();
extern "C" DOLPHINEXPORTAPI void ReleaseQtsDllDolphin(GCloud::GCloudDolphinInterface** dolphin);
#endif

#endif
