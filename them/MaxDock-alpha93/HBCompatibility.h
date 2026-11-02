#ifndef HB_COMPATIBILITY_H
#define HB_COMPATIBILITY_H
// Actual release families in the requested iOS15-through26 range.
static inline int HBSupportsOSMajor(long major){return major==15||major==16||major==17||major==18||major==26;}
static inline int HBDefaultEnabledForOS(long major){return major==16;}
static inline int HBEngineEnabledForOS(long major,int enabled,long optInMajor){return HBSupportsOSMajor(major)&&enabled&&(major==16||optInMajor==major);}
// iOS16 keeps its established live re-enable behavior. Other families require
// explicit per-OS enablement plus a new SpringBoard launch before any hooks.
static inline int HBStartupAllowedForOS(long major,int enabled,long optInMajor){return major==16||HBEngineEnabledForOS(major,enabled,optInMajor);}
#endif
