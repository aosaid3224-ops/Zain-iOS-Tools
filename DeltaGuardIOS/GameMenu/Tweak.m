#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <CommonCrypto/CommonCrypto.h>
#include <mach/vm_map.h>
#include <stdlib.h>
#include <unistd.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#ifndef LC_DYLD_EXPORTS_TRIE
#define LC_DYLD_EXPORTS_TRIE 0x80000033 /* شجرة تصدير dyld3 الحديثة — Xcode 13+ */
#endif

/* نفس تخطيط CAFrameRateRange (iOS 15+) */
typedef struct { float minimum; float maximum; float preferred; } DGFrameRateRange;

@interface DGMenu : NSObject
+ (void)hidePanel;
+ (void)install;
+ (void)start;
+ (void)dgStartPart:(int)idx;
+ (void)dgAssemble;
@end

@interface DGDownloadDelegate : NSObject <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@end

@interface DGFloatButton : UIButton
@property(nonatomic,getter=isDGMinimized) BOOL dgMinimized;
@end

static UIWindow *DGWindow;
static DGFloatButton *DGButton;
static UIView *DGPanel;
static UIView *DGEspView;
static UILabel *DGStatsLabel;
static UILabel *DGSceneLabel;
static UILabel *DGCoordLabel;
static UILabel *DGCandidatesLabel;
static UILabel *DGCoordPill;
static UISwitch *DG90Switch;
static UISwitch *DGTrainingSwitch;
static UISwitch *DGDebugSwitch;
static UILabel *DG90Note;
static UIScrollView *DGScroll;
static UIButton *DGDLButton;
static UIProgressView *DGDLBar;
static UILabel *DGDLProgressLabel;
static UILabel *DGDLStatusLabel;
static NSURLSession *DGDLSession;
static DGDownloadDelegate *DGDLDelegate;
static NSMutableData *DGDLBuffer;
static long DGDLPartsDone;
static long DGDLCurrentPartBytes;
static int DGDLCurrentPart;
static BOOL DGDLBusy=NO;
static UILabel *DGUE4Label;
static char DGUE4Stat[256]="الماسح لم يبدأ بعد";
static int DGUE4ScanCount=0;
static BOOL DGUE4FoundFlag=NO;
static char DGUE4FoundAddr[64]="";
static BOOL DGDLResponseValid=NO;
static NSInteger DGDLHTTPStatusCode=0;
static const long DGDLPartSizes[5]={90000000L,90000000L,90000000L,90000000L,56167600L};
static NSString *const DGDLExpectedSHA256=@"175b75f14edcdd409d3267f19ec3997b6fda415d71a0b3c7650d66b040bdc599";
static NSDate *DGSessionStart;
static CADisplayLink *DGLink;
static NSUInteger DGFrameCount;
static NSUInteger DGFPS;
static NSTimer *DGStatsTimer;
static NSTimer *DGDiscoveryTimer;
static BOOL DG90Enabled=NO;
static NSInteger DGRealMaxFPS=60; /* قدرة الشاشة الحقيقية (تُلتقط قبل السوازل) */
static NSString *const DG90Key=@"DG90Enabled";
static NSString *const DGFloatPosKey=@"DGFloatPos";
static NSString *const DGPanelPosKey=@"DGPanelPos";
static NSString *const DGForceTrainingKey=@"DGForceTraining";
static NSString *const DGDebugLinesKey=@"DGDebugLines";
static BOOL DGStarted=NO;
static BOOL DGForceTraining=NO;
static BOOL DGDebugLines=NO;
static dispatch_block_t DGIdleBlock;
static void DGHaptic(void);
static BOOL DGVerifyPoolStruct(uint64_t A);

/* قاعدة الكاميرا الحالية — تُحدّث كل فريم عند تفعيل خطوط التجربة */
static float DGCamPos[3]={0,0,0}, DGCamFwd[3]={0,0,1}, DGCamRight[3]={1,0,0}, DGCamUp[3]={0,1,0};
static float DGCamFov=60.0f;
static BOOL DGHavCamBasis=NO;

/* ============================================================
   المرحلة 1 — Entity Discovery
   اكتشاف بيئة IL2CPP داخل العملية وقراءة الإحداثيات للتشخيص
   ============================================================ */

typedef void* (*DGDomainGetFn)(void);
typedef void** (*DGDomainGetAssembliesFn)(void*, size_t*);
typedef void* (*DGAssemblyGetImageFn)(void*);
typedef void* (*DGClassFromNameFn)(void*, const char*, const char*);
typedef void* (*DGClassGetMethodFn)(void*, const char*, int);
typedef void* (*DGRuntimeInvokeFn)(void*, void*, void**, void**);
typedef void* (*DGObjectUnboxFn)(void*);
typedef const uint16_t* (*DGStringCharsFn)(void*);
typedef int32_t (*DGStringLengthFn)(void*);
typedef const char* (*DGImageGetNameFn)(const void*);
typedef void (*DGClassVisitorFn)(void*, void*);
typedef void (*DGClassForEachFn)(DGClassVisitorFn, void*);

static BOOL DGTryOffsetResolver(void);
static void DGResolveProfilerFns(uint32_t count);

static struct {
    BOOL available;
    DGDomainGetFn domain_get;
    DGDomainGetAssembliesFn domain_get_assemblies;
    DGAssemblyGetImageFn assembly_get_image;
    DGClassFromNameFn class_from_name;
    DGClassGetMethodFn class_get_method_from_name;
    DGRuntimeInvokeFn runtime_invoke;
    DGObjectUnboxFn object_unbox;
    DGStringCharsFn string_chars;
    DGStringLengthFn string_length;
    DGImageGetNameFn image_get_name;
    DGClassForEachFn class_for_each; /* اختياري */
    size_t assemblies;
    char imageName[96];
    /* مراسي il2cpp المثبتة التصدير — دليل حضور وقت التشغيل */
    void *fn_class_get_name;
    void *fn_method_get_name;
    void *fn_object_get_size;
    int partialAPIs;        /* عدد المراسي المحلولة */
    int resolvedViaOffsets; /* 1 = الحل تم عبر أوفسيتات التحليل */
} DGIL2CPP;

static NSMutableArray<NSString*> *DGCandidateClasses = nil;
static BOOL DGCandidatesScanned = NO;
static BOOL DGClassesSeen = NO; /* هل ظهرت كلاسات IL2CPP فعلاً (Unity مهيأ) */

/* ===== ماسح شجرة تصدير Mach-O — بديل مباشر عن dlopen/dlsym ===== */
static uint64_t DGUleb128(const uint8_t **p, const uint8_t *end){
    uint64_t r=0; unsigned s=0;
    while(*p<end){
        uint8_t b=**p; (*p)++;
        r|=((uint64_t)(b&0x7f))<<s;
        if(!(b&0x80)) break;
        s+=7;
        if(s>63) break;
    }
    return r;
}

static BOOL DGTrieNode(const uint8_t *node, const uint8_t *trieStart, const uint8_t *trieEnd, const char *want, const char *prefix, uint64_t slide, void **out){
    if(node<trieStart || node>=trieEnd) return NO;
    const uint8_t *p=node;
    uint64_t termSize=DGUleb128(&p,trieEnd);
    const uint8_t *afterTerm=p+termSize;
    if(termSize>0){
        (void)DGUleb128(&p,trieEnd); /* flags */
        uint64_t addr=DGUleb128(&p,trieEnd);
        if(strcmp(prefix,want)==0){
            *out=(void*)(uintptr_t)(addr+slide);
            return YES;
        }
    }
    p=afterTerm;
    if(p>=trieEnd) return NO;
    uint64_t kids=DGUleb128(&p,trieEnd);
    for(uint64_t i=0;i<kids && p<trieEnd;i++){
        const char *label=(const char*)p;
        size_t ll=0;
        while(p+ll<trieEnd && label[ll]) ll++;
        if(p+ll>=trieEnd) break;
        p+=ll+1;
        uint64_t off=DGUleb128(&p,trieEnd);
        char buf[200];
        size_t pl=strlen(prefix);
        if(pl+ll>=sizeof(buf)) continue;
        memcpy(buf,prefix,pl); memcpy(buf+pl,label,ll); buf[pl+ll]=0;
        size_t wl=strlen(want);
        size_t m=(pl+ll)<wl?(pl+ll):wl;
        if(m>0 && memcmp(buf,want,m)==0){
            if(DGTrieNode(trieStart+off,trieStart,trieEnd,want,buf,slide,out)) return YES;
        }
    }
    return NO;
}

/* استخراج (offset,size) لشجرة التصدير من أي من الأمرين القديم والحديث */
static BOOL DGGetTrieInfo(const struct mach_header_64 *mh, uint64_t *outOff, uint64_t *outSize){
    const uint8_t *cs=(const uint8_t*)mh+sizeof(struct mach_header_64);
    for(uint32_t i=0;i<mh->ncmds;i++){
        const struct load_command *lc=(const struct load_command*)cs;
        if(lc->cmd==LC_DYLD_INFO || lc->cmd==LC_DYLD_INFO_ONLY){
            const struct dyld_info_command *di=(const struct dyld_info_command*)lc;
            *outOff=di->export_off; *outSize=di->export_size;
            return di->export_size>0;
        }
        if(lc->cmd==LC_DYLD_EXPORTS_TRIE){
            const uint32_t *f=(const uint32_t*)lc; /* cmd,cmdsize,dataoff,datasize */
            *outOff=f[2]; *outSize=f[3];
            return f[3]>0;
        }
        cs+=lc->cmdsize;
    }
    return NO;
}

static uint64_t DGFileOffToVMAddr(const struct mach_header_64 *mh, uint64_t fileoff, uint64_t slide){
    const uint8_t *sg=(const uint8_t*)mh+sizeof(struct mach_header_64);
    for(uint32_t j=0;j<mh->ncmds;j++){
        const struct load_command *l2=(const struct load_command*)sg;
        if(l2->cmd==LC_SEGMENT_64){
            const struct segment_command_64 *seg=(const struct segment_command_64*)sg;
            if(fileoff>=seg->fileoff && fileoff<seg->fileoff+seg->filesize)
                return seg->vmaddr+(fileoff-seg->fileoff)+slide;
        }
        sg+=l2->cmdsize;
    }
    return 0;
}

/* البحث عن رمز مصدّر داخل صورة محمّلة عبر شجرة التصدير — دون الحاجة لـ dlopen */
static void* DGExportLookup(uint32_t idx, const char *sym){
    const struct mach_header_64 *mh=(const struct mach_header_64 *)_dyld_get_image_header(idx);
    if(!mh || mh->magic!=MH_MAGIC_64) return NULL;
    uint64_t slide=_dyld_get_image_vmaddr_slide(idx);
    uint64_t off=0,sz=0;
    if(!DGGetTrieInfo(mh,&off,&sz)) return NULL;
    uint64_t va=DGFileOffToVMAddr(mh,off,slide);
    if(!va) return NULL;
    const uint8_t *trie=(const uint8_t*)(uintptr_t)va;
    void *out=NULL;
    DGTrieNode(trie,trie,trie+sz,sym,"",slide,&out);
    return out;
}

/* البحث بالصيغتين: مع شرطة سفلية وبدون — شجرة التصدير تخزن _name للدوال C */
static void* DGExportLookupU(uint32_t idx, const char *sym){
    void *p=DGExportLookup(idx,sym);
    if(!p && sym[0]!='_'){
        char buf[160];
        snprintf(buf,sizeof(buf),"_%s",sym);
        p=DGExportLookup(idx,buf);
    }
    return p;
}

/* تفريغ كل أسماء رموز شجرة التصدير — لكشف الأسماء المعاد تسميتها */
static void DGTrieDump(const uint8_t *node, const uint8_t *start, const uint8_t *end, char *prefix, size_t prefixCap, NSMutableString *out, NSUInteger *count){
    if(*count>=30000) return;
    if(node<start||node>=end) return;
    const uint8_t *p=node;
    uint64_t termSize=DGUleb128(&p,end);
    const uint8_t *afterTerm=p+termSize;
    if(termSize>0 && prefix[0]){
        [out appendFormat:@"%s\n",prefix];
        (*count)++;
    }
    p=afterTerm;
    if(p>=end) return;
    uint64_t kids=DGUleb128(&p,end);
    for(uint64_t i=0;i<kids && p<end;i++){
        const char *label=(const char*)p;
        size_t ll=0;
        while(p+ll<end && label[ll]) ll++;
        if(p+ll>=end) break;
        p+=ll+1;
        uint64_t off=DGUleb128(&p,end);
        size_t pl=strlen(prefix);
        if(pl+ll+1<prefixCap){
            memcpy(prefix+pl,label,ll); prefix[pl+ll]=0;
            DGTrieDump(start+off,start,end,prefix,prefixCap,out,count);
            prefix[pl]=0;
        }
    }
}

static void DGDumpImageExports(uint32_t idx, NSMutableString *out, NSUInteger *total){
    const struct mach_header_64 *mh=(const struct mach_header_64 *)_dyld_get_image_header(idx);
    if(!mh || mh->magic!=MH_MAGIC_64) return;
    uint64_t slide=_dyld_get_image_vmaddr_slide(idx);
    uint64_t off=0,sz=0;
    if(!DGGetTrieInfo(mh,&off,&sz)) return;
    uint64_t va=DGFileOffToVMAddr(mh,off,slide);
    if(!va) return;
    char prefix[600]={0};
    DGTrieDump((const uint8_t*)(uintptr_t)va,(const uint8_t*)(uintptr_t)va,(const uint8_t*)(uintptr_t)(va+sz),prefix,sizeof(prefix),out,total);
}

/* ===== حالة التشخيص ===== */
static unsigned DGImagesScanned=0;
static char DGHitImage[128]="";
static char DGDiagShort[64]="—";
static NSString *DGLastDiag=nil;
static char DGAnchorHost[256]="";
static uint64_t DGMetaAddr=0;
static uint64_t DGCSharpAddr=0;
static uint64_t DGMetaSize=0;
static uint32_t DGSymCount=0;
static uint32_t DGSymHits=0;

/* قراءة آمنة عبر kernel — لا تكراش أبدًا على صفحات غير مخصصة */
static uint8_t* DGSafeRead(uint64_t at, uint64_t len, uint64_t *got){
    vm_offset_t data=0; mach_msg_type_number_t cnt=0;
    kern_return_t kr=vm_read(mach_task_self(),(vm_address_t)at,(vm_size_t)len,&data,&cnt);
    if(kr!=KERN_SUCCESS || !data){ *got=0; return NULL; }
    *got=cnt;
    return (uint8_t*)data; /* المستدعي يحرره بـ vm_deallocate */
}
static void DGFreeRead(uint8_t *p, uint64_t got){
    if(p) vm_deallocate(mach_task_self(),(vm_address_t)p,(vm_size_t)got);
}

/* بحث آمن في كل الذاكرة عن توقيع metadata — القراءة عبر kernel */
static void DGScanMemoryForMetadata(void){
    static BOOL tried=NO; if(tried) return; tried=YES;
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:@"global-metadata.dat"];
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];
    vm_address_t addr=(vm_address_t)0x100000000ULL;
    for(;;){
        vm_size_t size=0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj=MACH_PORT_NULL;
        kern_return_t kr=vm_region_64(mach_task_self(),&addr,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&cnt,&obj);
        if(kr!=KERN_SUCCESS) break;
        if(obj!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),obj);
        if((info.protection&VM_PROT_READ) && size>4096){
            uint64_t off=0;
            while(off<size){
                uint64_t want=size-off; if(want>33554432) want=33554432; /* 32MB */
                uint64_t got=0;
                uint8_t *buf=DGSafeRead((uint64_t)addr+off,want,&got);
                if(!buf) break; /* منطقة غير مقروءة بالكامل — تخطَّ */
                /* بحث التوقيع داخل النسخة الآمنة */
                const uint8_t *p=buf;
                uint64_t rem=got;
                while(rem>16){
                    p=(const uint8_t*)memchr(p,0xAF,rem-16);
                    if(!p) break;
                    uint32_t v,ver;
                    memcpy(&v,p,4);
                    if(v==0xFAB11BAFu){
                        memcpy(&ver,p+4,4);
                        if(ver>=21 && ver<=40){
                            uint64_t fileAt=(uint64_t)addr+off+(uint64_t)(p-buf);
                            uint64_t dumpGot=0;
                            uint64_t dumpWant=(uint64_t)size-off-(uint64_t)(p-buf);
                            if(dumpWant>100663296) dumpWant=100663296;
                            uint8_t *dump=DGSafeRead(fileAt,dumpWant,&dumpGot);
                            if(dump){
                                NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:out];
                                if(!fh){ [[NSFileManager defaultManager] createFileAtPath:out contents:nil attributes:nil]; fh=[NSFileHandle fileHandleForWritingAtPath:out]; }
                                if(fh){
                                    [fh truncateFileAtOffset:0];
                                    [fh writeData:[NSData dataWithBytes:dump length:(NSUInteger)dumpGot]];
                                    [fh closeFile];
                                    NSString *docs=@"/var/mobile/Documents";
                                    [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
                                    NSString *destination=[docs stringByAppendingPathComponent:@"global-metadata.dat"];
                                    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
                                    [[NSFileManager defaultManager] copyItemAtPath:out toPath:destination error:nil];
                                    DGMetaAddr=fileAt; DGMetaSize=dumpGot;
                                }
                                DGFreeRead(dump,dumpGot);
                            }
                            DGFreeRead(buf,got);
                            return;
                        }
                    }
                    rem=(uint64_t)(buf+got)-(uint64_t)(p+1);
                    p=p+1;
                }
                DGFreeRead(buf,got);
                off+=got?got:want;
                if(!got) break;
            }
        }
        addr+=size;
        if(addr<0x100000000) break;
    }
}

/* محلل جدول الرموز nlist — الثنائي يحتفظ برموز محلية كاملة (دليل: سجل الكراش) */
static void DGDumpSymbols(void){
    if(DGSymCount) return;
    const struct mach_header_64 *mh=(const struct mach_header_64*)_dyld_get_image_header(0);
    if(!mh||mh->magic!=MH_MAGIC_64) return;
    uint64_t slide=_dyld_get_image_vmaddr_slide(0);
    const uint8_t *cs=(const uint8_t*)mh+sizeof(struct mach_header_64);
    struct symtab_command sc; memset(&sc,0,sizeof(sc));
    uint64_t le_vm=0,le_off=0; BOOL haveSc=NO,haveLe=NO;
    for(uint32_t j=0;j<mh->ncmds;j++){
        const struct load_command *l2=(const struct load_command*)cs;
        if(l2->cmd==LC_SYMTAB){ sc=*(const struct symtab_command*)l2; haveSc=YES; }
        else if(l2->cmd==LC_SEGMENT_64){
            const struct segment_command_64 *seg=(const struct segment_command_64*)l2;
            if(strncmp(seg->segname,"__LINKEDIT",16)==0){ le_vm=seg->vmaddr; le_off=seg->fileoff; haveLe=YES; }
        }
        cs+=l2->cmdsize;
    }
    if(!haveSc||!haveLe||!sc.nsyms) return;
    const char *strtab=(const char*)(uintptr_t)(le_vm+(sc.stroff-le_off)+slide);
    const struct nlist_64 *syms=(const struct nlist_64*)(uintptr_t)(le_vm+(sc.symoff-le_off)+slide);
    DGSymCount=sc.nsyms;
    static const char *kw[]={
        "GEngine","GWorld","UObjectArray","GUObjectArray","GNames","FName",
        "PlayerController","PlayerCharacter","PlayerPawn","Character","Controller",
        "CameraManager","PlayerCameraManager","AcknowledgedPawn","Pawn","Actor",
        "RootComponent","SceneComponent","Transform","GObject","GNatives",
        "UWorld","ULevel","GameInstance","LocalPlayer","Player","Team","Health","Bone",
        NULL
    };
    NSString *docs=@"/var/mobile/Documents";
    [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[docs stringByAppendingPathComponent:@"deltaguard_symbols.txt"];
    FILE *f=fopen([path UTF8String],"w");
    if(!f) return;
    for(uint32_t i=0;i<sc.nsyms;i++){
        uint32_t strx=syms[i].n_un.n_strx;
        if(strx>=sc.strsize) continue;
        const char *nm=strtab+strx;
        if(!nm[0]) continue;
        for(int k=0;kw[k];k++){
            if(strstr(nm,kw[k])){
                fprintf(f,"%s 0x%llx\n",nm,(unsigned long long)(syms[i].n_value+slide));
                DGSymHits++;
                break;
            }
        }
    }
    fclose(f);
}

static void DGResolveOne(uint32_t idx, const char *name, void **slot){
    void *p=DGExportLookupU(idx,name);
    if(!p){
        const char *path=_dyld_get_image_name(idx);
        void *h=path?dlopen(path,RTLD_NOLOAD|RTLD_LAZY):NULL;
        if(h) p=dlsym(h,name);
    }
    if(!p) p=dlsym(RTLD_DEFAULT,name); /* حل أخير: النطاق العام */
    if(p) *slot=p;
}

/* الحل الرئيسي: شجرة التصدير أولاً ثم dlsym لأي نقص — مع بدائل يدوية لاحقاً */
static void DGResolveIL2CPP(void){
    if(DGIL2CPP.available) return;
    static NSTimeInterval lastTry=0;
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    if(lastTry>0 && now-lastTry<1.5) return; /* تخفيف الحمل: محاولة كل 1.5 ثانية */
    lastTry=now;
    memset(&DGIL2CPP,0,sizeof(DGIL2CPP));
    uint32_t count=_dyld_image_count();
    DGImagesScanned=count;
    for(uint32_t i=0;i<count;i++){
        void *probe=DGExportLookupU(i,"il2cpp_domain_get");
        if(!probe) continue;
        DGIL2CPP.domain_get=(DGDomainGetFn)probe;
        DGResolveOne(i,"il2cpp_domain_get_assemblies",(void**)&DGIL2CPP.domain_get_assemblies);
        DGResolveOne(i,"il2cpp_assembly_get_image",(void**)&DGIL2CPP.assembly_get_image);
        DGResolveOne(i,"il2cpp_class_from_name",(void**)&DGIL2CPP.class_from_name);
        DGResolveOne(i,"il2cpp_class_get_method_from_name",(void**)&DGIL2CPP.class_get_method_from_name);
        DGResolveOne(i,"il2cpp_runtime_invoke",(void**)&DGIL2CPP.runtime_invoke);
        DGResolveOne(i,"il2cpp_object_unbox",(void**)&DGIL2CPP.object_unbox);
        DGResolveOne(i,"il2cpp_string_chars",(void**)&DGIL2CPP.string_chars);
        DGResolveOne(i,"il2cpp_string_length",(void**)&DGIL2CPP.string_length);
        DGResolveOne(i,"il2cpp_image_get_name",(void**)&DGIL2CPP.image_get_name);
        DGResolveOne(i,"il2cpp_class_for_each",(void**)&DGIL2CPP.class_for_each);
        const char *nm=_dyld_get_image_name(i);
        snprintf(DGHitImage,sizeof(DGHitImage),"%s",nm?nm:"?");
        const char *base=strrchr(DGHitImage,'/');
        if(base) memmove(DGHitImage,base+1,strlen(base+1)+1);
        break;
    }
    /* الحد الأدنى — string/unbox لها بدائل يدوية */
    if(DGIL2CPP.domain_get && DGIL2CPP.domain_get_assemblies && DGIL2CPP.assembly_get_image &&
       DGIL2CPP.class_from_name && DGIL2CPP.class_get_method_from_name && DGIL2CPP.runtime_invoke){
        DGIL2CPP.available=YES;
        size_t n=0;
        DGIL2CPP.domain_get_assemblies(DGIL2CPP.domain_get(),&n);
        DGIL2CPP.assemblies=n;
        snprintf(DGIL2CPP.imageName,sizeof(DGIL2CPP.imageName),"%s",DGHitImage);
        snprintf(DGDiagShort,sizeof(DGDiagShort),"OK:%s",DGHitImage);
    } else {
        /* المرحلة أ: مسح المراسي المثبتة — دليل حضور زمن التشغيل */
        static const char *anchors[]={"il2cpp_class_get_name","il2cpp_method_get_name","il2cpp_object_get_size","il2cpp_thread_walk_frame_stack",NULL};
        static NSTimeInterval lastAnchor=0;
        if(now-lastAnchor>10.0 || lastAnchor==0){
            lastAnchor=now;
            DGIL2CPP.partialAPIs=0;
            for(int a=0;anchors[a];a++){
                for(uint32_t i=0;i<count;i++){
                    void *p=DGExportLookupU(i,anchors[a]);
                    if(p){
                        DGIL2CPP.partialAPIs++;
                        if(a==0){
                            DGIL2CPP.fn_class_get_name=p;
                            const char *hp=_dyld_get_image_name(i);
                            snprintf(DGAnchorHost,sizeof(DGAnchorHost),"%s",hp?hp:"?");
                        }
                        if(a==1) DGIL2CPP.fn_method_get_name=p;
                        if(a==2) DGIL2CPP.fn_object_get_size=p;
                        break;
                    }
                }
            }
            DGResolveProfilerFns(count);
        }
        /* المرحلة ب: الحل بالأوفسيتات من التحليل */
        DGTryOffsetResolver();
        if(!DGIL2CPP.available)
            snprintf(DGDiagShort,sizeof(DGDiagShort),"partial:%d/4|img:%u",DGIL2CPP.partialAPIs,count);
    }
}

/* ============================================================
   الحل بالأوفسيتات — للمحركات التي تُخفي واجهة il2cpp الكاملة
   (kgvmp/KiwiVM في Delta Force). القيم من IDA: File Offset
   داخل ثنائي DeltaForceClient. 0 = المعطّل.
   ============================================================ */
typedef struct {
    const char *imageName;              /* الصورة الحاملة لزمن il2cpp */
    uint64_t fileOffDomainGet;          /* il2cpp_domain_get */
    uint64_t fileOffRuntimeInvoke;      /* il2cpp_runtime_invoke */
    uint64_t fileOffClassFromName;      /* il2cpp_class_from_name */
    uint64_t fileOffClassGetMethodFromName; /* il2cpp_class_get_method_from_name */
    uint64_t fileOffObjectUnbox;        /* il2cpp_object_unbox */
    uint64_t fileOffStringChars;        /* il2cpp_string_chars */
    uint64_t fileOffStringLength;       /* il2cpp_string_length */
    uint64_t fileOffThreadAttach;       /* il2cpp_thread_attach (اختياري) */
    uint64_t fileOffDomainGetAssemblies; /* il2cpp_domain_get_assemblies (مطلوب) */
    uint64_t fileOffAssemblyGetImage;   /* il2cpp_assembly_get_image (مطلوب) */
} DGEngineOffsets;

/* ⚠️ املأ من تحليلك — كل قيمة 0 تعني "لا أعرف بعد" ولن تُستخدم */
static DGEngineOffsets DGOffsets={
    "DeltaForceClient",
    0,0,0,0,0,0,0,0, 0,0
};

static void* DGAddrFromFileOff(uint32_t idx, uint64_t fileoff){
    if(!fileoff) return NULL;
    const struct mach_header_64 *mh=(const struct mach_header_64*)_dyld_get_image_header(idx);
    if(!mh||mh->magic!=MH_MAGIC_64) return NULL;
    uint64_t slide=_dyld_get_image_vmaddr_slide(idx);
    const uint8_t *sg=(const uint8_t*)mh+sizeof(struct mach_header_64);
    for(uint32_t j=0;j<mh->ncmds;j++){
        const struct load_command *l2=(const struct load_command*)sg;
        if(l2->cmd==LC_SEGMENT_64){
            const struct segment_command_64 *seg=(const struct segment_command_64*)sg;
            if(fileoff>=seg->fileoff && fileoff<seg->fileoff+seg->filesize)
                return (void*)(uintptr_t)(seg->vmaddr+(fileoff-seg->fileoff)+slide);
        }
        sg+=l2->cmdsize;
    }
    return NULL;
}

static uint32_t DGFindImageIndex(const char *name){
    uint32_t c=_dyld_image_count();
    for(uint32_t i=0;i<c;i++){
        const char *p=_dyld_get_image_name(i);
        if(p && strstr(p,name)) return i;
    }
    return UINT32_MAX;
}

/* محاولة الحل بالأوفسيتات — تُعيد YES فقط إذا اجتاز التحقق الحقيقي */
static BOOL DGTryOffsetResolver(void){
    if(DGIL2CPP.available) return YES;
    if(!DGOffsets.fileOffDomainGet) return NO;
    uint32_t idx=DGFindImageIndex(DGOffsets.imageName);
    if(idx==UINT32_MAX) return NO;
    DGDomainGetFn dom=(DGDomainGetFn)DGAddrFromFileOff(idx,DGOffsets.fileOffDomainGet);
    if(!dom) return NO;
    /* تحقق حتمي: الاستدعاء يجب أن يرجع غير NULL — غير ذلك يعني أوفسيت خاطئ */
    void *domain=dom();
    if(!domain) return NO;
    DGIL2CPP.domain_get=dom;
    DGIL2CPP.runtime_invoke=(DGRuntimeInvokeFn)DGAddrFromFileOff(idx,DGOffsets.fileOffRuntimeInvoke);
    DGIL2CPP.class_from_name=(DGClassFromNameFn)DGAddrFromFileOff(idx,DGOffsets.fileOffClassFromName);
    DGIL2CPP.class_get_method_from_name=(DGClassGetMethodFn)DGAddrFromFileOff(idx,DGOffsets.fileOffClassGetMethodFromName);
    DGIL2CPP.object_unbox=(DGObjectUnboxFn)DGAddrFromFileOff(idx,DGOffsets.fileOffObjectUnbox);
    DGIL2CPP.string_chars=(DGStringCharsFn)DGAddrFromFileOff(idx,DGOffsets.fileOffStringChars);
    DGIL2CPP.string_length=(DGStringLengthFn)DGAddrFromFileOff(idx,DGOffsets.fileOffStringLength);
    DGIL2CPP.domain_get_assemblies=(DGDomainGetAssembliesFn)DGAddrFromFileOff(idx,DGOffsets.fileOffDomainGetAssemblies);
    DGIL2CPP.assembly_get_image=(DGAssemblyGetImageFn)DGAddrFromFileOff(idx,DGOffsets.fileOffAssemblyGetImage);
    /* الحد الأدنى الصارم — أي نقص يعني فشلًا صادقًا */
    if(!DGIL2CPP.domain_get_assemblies || !DGIL2CPP.assembly_get_image ||
       !DGIL2CPP.runtime_invoke || !DGIL2CPP.class_from_name || !DGIL2CPP.class_get_method_from_name){
        memset(&DGIL2CPP,0,sizeof(DGIL2CPP));
        snprintf(DGDiagShort,sizeof(DGDiagShort),"offsets-incomplete");
        return NO;
    }
    DGIL2CPP.available=YES;
    DGIL2CPP.resolvedViaOffsets=1;
    DGIL2CPP.assemblies=0;
    snprintf(DGIL2CPP.imageName,sizeof(DGIL2CPP.imageName),"%s+offsets",DGOffsets.imageName);
    snprintf(DGDiagShort,sizeof(DGDiagShort),"OK:offsets");
    return YES;
}

/* ============================================================
   المستكشف الحي — Profiler Bridge
   يستخدم الدوال المصدَّرة فقط (allocation profiler) لالتقاط
   الكائنات الحية وأسماء كلاساتها أثناء اللعب — بلا أوفسيتات.
   ============================================================ */
static void (*DGProfAlloc)(void*,void*)=NULL;        /* il2cpp_profiler_install_allocation(cb,ud) */
static void (*DGProfEnterLeave)(void*,void*)=NULL;   /* il2cpp_profiler_install_enter_leave(en,lv) */
static void (*DGProfSetEvents)(uint32_t)=NULL;       /* il2cpp_profiler_set_events(mask) */

#define DG_MAX_CLASSES 64
#define DG_MAX_CNAME 48
static struct { char name[DG_MAX_CNAME]; uint32_t allocs; void *lastObj; } DGSeen[DG_MAX_CLASSES];
static int DGSeenCount=0;
static char DGMatchNames[12][DG_MAX_CNAME];
static int DGMatchCount=0;
static volatile uint32_t DGAllocCount=0;
static volatile uint32_t DGEnterCount=0;
static BOOL DGProbeStarted=NO;
static BOOL DGProbeEverFired=NO;

static void DGAllocCb(void *obj, void *klass, size_t size, void *userData){
    (void)size; (void)userData;
    DGAllocCount++;
    if(!klass||!obj) return;
    DGProbeEverFired=YES;
    const char *(*getname)(void*)=(const char*(*)(void*))DGIL2CPP.fn_class_get_name;
    if(!getname) return;
    const char *nm=getname(klass);
    if(!nm) return;
    int idx=-1;
    for(int i=0;i<DGSeenCount;i++){ if(strncmp(DGSeen[i].name,nm,DG_MAX_CNAME-1)==0){ idx=i; break; } }
    if(idx<0 && DGSeenCount<DG_MAX_CLASSES){
        idx=DGSeenCount++;
        strncpy(DGSeen[idx].name,nm,DG_MAX_CNAME-1);
        DGSeen[idx].name[DG_MAX_CNAME-1]=0;
    }
    if(idx>=0){ DGSeen[idx].allocs++; DGSeen[idx].lastObj=obj; }
    if(DGMatchCount<12){
        char low[DG_MAX_CNAME];
        size_t L=strlen(nm); if(L>DG_MAX_CNAME-1) L=DG_MAX_CNAME-1;
        for(size_t i=0;i<L;i++) low[i]=(char)tolower((unsigned char)nm[i]); low[L]=0;
        if(strstr(low,"player")||strstr(low,"character")||strstr(low,"soldier")||
           strstr(low,"avatar")||strstr(low,"pawn")||strstr(low,"entity")||strstr(low,"hero")){
            BOOL fnd=NO;
            for(int i=0;i<DGMatchCount;i++) if(strncmp(DGMatchNames[i],nm,DG_MAX_CNAME-1)==0) fnd=YES;
            if(!fnd){ strncpy(DGMatchNames[DGMatchCount],nm,DG_MAX_CNAME-1); DGMatchNames[DGMatchCount][DG_MAX_CNAME-1]=0; DGMatchCount++; }
        }
    }
}
static void DGEnterCb(void *method, void *obj, void **args, void *userData){
    (void)method;(void)obj;(void)args;(void)userData; DGEnterCount++;
}
static void DGLeaveCb(void *method, void *obj, void *ret, void *userData){
    (void)method;(void)obj;(void)ret;(void)userData;
}

static void DGResolveProfilerFns(uint32_t count){
    if(DGProfAlloc&&DGProfEnterLeave&&DGProfSetEvents) return;
    for(uint32_t i=0;i<count;i++){
        if(!DGProfAlloc) DGProfAlloc=(void(*)(void*,void*))DGExportLookupU(i,"il2cpp_profiler_install_allocation");
        if(!DGProfEnterLeave) DGProfEnterLeave=(void(*)(void*,void*))DGExportLookupU(i,"il2cpp_profiler_install_enter_leave");
        if(!DGProfSetEvents) DGProfSetEvents=(void(*)(uint32_t))DGExportLookupU(i,"il2cpp_profiler_set_events");
    }
}

/* تشغيل المستكشف — ALLOCATIONS أولاً (الأخف)؛ ENTER_LEAVE يُضاف يدويًا لاحقًا */
static void DGStartProbe(void){
    if(DGProbeStarted) return;
    if(!DGIL2CPP.fn_class_get_name||!DGProfAlloc||!DGProfSetEvents) return;
    DGProfAlloc((void*)DGAllocCb,NULL);
    DGProfSetEvents(8u|128u|256u); /* CLASS | ALLOCATIONS | GC */
    DGProbeStarted=YES;
}



/* فحص FairPlay cryptid للصورة الرئيسية */
static int DGMainCryptid(void){
    const struct mach_header_64 *mh=(const struct mach_header_64*)_dyld_get_image_header(0);
    if(!mh||mh->magic!=MH_MAGIC_64) return -1;
    const uint8_t *cs=(const uint8_t*)mh+sizeof(struct mach_header_64);
    for(uint32_t j=0;j<mh->ncmds;j++){
        const struct load_command *l2=(const struct load_command*)cs;
        if(l2->cmd==LC_ENCRYPTION_INFO_64){
            const struct encryption_info_command_64 *e=(const struct encryption_info_command_64*)cs;
            return e->cryptid;
        }
        cs+=l2->cmdsize;
    }
    return -1;
}

/* ============================================================
   v0.7.0 — UE4 Runtime Scanner
   يمسح ذاكرة العملية الحية عبر vm_read (نسخ kernel) عن
   TUObjectArray متقد (NumElements>0) ويتحقق بسلسلة:
   chunk → FUObjectItem → UObject → vtable داخل __TEXT اللعبة
   ============================================================ */
static uint64_t DGGameTextLo=0, DGGameTextHi=0;
static uint64_t DGGameDataLo=0, DGGameDataHi=0;

static void DGInitGameRanges(void){
    if(DGGameTextLo) return;
    uint32_t ic=_dyld_image_count();
    for(uint32_t i=0;i<ic;i++){
        const char *p=_dyld_get_image_name(i);
        if(!p || !strstr(p,"DeltaForceClient.app/DeltaForceClient") || strstr(p,"Frameworks/")) continue;
        const struct mach_header_64 *mh=(const struct mach_header_64*)_dyld_get_image_header(i);
        if(!mh||mh->magic!=MH_MAGIC_64) continue;
        uint64_t slide=_dyld_get_image_vmaddr_slide(i);
        const uint8_t *cs=(const uint8_t*)mh+sizeof(struct mach_header_64);
        for(uint32_t k2=0;k2<mh->ncmds;k2++){
            const struct load_command *l2=(const struct load_command*)cs;
            if(l2->cmd==LC_SEGMENT_64){
                const struct segment_command_64 *seg=(const struct segment_command_64*)l2;
                uint64_t lo=seg->vmaddr+slide, hi=lo+seg->vmsize;
                if(strncmp(seg->segname,"__TEXT",16)==0){ DGGameTextLo=lo; DGGameTextHi=hi; }
                if(strncmp(seg->segname,"__DATA",16)==0){ if(!DGGameDataLo||lo<DGGameDataLo)DGGameDataLo=lo; if(hi>DGGameDataHi)DGGameDataHi=hi; }
            }
            cs+=l2->cmdsize;
        }
        break;
    }
}

static BOOL DGPtrMapped(uint64_t p){
    if(p<0x1000) return NO;
    vm_address_t a=(vm_address_t)(p&~0x3FFFULL);
    vm_size_t size=0; vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64; mach_port_t obj=MACH_PORT_NULL;
    kern_return_t kr=vm_region_64(mach_task_self(),&a,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&cnt,&obj);
    if(obj!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),obj);
    if(kr!=KERN_SUCCESS) return NO;
    return (p>=a && p<a+size);
}

static BOOL DGReadQ(uint64_t at, uint64_t *out){
    uint64_t got=0; uint8_t *b=DGSafeRead(at,8,&got);
    if(!b||got<8) return NO;
    memcpy(out,b,8); DGFreeRead(b,got);
    return YES;
}

static int DGVerifyUObjectChain(uint64_t objectsPtr, uint32_t numChunks){
    uint64_t got=0;
    uint32_t want=numChunks; if(want>512) want=512;
    uint8_t *table=DGSafeRead(objectsPtr,(uint64_t)want*8,&got);
    if(!table) return 0;
    int score=0; uint64_t checked=0;
    for(uint32_t c=0;c<want && checked<24;c++){
        uint64_t chunk; memcpy(&chunk,table+c*8,8);
        if(!DGPtrMapped(chunk)) continue;
        for(int k=0;k<2;k++){
            uint64_t item=chunk+(uint64_t)k*0x18;
            uint64_t obj=0; if(!DGReadQ(item,&obj)) continue;
            if(obj<0x100000000||obj%8) continue;
            uint64_t vtab=0; if(!DGReadQ(obj,&vtab)) continue;
            if(DGGameTextLo && vtab>=DGGameTextLo && vtab<DGGameTextHi) score++;
            checked++;
        }
    }
    DGFreeRead(table,got);
    return score;
}

static FILE *DGOpenUE4Log(void){
    NSString *docs=@"/var/mobile/Documents";
    [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[docs stringByAppendingPathComponent:@"deltaguard_ue4.txt"];
    return fopen([path UTF8String],"w");
}

static uint64_t *DGRegions=0; static uint32_t DGRegionCount=0;
static void DGCollectRegions(void){
    if(DGRegions) return;
    DGRegions=(uint64_t*)malloc(sizeof(uint64_t)*2*8192);
    vm_address_t addr=(vm_address_t)0x100000000ULL;
    while(DGRegionCount<8192){
        vm_size_t size=0; vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64; mach_port_t obj=MACH_PORT_NULL;
        if(vm_region_64(mach_task_self(),&addr,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&cnt,&obj)!=KERN_SUCCESS) break;
        if(obj!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),obj);
        if((info.protection&VM_PROT_READ)&&size>0){
            DGRegions[DGRegionCount*2]=(uint64_t)addr;
            DGRegions[DGRegionCount*2+1]=(uint64_t)addr+size;
            DGRegionCount++;
        }
        addr+=size;
        if(addr<0x100000000) break;
    }
}
static BOOL DGInRegions(uint64_t p){
    if(!DGRegionCount||p<0x1000) return NO;
    uint32_t lo=0,hi=DGRegionCount;
    while(lo<hi){ uint32_t mid=(lo+hi)>>1; if(p<DGRegions[mid*2]) hi=mid; else lo=mid+1; }
    if(lo==0) return NO;
    return p<DGRegions[(lo-1)*2+1];
}
static BOOL DGObjOk(uint64_t item,uint64_t *objOut){
    uint64_t o=0,v=0;
    if(!DGReadQ(item,&o)||!DGInRegions(o)||(o&7)) return NO;
    if(!DGReadQ(o,&v)) return NO;
    if(!(DGGameTextLo<=v&&v<DGGameTextHi)) return NO;
    if(objOut) *objOut=o;
    return YES;
}

static int DGScoreChunkStride(uint64_t chunk,uint32_t stride){
    uint64_t got=0;
    uint8_t *b=DGSafeRead(chunk,stride*16,&got);
    if(!b||got<stride){ if(b)DGFreeRead(b,got); return 0; }
    int n=(int)(got/stride); if(n>16) n=16;
    int score=0,ptrs=0;
    for(int i=0;i<n;i++){
        uint64_t o; memcpy(&o,b+i*stride,8);
        if(!o) continue;
        if((o&7)||!DGInRegions(o)) continue;
        ptrs++;
        uint64_t v=0;
        if(DGReadQ(o,&v)&&DGGameTextLo<=v&&v<DGGameTextHi) score++;
    }
    DGFreeRead(b,got);
    if(score>=3) return score;
    if(ptrs>=6) return -ptrs;
    return 0;
}
static int DGScoreChunk(uint64_t chunk,uint32_t *strideOut){
    int s18=DGScoreChunkStride(chunk,0x18);
    int s20=DGScoreChunkStride(chunk,0x20);
    if(s20>s18){ if(strideOut)*strideOut=0x20; return s20; }
    if(s18!=0){ if(strideOut)*strideOut=0x18; return s18; }
    if(s20!=0){ if(strideOut)*strideOut=0x20; return s20; }
    return 0;
}

static NSDictionary *DGScanCfg=nil;
static void DGLoadScanCfg(void){
    NSString *urlString=[NSString stringWithFormat:@"https://raw.githubusercontent.com/aosaid3224-ops/Zain-iOS-Tools/main/DeltaGuardIOS/Scripts/scan_config.json?ts=%llu",(unsigned long long)[[NSDate date] timeIntervalSince1970]];
    NSURL *u=[NSURL URLWithString:urlString];
    NSData *d=nil;
    @try{ d=[NSData dataWithContentsOfURL:u options:0 error:nil]; }@catch(NSException*){}
    if(!d){ @try{ d=[NSData dataWithContentsOfFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"scan_config_cache.json"] options:0 error:nil]; }@catch(NSException*){} }
    if(d){ @try{ id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if([j isKindOfClass:[NSDictionary class]]) DGScanCfg=j; }@catch(NSException*){} }
    if(!DGScanCfg) DGScanCfg=@{};
    @try{ [DGScanCfg writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"scan_config_cache.json"] atomically:YES]; }@catch(NSException*){}
}
static BOOL DGCfgBool(NSString *k,BOOL d){ id v=DGScanCfg[k]; return v?[v boolValue]:d; }
static uint8_t DGXorKeys[8]={0,14,0xD2,0,0,0,0,0};
static int DGXorKeyCount=3; /* مدمج: نصي + XOR 0x0E المؤكد */
static uint8_t DGDetectedXorKey=0;
static BOOL DGDetectedXorKeyValid=NO;
static void DGLoadXorKeys(void){
    DGXorKeys[0]=0; DGXorKeys[1]=14; DGXorKeyCount=2;
    id value=DGScanCfg[@"xorKeys"];
    if([value isKindOfClass:[NSArray class]]){
        NSArray *arr=(NSArray *)value;
        if(arr.count==0) return;
        int n=(int)MIN((NSUInteger)8,arr.count);
        for(int i=0;i<n;i++) DGXorKeys[i]=(uint8_t)[arr[i] intValue];
        DGXorKeyCount=n;
    }
}
/* تحقق None مع كل مفاتيح XOR */
static BOOL DGMatchNone(const uint8_t *p, uint8_t k){
    return (p[0]==('N'^k)&&p[1]==('o'^k)&&p[2]==('n'^k)&&p[3]==('e'^k)&&p[4]==(0^k));
}

static uint64_t DGNamePool=0;
#define DG_SNAP_BLOCKS 8
#define DG_SNAP_SIZE 0x10000
static uint8_t *DGBlockSnap[DG_SNAP_BLOCKS];
static uint32_t DGBlockNoneOff[DG_SNAP_BLOCKS];
static int DGBlockRegIndex[DG_SNAP_BLOCKS];
static int DGSnapCount=0;
static BOOL DGSnapFromRegistered=NO;
static BOOL DGDecodeFromSnap(uint32_t nameId,char *out,int outLen);
static BOOL DGDecodeAnyBlock(uint32_t nameId,char *out,int outLen);
static uint64_t DGBlocks[16];
static int DGBlockCount=0;
static void DGRegisterBlock(uint64_t entry, FILE *dbg){
    uint64_t page=entry&~0xFFFFULL;
    for(int i=0;i<DGBlockCount;i++) if(DGBlocks[i]==page) return;
    if(DGBlockCount>=16) return;
    /* تحقق أن الصفحة تحوي None (XOR-aware) قبل التسجيل */
    uint64_t g=0; uint8_t *b=DGSafeRead(page,0x10000,&g);
    if(!b||g!=DG_SNAP_SIZE){ if(b)DGFreeRead(b,g); return; }
    int ok=0;
    for(uint64_t i=0;i+8<g&&!ok;i+=2)
        for(int k=0;k<DGXorKeyCount;k++)
            if(DGMatchNone(b+i+2,DGXorKeys[k])){
                DGDetectedXorKey=DGXorKeys[k]; DGDetectedXorKeyValid=YES; ok=1; break;
            }
    if(!ok){ DGFreeRead(b,g); return; }
    /* لقطة ذرية فورية — البلوكات تتحرك خلال دقائق */
    int regIndex=DGBlockCount;
    BOOL snapInline=NO;
    if(regIndex<DG_SNAP_BLOCKS && DGSnapCount<DG_SNAP_BLOCKS){
        uint8_t *copy=(uint8_t*)malloc(DG_SNAP_SIZE);
        if(copy){
            memcpy(copy,b,DG_SNAP_SIZE);
            int snapIndex=DGSnapCount++;
            DGBlockSnap[snapIndex]=copy;
            DGBlockRegIndex[snapIndex]=regIndex;
            DGSnapFromRegistered=YES;
            snapInline=YES;
        }
    }
    DGFreeRead(b,g);
    DGBlocks[regIndex]=page;
    DGBlockCount++;
    if(dbg){ fprintf(dbg,"BLOCKREG %d @ 0x%llx %s\n",regIndex,(unsigned long long)page,snapInline?"SNAP-INLINE":"LIVE-ONLY"); fflush(dbg); }
}
static void DGDumpRegion2(uint64_t at, uint64_t bytes, const char *name, FILE *dbg);
/* ابحث في كل الذاكرة عن مؤشر لبلوك معروف — مع تحقق XOR أن Blocks[0] هو بداية بول حقيقية */
static void DGFindPoolPtr(uint64_t entry, FILE *dbg){
    if(DGNamePool) return; /* انحل — توقف */
    uint64_t loW=(entry>0x50000?entry-0x40000:0x1000)&~0xFFFULL;
    uint64_t hiW=entry+0x20000;
    int hits=0;
    for(uint32_t ri=0; ri<DGRegionCount && hits<8 && !DGNamePool; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x1000||sz>0x8000000ULL) continue; /* تخطَّ العملاقة — البول ليس فيها */
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue;
        uint64_t off=0;
        while(off+8<sz && hits<8 && !DGNamePool){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf) break;
            for(uint64_t q=0;q+8<=got && hits<8 && !DGNamePool;q+=8){
                uint64_t p; memcpy(&p,buf+q,8);
                if(p>=loW && p<hiW){
                    /* تحقق: p يجب أن يشير لبداية بلوك يحوي None بأي مفتاح */
                    uint64_t g2=0; uint8_t *blk=DGSafeRead(p,64,&g2);
                    int ok=0;
                    if(blk){
                        for(int k=0;k<DGXorKeyCount;k++)
                            if(g2>=8 && DGMatchNone(blk+2,DGXorKeys[k])) ok=DGXorKeys[k]+1;
                        DGFreeRead(blk,g2);
                    }
                    if(!ok) continue;
                    uint64_t gotv=0; uint8_t *bv=DGSafeRead(lo+off+q,24,&gotv);
                    if(bv){ uint32_t nbv,cbv,curv; memcpy(&nbv,bv+8,4); memcpy(&cbv,bv+12,4); memcpy(&curv,bv+16,4);
                        fprintf(dbg,"CAND @ 0x%llx nb=%u cb=%u cur=%u\n",(unsigned long long)(lo+off+q),nbv,cbv,curv);
                        DGFreeRead(bv,gotv); fflush(dbg); }
                    if(!DGVerifyPoolStruct(lo+off+q)) continue; /* صارم + مستقر */
                    hits++;
                    fprintf(dbg,"POOLPTR @ 0x%llx -> 0x%llx VERIFIED-STABLE ctx=", (unsigned long long)(lo+off+q),(unsigned long long)p);
                    uint64_t gc=0; uint8_t *cx=DGSafeRead(lo+off+q>64?lo+off+q-64:lo+off+q,64,&gc);
                    if(cx){ for(uint64_t kk=0;kk<gc;kk++) fprintf(dbg,"%02x",cx[kk]); DGFreeRead(cx,gc); }
                    fprintf(dbg,"\n");
                    if(hits==1){ DGNamePool=lo+off+q; fprintf(dbg,"NAMEPOOL STRUCT @ 0x%llx CONFIRMED-STABLE\n",(unsigned long long)DGNamePool); }
                    fflush(dbg);
                }
            }
            DGFreeRead(buf,got);
            if(!got) break;
            off+=got;
        }
    }
}


static int DGFindNameBlocksHeap(FILE *dbg){
    int blocks=0, regions=0, noneHits=0;
    for(uint32_t ri=0; ri<DGRegionCount && blocks<8 && !DGNamePool; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x8000 || sz>0x40000000ULL) continue;
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue; /* لا كود */
        regions++;
        uint64_t off=0;
        while(off+2100<sz && blocks<8 && !DGNamePool){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf) break;
            for(uint64_t q=2;q+2100<got && !DGNamePool;q++){
                if(buf[q-1]==0&&buf[q-2]<0x40&&(buf[q]==0x4E||buf[q]==0x40)&&((buf[q]=='N'&&buf[q+1]=='o'&&buf[q+2]=='n'&&buf[q+3]=='e'&&buf[q+4]==0)||(buf[q]==0x40&&buf[q+1]==0x61&&buf[q+2]==0x62&&buf[q+3]==0x65&&buf[q+4]==0x0E))){
                    noneHits++;
                    int density=0;
                    for(uint64_t i=q-2;i+8<got && i<q+2048;i+=2)
                        if(buf[i]<0x40&&buf[i+1]==0&&buf[i+2]>=0x20&&buf[i+2]<0x7f) density++;
                    uint64_t entry=lo+off+q-2;
                    int minD=DGCfgBool(@"densityFromConfig",YES)?[[DGScanCfg objectForKey:@"minDensity"] intValue]:45;
                    int weakD=[[DGScanCfg objectForKey:@"weakMin"] intValue];
                    if(weakD<=0) weakD=25;
                    if(minD<=0) minD=45;
                    if(density>=minD && blocks<8){
                        fprintf(dbg,"NAMEBLOCK @ 0x%llx density=%d\n",(unsigned long long)entry,density);
                        blocks++;
                        DGRegisterBlock(entry,dbg);
                    } else if(density>=weakD && noneHits<=600){
                        fprintf(dbg,"WEAKBLOCK @ 0x%llx density=%d\n",(unsigned long long)entry,density);
                        DGRegisterBlock(entry,dbg);
                    }
                }
            }
            DGFreeRead(buf,got);
            if(!got) break;
            off+=got;
        }
    }
    fprintf(dbg,"HEAPSCAN regions=%d noneHits=%d blocks=%d registered=%d\n",regions,noneHits,blocks,DGBlockCount);
    fflush(dbg);
    return blocks;
}


/* فك إدخال FName بالـ length المخزن في header؛ nextOff يسمح بمشي الإدخالات حتى لو تعذر فك الاسم. */
static BOOL DGDecodeNameEntry(uint64_t block,uint32_t off,char *out,int outLen,uint32_t *nextOff){
    if(out&&outLen>0) out[0]=0;
    uint64_t got=0; uint8_t *h=DGSafeRead(block+off,2,&got);
    if(!h||got<2){ if(h)DGFreeRead(h,got); return NO; }
    uint16_t hdr; memcpy(&hdr,h,2); DGFreeRead(h,got);
    uint32_t chars=(uint32_t)(hdr>>6);
    BOOL wide=(hdr&1)!=0;
    uint64_t charBytes=wide?2:1;
    uint64_t entryEnd=(uint64_t)off+2+(uint64_t)chars*charBytes+charBytes;
    uint64_t alignedEnd=(entryEnd+1)&~1ULL;
    if(nextOff) *nextOff=alignedEnd<=0x10000?(uint32_t)alignedEnd:0x10000;
    if(!chars||chars>0x400||alignedEnd>0x10000||wide||!out||outLen<=1||chars>=(uint32_t)outLen) return NO;
    uint8_t *raw=DGSafeRead(block+off+2,chars,&got);
    if(!raw||got<chars){ if(raw)DGFreeRead(raw,got); return NO; }
    uint8_t keys[9]; int keyCount=0;
    if(DGDetectedXorKeyValid) keys[keyCount++]=DGDetectedXorKey;
    for(int k=0;k<DGXorKeyCount;k++){
        uint8_t kk=DGXorKeys[k]; BOOL duplicate=NO;
        for(int j=0;j<keyCount;j++) if(keys[j]==kk) duplicate=YES;
        if(!duplicate&&keyCount<9) keys[keyCount++]=kk;
    }
    BOOL decoded=NO;
    for(int k=0;k<keyCount&&!decoded;k++){
        uint8_t kk=keys[k]; BOOL ok=YES;
        for(uint32_t i=0;i<chars;i++){
            uint8_t ch=raw[i]^kk;
            if(ch<32||ch>126){ ok=NO; break; }
            out[i]=(char)ch;
        }
        if(ok){ out[chars]=0; decoded=YES; }
    }
    if(!decoded) out[0]=0;
    DGFreeRead(raw,got);
    return decoded;
}

/* FNameEntryId: upper bits select block, low 16 bits are the byte offset within that block. */
static BOOL DGDecodeFName(uint32_t nameId, char *out, int outLen){
    if(out&&outLen>0) out[0]=0;
    if(!DGNamePool||!out||outLen<=1) return NO;
    uint32_t blockIdx=nameId>>16, off=nameId&0xFFFF;
    if(blockIdx>512) return NO;
    uint64_t block=0;
    if(!DGReadQ(DGNamePool+(uint64_t)blockIdx*8,&block)||!block||!DGInRegions(block)) return NO;
    return DGDecodeNameEntry(block,off,out,outLen,NULL);
}
static BOOL DGObjName(uint64_t obj, uint32_t nameOff, char *out, int outLen){
    out[0]=0;
    uint64_t got=0;
    uint8_t *b=DGSafeRead(obj+nameOff,4,&got);
    if(!b||got<4){ if(b)DGFreeRead(b,got); return NO; }
    uint32_t id; memcpy(&id,b,4); DGFreeRead(b,got);
    if(!id) return NO;
    if(DGSnapCount){
        if(DGSnapFromRegistered) return DGDecodeAnyBlock(id,out,outLen);
        return DGDecodeFromSnap(id,out,outLen);
    }
    return DGDecodeFName(id,out,outLen);
}

/* البحث عن FNamePool: تحقق None-أول بدون افتراض ترتيب الحقول */
static int DGBlockHasNone(uint64_t block){
    uint64_t got=0;
    uint8_t *e=DGSafeRead(block,160,&got);
    if(!e) return 0;
    int found=0;
    for(uint64_t i=0;i+8<got;i+=2){
        if(e[i+1]!=0||e[i]>=0x40) continue;
        for(int k=0;k<DGXorKeyCount;k++){
            if(DGMatchNone(e+i+2,DGXorKeys[k])){
                DGDetectedXorKey=DGXorKeys[k]; DGDetectedXorKeyValid=YES;
                found=DGXorKeys[k]+1; break;
            }
        }
        if(found) break;
    }
    DGFreeRead(e,got);
    return found;
}
static int DGFindNamePool(FILE *dbg){
    if(DGNamePool) return 1;
    int ptrCand=0, blockTested=0, hits=0;
    uint64_t cursor=DGGameDataLo;
    while(cursor<DGGameDataHi){
        uint64_t want=DGGameDataHi-cursor; if(want>33554432) want=33554432;
        uint64_t got=0;
        uint8_t *buf=DGSafeRead(cursor,want,&got);
        if(!buf){ cursor+=want; continue; }
        uint64_t lim=got-8;
        for(uint64_t q=0;q<lim;q+=8){
            uint64_t p; memcpy(&p,buf+q,8);
            if(!p||(p&7)||!DGInRegions(p)) continue;
            if(p>=DGGameDataLo&&p<DGGameDataHi) continue;
            ptrCand++;
            /* اقرأ أول 4 مؤشرات بلوك دفعة واحدة */
            uint64_t g2=0; uint8_t *ba=DGSafeRead(p,32,&g2);
            if(!ba) continue;
            int none=0;
            int nb=(int)(g2/8); if(nb>4) nb=4;
            for(int i=0;i<nb;i++){
                uint64_t blk; memcpy(&blk,ba+i*8,8);
                if(!blk||!DGInRegions(blk)) continue;
                blockTested++;
                if(DGBlockHasNone(blk)){ none=1; break; }
            }
            DGFreeRead(ba,g2);
            if(!none) continue;
            hits++;
            if(dbg) fprintf(dbg,"POOLCAND @ 0x%llx ctx64=",(unsigned long long)(cursor+q));
            uint64_t g3=0; uint8_t *cx=DGSafeRead(cursor+q>64?cursor+q-64:cursor+q,64,&g3);
            if(cx){ for(uint64_t k=0;k<g3;k++) fprintf(dbg,"%02x",cx[k]); DGFreeRead(cx,g3); }
            fprintf(dbg,"\n");
            fflush(dbg);
            if(hits>=6){ DGFreeRead(buf,got); if(dbg)fprintf(dbg,"POOL candidates>=6 (funnel ptr=%d blocks=%d)\n",ptrCand,blockTested); return 0; }
        }
        DGFreeRead(buf,got);
        cursor+=got?got:want;
        if(!got) cursor+=want;
    }
    if(dbg) fprintf(dbg,"POOL funnel: ptrCand=%d blockTested=%d hits=%d\n",ptrCand,blockTested,hits);
    return 0;
}

static uint64_t DGSlide=0;
static void DGProbeBss(FILE *dbg){
    NSArray *arr=DGScanCfg[@"probeBss"];
    if(![arr isKindOfClass:[NSArray class]]||!arr.count) return;
    if(!DGSlide) DGSlide=DGGameTextLo-0x100000000ULL;
    fprintf(dbg,"PROBE slide=0x%llx bss=%llu candidates\n",(unsigned long long)DGSlide,(unsigned long long)arr.count);
    for(NSString *s in arr){
        uint64_t file=strtoull([s UTF8String],0,16);
        uint64_t live=file+DGSlide;
        fprintf(dbg,"PROBE 0x%llx live=0x%llx ",(unsigned long long)file,(unsigned long long)live);
        uint64_t got=0; uint8_t *b=DGSafeRead(live,64,&got);
        if(!b||got<32){ fprintf(dbg,"UNREADABLE\n"); if(b)DGFreeRead(b,got); continue; }
        for(uint64_t k=0;k<got;k++) fprintf(dbg,"%02x",b[k]);
        fprintf(dbg," | ");
        uint64_t q0=0; memcpy(&q0,b,8);
        uint32_t v8,v12,v16,v20;
        memcpy(&v8,b+8,4); memcpy(&v12,b+12,4); memcpy(&v16,b+16,4); memcpy(&v20,b+20,4);
        if(q0&&!(q0&7)&&DGInRegions(q0)){
            if(DGGameTextLo<=q0&&q0<DGGameTextHi) fprintf(dbg,"VTAB-GLOBAL");
            else if(DGBlockHasNone(q0)) fprintf(dbg,"POOL-LIKE(Blocks[0] has None)");
            else fprintf(dbg,"PTR");
        } else if(v8<=0x1000&&v12<0x20000&&v8) fprintf(dbg,"INTS(NumBlocks=%u Cursor=%u)",v8,v16);
        else fprintf(dbg,"?");
        fprintf(dbg,"\n");
        DGFreeRead(b,got);
        fflush(dbg);
    }
}

/* مسبار الكثافة: كل مؤشر heap في __DATA ← تحقق كثافة 4KB (الحقيقي >250 إدخال) */
static int DGBlockDensity256(const uint8_t *b, uint64_t n){
    int d=0;
    for(uint64_t i=0;i+10<n;i+=2)
        if(b[i]<0x40&&b[i+1]==0&&b[i+2]>=0x20&&b[i+2]<0x7f&&b[i+3]>=0x20&&b[i+3]<0x7f) d++;
    return d;
}
static int DGFindPoolByDensity(FILE *dbg){
    int ptrCand=0, preHits=0, dense=0, confirmed=0;
    uint64_t cursor=DGGameDataLo;
    while(cursor<DGGameDataHi){
        uint64_t want=DGGameDataHi-cursor; if(want>33554432) want=33554432;
        uint64_t got=0;
        uint8_t *buf=DGSafeRead(cursor,want,&got);
        if(!buf){ cursor+=want; continue; }
        for(uint64_t q=0;q+8<=got;q+=8){
            uint64_t p; memcpy(&p,buf+q,8);
            if(!p||(p&7)||!DGInRegions(p)) continue;
            if(p>=DGGameDataLo&&p<DGGameDataHi) continue;
            ptrCand++;
            uint64_t g2=0; uint8_t *b256=DGSafeRead(p,256,&g2);
            if(!b256) continue;
            int d256=(g2>=64)?DGBlockDensity256(b256,g2):0;
            DGFreeRead(b256,g2);
            if(d256<24) continue;
            preHits++;
            uint64_t g4=0; uint8_t *b4k=DGSafeRead(p,4096,&g4);
            if(!b4k) continue;
            int d4k=DGBlockDensity256(b4k,g4);
            /* تحقق نهائي: entry 0 عند البداية يجب أن يفك إلى None */
            int none=0;
            for(int k=0;k<DGXorKeyCount;k++)
                if(g4>=8 && DGMatchNone(b4k+2,DGXorKeys[k])) none=DGXorKeys[k]+1;
            DGFreeRead(b4k,g4);
            if(d4k>200||none){
                dense++;
                if(none){ char dumpName[64]; snprintf(dumpName,sizeof(dumpName),"dense_%d_%llx.bin",DGUE4ScanCount,(unsigned long long)p); DGDumpRegion2(p,262144,dumpName,dbg); }
                fprintf(dbg,"DENSEBLOCK ptr=0x%llx block=0x%llx d256=%d d4k=%d noneKey=%d ctx=",
                    (unsigned long long)(cursor+q),(unsigned long long)p,d256,d4k,none?none-1:-1);
                uint64_t gc=0; uint8_t *cx=DGSafeRead(cursor+q>64?cursor+q-64:cursor+q,64,&gc);
                if(cx){ for(uint64_t kk=0;kk<gc;kk++) fprintf(dbg,"%02x",cx[kk]); DGFreeRead(cx,gc); }
                fprintf(dbg,"\n");
                fflush(dbg);
                if(none){ confirmed++; DGFreeRead(buf,got); return 1; }
            }
        }
        DGFreeRead(buf,got);
        cursor+=got?got:want;
        if(!got) cursor+=want;
    }
    fprintf(dbg,"DENSITY funnel: ptr=%d pre=%d dense=%d confirmed=%d\n",ptrCand,preHits,dense,confirmed);
    fflush(dbg);
    return confirmed>0;
}

/* البحث عن فهرس Pak المفكوك في الذاكرة الحية (.uasset كثيف) */
/* نسخة صحيحة بالـ fileHandle */
static void DGDumpRegion2(uint64_t at, uint64_t bytes, const char *name, FILE *dbg){
    uint64_t base=at>bytes/2 ? at-bytes/2 : at;
    base&=~0xFFFULL;
    uint64_t got=0;
    uint8_t *b=DGSafeRead(base,bytes,&got);
    if(!b){ if(dbg)fprintf(dbg,"DUMP %s FAILED\n",name); return; }
    NSString *baseName=[NSString stringWithUTF8String:name];
    NSString *uniqueStem=[NSString stringWithFormat:@"%@_%@",[baseName stringByDeletingPathExtension],[[NSUUID UUID] UUIDString]];
    NSString *uniqueName=[uniqueStem stringByAppendingPathExtension:[baseName pathExtension]];
    NSString *p=[NSTemporaryDirectory() stringByAppendingPathComponent:uniqueName];
    BOOL wrote=NO;
    @try{
        if([[NSFileManager defaultManager] createFileAtPath:p contents:nil attributes:nil]){
            NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:p];
            if(fh){ [fh writeData:[NSData dataWithBytesNoCopy:b length:(NSUInteger)got freeWhenDone:NO]]; [fh closeFile]; wrote=YES; }
        }
    }@catch(NSException *ex){ (void)ex; }
    DGFreeRead(b,got);
    if(dbg){
        if(wrote) fprintf(dbg,"DUMP %s file=%s @ 0x%llx size=%llu\n",name,[uniqueName UTF8String],(unsigned long long)base,(unsigned long long)got);
        else fprintf(dbg,"DUMP %s WRITE FAILED\n",name);
    }
    fflush(dbg);
}

static int DGFindPakIndex(FILE *dbg){
    int hits=0, regions=0;
    for(uint32_t ri=0; ri<DGRegionCount && hits<3; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x10000 || sz>0x40000000ULL) continue;
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue;
        regions++;
        uint64_t off=0;
        while(off+0x20000<sz && hits<3){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf) break;
            for(uint64_t q=0;q+16<got;q++){
                if(buf[q]=='.'&&buf[q+1]=='u'&&buf[q+2]=='a'&&buf[q+3]=='s'&&buf[q+4]=='s'&&buf[q+5]=='e'&&buf[q+6]=='t'){
                    hits++;
                    /* كثافة النافذة */
                    int d=0; char first[96]={0};
                    for(uint64_t i=q;i+8<got&&i<q+0x20000;i++){
                        if(buf[i]=='.'&&buf[i+1]=='u'&&(buf[i+2]=='a'||buf[i+2]=='u')) d++;
                    }
                    /* اجذب أول مسار كامل قبل .uasset */
                    uint64_t s=q; while(s>0&&buf[s-1]>32&&buf[s-1]<0x7f&&q-s<90) s--;
                    uint64_t prefix=q-s;
                    if(prefix>sizeof(first)-8) prefix=sizeof(first)-8;
                    memcpy(first,buf+s,prefix);
                    memcpy(first+prefix,".uasset",7);
                    first[prefix+7]=0;
                    fprintf(dbg,"PAKIDX @ 0x%llx density=%d first=%s\n",(unsigned long long)(lo+off+q),d,first);
                    char uname[64]; snprintf(uname,sizeof(uname),"pakidx_%d_%llx.bin",DGUE4ScanCount,(unsigned long long)(lo+off+q));
                    DGDumpRegion2(lo+off+q,262144,uname,dbg);
                    fflush(dbg);
                    break;
                }
            }
            DGFreeRead(buf,got);
            if(!got) break;
            off+=got;
        }
    }
    fprintf(dbg,"PAKIDX scan: regions=%d hits=%d\n",regions,hits);
    fflush(dbg);
    return hits;
}

static uint32_t DGPhase2RI=0;
static uint64_t DGPhase2OFF=0;
/* المرحلة 2: GUObjectArray — كل الذاكرة المقروءة مع استئناف */
static int DGFindGObjects(FILE *dbg){
    if(!DGNamePool&&!DGSnapCount) return 0;
    int cheap=0, nameHits=0;
    int cap=4000;
    id capObj=DGScanCfg[@"phase2Cap"];
    if([capObj isKindOfClass:[NSNumber class]]) cap=[capObj intValue];
    if(cap<500) cap=500;
    uint32_t ri=DGPhase2RI;
    uint64_t startOff=DGPhase2OFF;
    for(; ri<DGRegionCount && cheap<cap; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x1000||sz>0x40000000ULL) continue;
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue;
        uint64_t off=(ri==DGPhase2RI)?startOff:0;
        while(off+24<=sz && cheap<cap){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf){ off+=want; DGPhase2OFF=off; continue; }
            if(got<24){
                DGFreeRead(buf,got);
                off+=got?got:want;
                DGPhase2OFF=off;
                continue;
            }
            uint64_t lim=got-24;
            uint64_t q=0;
            for(;q<=lim && cheap<cap;q+=8){
                uint64_t table; memcpy(&table,buf+q,8);
                if(!table||(table&7)||!DGInRegions(table)) continue;
                uint64_t c0=0,c1=0;
                if(!DGReadQ(table,&c0)||!DGInRegions(c0)) continue;
                if(!DGReadQ(table+8,&c1)||!DGInRegions(c1)) continue;
                long long stride=(long long)(c1-c0);
                if(stride<0x8000||stride>0x800000) continue;
                cheap++;
                if(cheap%100==0){ fprintf(dbg,"PHASE2 progress: %d/%d (region %u)\n",cheap,cap,ri); fflush(dbg); }
                int n18=0,n20=0; char sample[64]=""; char sample2[64]="";
                for(int i=0;i<6;i++){
                    uint64_t item=c0+(uint64_t)i*0x18;
                    uint64_t obj=0;
                    if(!DGReadQ(item,&obj)||!obj||!DGInRegions(obj)) continue;
                    char nm[64];
                    if(DGObjName(obj,0x18,nm,sizeof nm)){ n18++; if(!sample[0]) strncpy(sample,nm,63); }
                    if(DGObjName(obj,0x20,nm,sizeof nm)){ n20++; if(!sample2[0]) strncpy(sample2,nm,63); }
                }
                int bestN=MAX(n18,n20);
                if(bestN>=1 && nameHits<30){
                    nameHits++;
                    fprintf(dbg,"OBJTABLE? @ 0x%llx stride=0x%llx names18=%d names20=%d sample=%s/%s\n",
                        (unsigned long long)table,(unsigned long long)stride,n18,n20,sample,sample2);
                    fflush(dbg);
                }
                if(bestN>=3){
                    fprintf(dbg,"VERIFIED GObjects @ 0x%llx (itemStride=%s, samples=%s|%s)\n",
                        (unsigned long long)table,n20>n18?"0x20":"0x18",sample,sample2);
                    snprintf(DGUE4Stat,sizeof(DGUE4Stat),"تم: GObjects @ 0x%llx — اكتمل الاكتشاف كاملًا",(unsigned long long)table);
                    snprintf(DGUE4FoundAddr,sizeof(DGUE4FoundAddr),"0x%llx",(unsigned long long)table);
                    DGUE4FoundFlag=YES;
                    dispatch_async(dispatch_get_main_queue(),^{ DGHaptic(); DGHaptic(); DGHaptic(); });
                    DGFreeRead(buf,got);
                    return 1;
                }
            }
            uint64_t advance=q;
            DGPhase2OFF=off+advance;
            DGFreeRead(buf,got);
            off+=advance;
        }
        if(cheap<cap){ DGPhase2RI=ri+1; DGPhase2OFF=0; }
        if(cheap>=cap) break;
    }
    if(cheap>=cap && !DGUE4FoundFlag){
        DGPhase2RI=ri;
        fprintf(dbg,"PHASE2 resume @ region %u off 0x%llx\n",ri,(unsigned long long)DGPhase2OFF);
    } else if(!DGUE4FoundFlag){
        DGPhase2RI=0; DGPhase2OFF=0;
        fprintf(dbg,"PHASE2 full cycle done — restarting\n");
    }
    fprintf(dbg,"GOBJ funnel: cheap=%d nameHits=%d\n",cheap,nameHits);
    fflush(dbg);
    return 0;
}

/* تحقق مزدوج: بنية + مقارنة زمنية للمرشح */
static BOOL DGBlockHasNoneP(uint64_t blocks){
    uint64_t g2=0; uint8_t *blk=DGSafeRead(blocks,128,&g2);
    if(!blk) return 0;
    int ok=0;
    for(uint64_t i=0;i+8<g2&&!ok;i+=2)
        for(int k=0;k<DGXorKeyCount;k++)
            if(DGMatchNone(blk+i+2,DGXorKeys[k])) ok=1;
    DGFreeRead(blk,g2);
    return ok;
}
static BOOL DGIsPlausibleName(const char *s){
    size_t n=s?strlen(s):0;
    if(n<2||n>63) return NO;
    BOOL letter=NO;
    for(size_t i=0;i<n;i++){
        unsigned char c=(unsigned char)s[i];
        BOOL alpha=(c>='A'&&c<='Z')||(c>='a'&&c<='z');
        BOOL digit=(c>='0'&&c<='9');
        if(alpha) letter=YES;
        if(!alpha&&!digit&&c!='_'&&c!='/'&&c!='.'&&c!='-'&&c!=':') return NO;
    }
    return letter;
}
static BOOL DGValidateRegisteredSnapshot(uint8_t *block,uint32_t *noneOff){
    for(uint32_t off=0;off+10<DG_SNAP_SIZE;off+=2){
        uint8_t key=0; BOOL matched=NO;
        for(int k=0;k<DGXorKeyCount;k++) if(DGMatchNone(block+off+2,DGXorKeys[k])){
            key=DGXorKeys[k]; matched=YES; break;
        }
        if(!matched) continue;
        char name[80]={0}; uint32_t next=off;
        if(!DGDecodeNameEntry((uint64_t)block,off,name,sizeof(name),&next)||strcmp(name,"None")!=0||next<=off) continue;
        int following=0; uint32_t pos=next;
        for(int e=0;e<8&&pos+2<DG_SNAP_SIZE&&following<2;e++){
            char candidate[80]={0}; uint32_t nextPos=pos;
            BOOL decoded=DGDecodeNameEntry((uint64_t)block,pos,candidate,sizeof(candidate),&nextPos);
            if(nextPos<=pos||nextPos>DG_SNAP_SIZE) break;
            if(decoded&&DGIsPlausibleName(candidate)) following++;
            pos=nextPos;
        }
        if(following>=2){
            DGDetectedXorKey=key; DGDetectedXorKeyValid=YES;
            if(noneOff) *noneOff=off;
            return YES;
        }
    }
    return NO;
}
/* انسخ البلوكات المسجلة فقط بعد تحقق المحتوى نفسه، لا من بنية struct مشتبه بها. */
static void DGSnapshotPool(FILE *dbg){
    /* لا نرجع إلى struct إذا وُجدت مرشحات مسجلة؛ نلتقط الصفحات الموثقة مباشرة. */
    if(DGBlockCount>0){
        uint8_t *copies[DG_SNAP_BLOCKS]={0};
        uint32_t noneOffsets[DG_SNAP_BLOCKS]={0};
        int regIndices[DG_SNAP_BLOCKS]={0};
        BOOL seen[16]={NO};
        int n=0,inlineCount=0,liveCount=0;
        /* لا نخلط snapshots قديمة من struct مع snapshots sourced from registered. */
        if(!DGSnapFromRegistered){
            for(int i=0;i<DGSnapCount;i++) if(DGBlockSnap[i]) free(DGBlockSnap[i]);
            memset(DGBlockSnap,0,sizeof(DGBlockSnap));
            memset(DGBlockNoneOff,0,sizeof(DGBlockNoneOff));
            memset(DGBlockRegIndex,0,sizeof(DGBlockRegIndex));
            DGSnapCount=0;
        }
        /* تحقق snapshots المأخوذة inline أولاً؛ لا تعِد قراءة عنوانها الحي. */
        for(int i=0;i<DGSnapCount&&i<DG_SNAP_BLOCKS&&n<DG_SNAP_BLOCKS;i++){
            uint8_t *copy=DGBlockSnap[i];
            int reg=DGBlockRegIndex[i];
            if(!copy) continue;
            if(reg<0||reg>=DGBlockCount||seen[reg]){ free(copy); continue; }
            uint32_t noneOff=0;
            BOOL vOK=DGValidateRegisteredSnapshot(copy,&noneOff);
            if(!vOK){
                /* لا رفض — التحقق من الالتقاط تم لحظيًا؛ الفك نفسه هو الحَكَم */
                for(uint32_t off=0;off+8<0x8000&&!noneOff;off+=2)
                    for(int k=0;k<DGXorKeyCount;k++) if(DGMatchNone(copy+off+2,DGXorKeys[k])){ noneOff=off; break; }
                if(dbg) fprintf(dbg,"SNAPSHOT soft-keep slot=%d reg#%d noneOff=0x%x\n",i,reg,noneOff);
            }
            copies[n]=copy; noneOffsets[n]=noneOff; regIndices[n]=reg; seen[reg]=YES;
            n++; inlineCount++;
        }
        /* Fallback حي فقط للصفحات التي لم تنجح لها لقطة inline، مع فحص كامل. */
        for(int reg=0;reg<DGBlockCount&&n<DG_SNAP_BLOCKS;reg++){
            if(seen[reg]) continue;
            uint64_t got=0; uint8_t *d=DGSafeRead(DGBlocks[reg],DG_SNAP_SIZE,&got);
            if(!d||got!=DG_SNAP_SIZE){ if(d)DGFreeRead(d,got); if(dbg) fprintf(dbg,"SNAPSHOT skip reg#%d (unreadable/short)\n",reg); continue; }
            uint8_t *copy=(uint8_t*)malloc(DG_SNAP_SIZE);
            if(!copy){ DGFreeRead(d,got); if(dbg) fprintf(dbg,"SNAPSHOT skip reg#%d (alloc failed)\n",reg); continue; }
            memcpy(copy,d,DG_SNAP_SIZE);
            DGFreeRead(d,got);
            uint32_t noneOff=0;
            if(!DGValidateRegisteredSnapshot(copy,&noneOff)){
                free(copy);
                if(dbg) fprintf(dbg,"SNAPSHOT skip reg#%d (None/entry validation failed)\n",reg);
                continue;
            }
            copies[n]=copy; noneOffsets[n]=noneOff; regIndices[n]=reg; seen[reg]=YES;
            n++; liveCount++;
        }
        memset(DGBlockSnap,0,sizeof(DGBlockSnap));
        memset(DGBlockNoneOff,0,sizeof(DGBlockNoneOff));
        memset(DGBlockRegIndex,0,sizeof(DGBlockRegIndex));
        for(int i=0;i<n;i++){
            DGBlockSnap[i]=copies[i];
            DGBlockNoneOff[i]=noneOffsets[i];
            DGBlockRegIndex[i]=regIndices[i];
        }
        DGSnapCount=n;
        DGSnapFromRegistered=(n>0);
        if(dbg){ fprintf(dbg,"SNAPSHOT %d blocks captured (inline-captured=%d live-fallback=%d; registered validated)\n",DGSnapCount,inlineCount,liveCount); fflush(dbg); }
        return;
    }
    if(DGSnapCount) return;
    if(!DGNamePool) return;
    for(int attempt=0;attempt<3&&!DGSnapCount;attempt++){
        uint64_t ptrs[DG_SNAP_BLOCKS]={0};
        uint8_t *copies[DG_SNAP_BLOCKS]={0};
        int count=0; BOOL ok=YES;
        for(int i=0;i<DG_SNAP_BLOCKS;i++){
            if(!DGReadQ(DGNamePool+(uint64_t)i*8,&ptrs[i])){ ok=NO; break; }
            if(!ptrs[i]) break;
            if(ptrs[i]<0x10000){ ok=NO; break; }
            count++;
        }
        if(!ok||count==0) goto snapshot_retry;
        for(int i=0;i<count;i++){
            uint64_t got=0; uint8_t *d=DGSafeRead(ptrs[i],DG_SNAP_SIZE,&got);
            if(!d||got!=DG_SNAP_SIZE){ if(d)DGFreeRead(d,got); ok=NO; break; }
            copies[i]=(uint8_t*)malloc(DG_SNAP_SIZE);
            if(!copies[i]){ DGFreeRead(d,got); ok=NO; break; }
            memcpy(copies[i],d,DG_SNAP_SIZE);
            DGFreeRead(d,got);
        }
        if(ok){
            for(int i=0;i<count;i++){
                uint64_t after=0;
                if(!DGReadQ(DGNamePool+(uint64_t)i*8,&after)||after!=ptrs[i]){ ok=NO; break; }
            }
            if(ok&&count<DG_SNAP_BLOCKS){
                uint64_t after=1;
                if(!DGReadQ(DGNamePool+(uint64_t)count*8,&after)||after!=0) ok=NO;
            }
        }
        if(ok){
            BOOL hasNone=NO;
            for(uint64_t i=0;i+8<0x1000&&!hasNone;i+=2)
                for(int k=0;k<DGXorKeyCount;k++)
                    if(DGMatchNone(copies[0]+i+2,DGXorKeys[k])){
                        DGDetectedXorKey=DGXorKeys[k]; DGDetectedXorKeyValid=YES; hasNone=YES; break;
                    }
            if(!hasNone) ok=NO;
        }
        if(ok){
            for(int i=0;i<count;i++) DGBlockSnap[i]=copies[i];
            DGSnapCount=count;
        } else {
            for(int i=0;i<DG_SNAP_BLOCKS;i++) if(copies[i]) free(copies[i]);
        }
snapshot_retry:
        if(!DGSnapCount&&attempt<2) usleep(10000);
    }
    if(dbg){
        if(DGSnapCount) fprintf(dbg,"SNAPSHOT %d blocks captured (pointers stable)\n",DGSnapCount);
        else fprintf(dbg,"SNAPSHOT failed (unstable/unreadable)\n");
        fflush(dbg);
    }
}
/* فك من اللقطة — مستقر حتى لو تحركت البلوكات الأصلية */
static BOOL DGDecodeFromSnap(uint32_t nameId, char *out, int outLen){
    if(out&&outLen>0) out[0]=0;
    if(!DGSnapCount||!out||outLen<=1) return NO;
    uint32_t bi=nameId>>16, off=nameId&0xFFFF;
    if(bi>=(uint32_t)DGSnapCount) return NO;
    return DGDecodeNameEntry((uint64_t)DGBlockSnap[bi],off,out,outLen,NULL);
}

/* فك عبر كل snapshot مسجل؛ لا نقبل أول تطابق عشوائي إذا اختلفت نتائج المرشحين. */
static BOOL DGDecodeAnyBlock(uint32_t nameId, char *out, int outLen){
    if(out&&outLen>0) out[0]=0;
    if(!out||outLen<=1||!DGSnapCount) return NO;
    /* حقائق Offsets.hpp: block=id>>18, off=(id&0x3FFFF)*2 — أول نتيجة معقولة تفوز (لا إجماع) */
    uint32_t bi=nameId>>18, uoff=(nameId&0x3FFFF)*2;
    if(uoff>0xFF00) return NO;
    int order[8]; int n=0;
    if(bi<(uint32_t)DGSnapCount) order[n++]=(int)bi;
    for(int b=0;b<DGSnapCount&&n<8;b++){ int f=0; for(int k=0;k<n;k++) if(order[k]==b){f=1;break;} if(!f) order[n++]=b; }
    for(int k=0;k<n;k++){
        const uint8_t *blk=(const uint8_t*)DGBlockSnap[order[k]];
        if(!blk) continue;
        uint16_t hdr; memcpy(&hdr,blk+uoff,2);
        uint32_t len=hdr>>6;
        if(len<2||len>=outLen||len>72) continue;
        uint32_t L=len;
        char t[80];
        BOOL ok=YES;
        for(int kk=0;kk<DGXorKeyCount&&ok;kk++){
            ok=YES;
            for(uint32_t i=0;i<L;i++){
                char c=(char)(blk[uoff+2+i]^DGXorKeys[kk]);
                t[i]=c;
                if(c<32||c>126) ok=NO;
            }
            t[L]=0;
            if(ok&&t[0]){ strncpy(out,t,outLen-1); out[outLen-1]=0; return YES; }
        }
    }
    return NO;
}

static BOOL DGVerifyPoolStruct(uint64_t A){
    uint64_t got=0; uint8_t *b1=DGSafeRead(A,32,&got);
    if(!b1||got<24){ if(b1)DGFreeRead(b1,got); return NO; }
    uint64_t blocks; uint32_t nb,cur;
    memcpy(&blocks,b1,8); memcpy(&nb,b1+8,4); memcpy(&cur,b1+16,4);
    uint64_t snapLen=got<32?got:32;
    uint8_t snap[32]; memcpy(snap,b1,snapLen);
    DGFreeRead(b1,got);
    if(!blocks||(blocks&7)) return NO;
    if(!DGBlockHasNoneP(blocks)) return NO;
    /* نعومة الحقول (لو البنية مختلفة لا نرفض — نكتفي بالمؤشر المستقر) */
    if(nb>4096) return NO;
    if(cur>0x40000) return NO;
    /* الاستقرار الزمني: أعد القراءة بعد 250ms وقارن */
    usleep(250000);
    uint64_t got2=0; uint8_t *b2=DGSafeRead(A,32,&got2);
    if(!b2||got2<24){ if(b2)DGFreeRead(b2,got2); return NO; }
    BOOL stable=(got2==snapLen&&memcmp(snap,b2,snapLen)==0);
    uint64_t blocks2; memcpy(&blocks2,b2,8);
    DGFreeRead(b2,got2);
    if(!stable) return NO;
    if(blocks2!=blocks) return NO;
    if(!DGBlockHasNoneP(blocks2)) return NO;
    return YES;
}

/* مُصطاد Blocks[]: مصفوفة مؤشرات تشير لبلوكات موثقة متعددة = GNamePool.Blocks */
static int DGFindBlocksArray(FILE *dbg){
    if(DGNamePool||DGBlockCount<2) return 0;
    int found=0;
    for(uint32_t ri=0; ri<DGRegionCount && !found; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x1000||sz>0x8000000ULL) continue;
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue;
        uint64_t off=0;
        while(off+8<sz && !found){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf) break;
            for(uint64_t q=0;q+16<=got && !found;q+=8){
                uint64_t p0,p1; memcpy(&p0,buf+q,8); memcpy(&p1,buf+q+8,8);
                if(!p0||!p1) continue;
                /* كلا المؤشرين يجب أن يطابقا بدايتي بلوكين موثقين مختلفين */
                int i0=-1,i1=-1;
                for(int k=0;k<DGBlockCount;k++){
                    uint64_t pg=DGBlocks[k]&~0xFFFFULL;
                    if(p0==pg) i0=k;
                    if(p1==pg) i1=k;
                }
                if(i0<0||i1<0||i0==i1) continue;
                /* أعد قراءة زوج المؤشرات بعد مهلة؛ اشترط 16 بايت في القراءتين */
                uint64_t g1=0; uint8_t *chk=DGSafeRead(lo+off+q,16,&g1);
                if(!chk||g1!=16){ if(chk) DGFreeRead(chk,g1); continue; }
                uint8_t s[16]; memcpy(s,chk,16); DGFreeRead(chk,g1);
                usleep(150000);
                uint64_t g2=0; uint8_t *chk2=DGSafeRead(lo+off+q,16,&g2);
                BOOL stb=chk2&&g2==16&&(memcmp(s,chk2,16)==0);
                if(chk2) DGFreeRead(chk2,g2);
                if(!stb) continue;
                fprintf(dbg,"BLOCKSARRAY @ 0x%llx -> [reg#%d]=0x%llx [reg#%d]=0x%llx CONFIRMED\n",
                    (unsigned long long)(lo+off+q),i0,(unsigned long long)p0,i1,(unsigned long long)p1);
                DGNamePool=lo+off+q;
                found=1;
            }
            DGFreeRead(buf,got);
            if(!got) break;
            off+=got;
        }
    }
    if(found) fprintf(dbg,"GNamePool = BlocksArray @ 0x%llx (طريقة المصفوفة)\n",(unsigned long long)DGNamePool);
    fflush(dbg);
    return found;
}

static uint64_t DGWatchBase=0;
static uint8_t DGWatchLast[32];
static BOOL DGWatchInit=NO;
/* منفذ probes من الإعدادات: قراءات خام فورية بدون بناء */
static void DGRunProbes(FILE *dbg){
    id arr=DGScanCfg[@"probes"];
    if(![arr isKindOfClass:[NSArray class]]) return;
    for(id p in arr){
        if(![p isKindOfClass:[NSDictionary class]]) continue;
        NSString *as=p[@"addr"];
        if(!as) continue;
        uint64_t a;
        if([as isEqualToString:@"bsslive"]){ a=DGWatchBase; if(!a){ fprintf(dbg,"PROBE bsslive: لا مرشح بعد\n"); continue; } }
        else a=strtoull([as UTF8String],0,16);
        int n=[[p objectForKey:@"n"] intValue]; if(n<=0||n>4096) n=128;
        if([p[@"rel"] boolValue]){ if(!DGGameTextLo) continue; a+=DGGameTextLo-0x100000000ULL; }
        if(a<0x1000) continue;
        int follow=[[p objectForKey:@"follow"] intValue];
        /* قراءة متتالية مع تتبع مؤشرات heap */
        uint64_t queue[16]; int qh=0,qt=0; queue[qt++]=(a<<8)|(uint64_t)(n<4096?n:4096);
        int seen=0;
        while(qh<qt&&seen<8){
            uint64_t pack=queue[qh++]; uint64_t ad=pack>>8; int nn=(int)(pack&0xFF);
            uint64_t got=0; uint8_t *b=DGSafeRead(ad,(uint64_t)nn,&got);
            fprintf(dbg,"PROBE 0x%llx n=%d : ",(unsigned long long)ad,nn);
            if(!b){ fprintf(dbg,"UNREADABLE\n"); continue; }
            for(uint64_t k=0;k<got;k++) fprintf(dbg,"%02x",b[k]);
            fprintf(dbg,"\n");
            if(follow>0){
                for(uint64_t k=0;k+8<=got&&qt<16;k+=8){
                    uint64_t v; memcpy(&v,b+k,8);
                    if(v>=0x100000000ULL&&!(v&7)&&v<0x140000000ULL){ queue[qt++]=(v<<8)|128; }
                }
            }
            DGFreeRead(b,got);
            seen++;
        }
    }
    fflush(dbg);
}

/* مرصد bss: بعد التهيئة، امسح bss كاملًا عن بنية GUObjectArray الحية */
static int DGWatchBss(FILE *dbg){
    uint64_t lo=0x117c6ca40, hi=0x1189952d0; /* __bss + __common كامل */
    if(DGGameTextLo){ lo+=DGGameTextLo-0x100000000ULL; hi+=DGGameTextLo-0x100000000ULL; }
    int found=0;
    uint64_t cursor=lo;
    while(cursor<hi && found<12){
        uint64_t want=hi-cursor; if(want>33554432) want=33554432;
        uint64_t got=0;
        uint8_t *buf=DGSafeRead(cursor,want,&got);
        if(!buf){ cursor+=want; continue; }
        uint64_t lim=got-32;
        for(uint64_t q=0;q<lim && found<12;q+=8){
            /* تخطيطا A(+0x10) و B(+0x0) — مع تجاهل قيمة objects (قد تكون XOR مشفرة) */
            uint64_t objects=0; memcpy(&objects,buf+q,8);
            int lay=0; uint32_t a=0,b=0,c=0,d=0;
            memcpy(&a,buf+q+16,4); memcpy(&b,buf+q+20,4);
            memcpy(&c,buf+q+24,4); memcpy(&d,buf+q+28,4);
            if(a>=0x40000&&a<=0x10000000&&b>=1000&&b<a&&c>=8&&c<=65536&&d>=1&&d<=c&&(a%c)==0) lay=1;
            if(!lay){ memcpy(&a,buf+q,4); memcpy(&b,buf+q+4,4); memcpy(&c,buf+q+8,4); memcpy(&d,buf+q+12,4);
                if(a>=0x40000&&a<=0x10000000&&b>=1000&&b<a&&c>=8&&c<=65536&&d>=1&&d<=c&&(a%c)==0) lay=2; }
            if(!lay) continue;
            if(!DGWatchBase) DGWatchBase=cursor+q;
            fprintf(dbg,"BSSLIVE @ 0x%llx objects=0x%llx Max=0x%x Num=%u Chunks=%u/%u raw=",(unsigned long long)(cursor+q),(unsigned long long)objects,a,b,d,c);
            for(int k=0;k<32;k++) fprintf(dbg,"%02x",buf[q+k]);
            fprintf(dbg,"\n");
            /* AUTOPROBE: اتبع حتى 4 مؤشرات heap من البنية */
            int followed=0;
            for(int k2=0;k2<32&&followed<4;k2+=8){
                uint64_t p; memcpy(&p,buf+q+k2,8);
                if(p<0x100000000ULL||(p&7)||p>=0x140000000ULL) continue;
                uint64_t g2=0; uint8_t *t2=DGSafeRead(p,128,&g2);
                if(!t2) continue;
                fprintf(dbg,"AUTOPROBE 0x%llx <= 0x%llx+%d : ",(unsigned long long)p,(unsigned long long)(cursor+q),k2);
                for(uint64_t x=0;x<g2;x++) fprintf(dbg,"%02x",t2[x]);
                fprintf(dbg,"\n");
                DGFreeRead(t2,g2);
                followed++;
            }
            found++;
        }
        DGFreeRead(buf,got);
        cursor+=got?got:want;
        if(!got) cursor+=want;
    }
    fprintf(dbg,"BSSWATCH done found=%d\n",found);
    fflush(dbg);
    return found;
}

/* كاسح الكائنات المباشر: vtable داخل __TEXT + ترجمة اسم من اللقطة = UObject حي */
static int DGObjectSweep(FILE *dbg){
    if(!DGSnapCount||!DGGameTextLo) return 0;
    uint64_t tLo=DGGameTextLo, tHi=DGGameTextHi;
    int hits=0, scanned=0;
    for(uint32_t ri=0; ri<DGRegionCount && hits<20; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x1000||sz>0x40000000ULL) continue;
        if(lo>=tLo&&lo<tHi) continue; /* لا كود */
        uint64_t off=0;
        while(off+0x18<sz && hits<20){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf) break;
            uint64_t lim=got-0x18;
            for(uint64_t q=0;q<lim && hits<20;q+=0x18*4){ /* عينة كل 4 خانات */
                uint64_t obj; memcpy(&obj,buf+q,8);
                if(obj<0x100000000ULL||(obj&7)||obj>=tLo) continue;
                uint64_t v=0;
                if(!DGReadQ(obj,&v)) continue;
                scanned++;
                if(v<tLo||v>=tHi) continue;
                /* UObject محتمل — ترجم اسمه من اللقطة */
                uint64_t got2=0; uint8_t *nb=DGSafeRead(obj+0x1c,4,&got2);
                if(!nb||got2<4) continue;
                uint32_t nid; memcpy(&nid,nb,4); DGFreeRead(nb,got2);
                char nm[64]="";
                if(nid && DGDecodeAnyBlock(nid,nm,sizeof nm)){
                    /* UObject مؤكد بالاسم! اقرأ كلاسه أيضًا */
                    uint64_t cls=0; char cn[64]="";
                    if(DGReadQ(obj+0x8,&cls)&&cls){
                        uint8_t *cb=DGSafeRead(cls+0x1c,4,&got2);
                        if(cb&&got2>=4){ uint32_t cid; memcpy(&cid,cb,4); DGFreeRead(cb,got2); DGDecodeAnyBlock(cid,cn,sizeof cn); }
                    }
                    fprintf(dbg,"OBJHIT @ 0x%llx name=%s class=%s vtab=0x%llx\\n",
                        (unsigned long long)obj,nm,cn,(unsigned long long)v);
                    hits++;
                }
            }
            DGFreeRead(buf,got);
            if(!got) break;
            off+=got;
        }
    }
    fprintf(dbg,"OBJSWEEP scanned=%d hits=%d\\n",scanned,hits);
    fflush(dbg);
    return hits;
}

/* مسار طوارئ: لقطة مباشرة من العناوين المسجلة — بلا validation، بلا رفض */
static int DGEmergencySnapshot(FILE *dbg){
    if(DGSnapCount) return DGSnapCount;
    int n=0;
    for(int i=0;i<DGBlockCount && n<DG_SNAP_BLOCKS;i++){
        uint64_t got=0; uint8_t *d=DGSafeRead(DGBlocks[i],0x8000,&got);
        if(!d||got<0x200){ if(d)DGFreeRead(d,got); continue; }
        if(DGBlockSnap[n]) free(DGBlockSnap[n]);
        DGBlockSnap[n]=(uint8_t*)malloc(got);
        memcpy(DGBlockSnap[n],d,got);
        DGFreeRead(d,got);
        n++;
    }
    DGSnapCount=n;
    if(dbg){ fprintf(dbg,"EMERGENCY-SNAP %d blocks (no-validation path)\n",n); fflush(dbg); }
    return n;
}

/* بصمة GUObjectArray على كل الذاكرة القابلة للكتابة (heap شامل) — TiMi قد تخصصه ديناميكيًا */
static int DGWatchAll(FILE *dbg){
    int found=0;
    for(uint32_t ri=0; ri<DGRegionCount && found<8; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x1000||sz>0x40000000ULL) continue;
        if(DGGameTextLo && lo>=DGGameTextLo && lo<DGGameTextHi) continue; /* لا كود */
        uint64_t off=0;
        while(off+32<sz && found<8){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf){ off+=want; continue; }
            uint64_t lim=got-32;
            for(uint64_t q=0;q<lim && found<8;q+=8){
                uint32_t a,b,c,d;
                memcpy(&a,buf+q+16,4); memcpy(&b,buf+q+20,4);
                memcpy(&c,buf+q+24,4); memcpy(&d,buf+q+28,4);
                if(!(a>=0x40000&&a<=0x10000000&&b>=1000&&b<a&&c>=8&&c<=65536&&d>=1&&d<=c&&(a%c)==0)) continue;
                uint32_t per=a/c; if(per<256||per>65536) continue;
                /* مؤشرات +0x0 و +0x8: واحد منها objects (ربما XOR مشفر) */
                uint64_t p0,p1; memcpy(&p0,buf+q,8); memcpy(&p1,buf+q+8,8);
                int p0m=(p0>=0x100000000ULL&&!(p0&7)&&p0<0x140000000ULL);
                int p1m=(p1>=0x100000000ULL&&!(p1&7)&&p1<0x140000000ULL);
                if(!p0m&&!p1m) continue;
                fprintf(dbg,"GLOBHIT @ 0x%llx Max=0x%x Num=%u Chunks=%u/%u p0=0x%llx p1=0x%llx raw=",(unsigned long long)(lo+off+q),a,b,d,c,(unsigned long long)p0,(unsigned long long)p1);
                for(int k=0;k<32;k++) fprintf(dbg,"%02x",buf[q+k]);
                fprintf(dbg,"\n");
                if(!DGWatchBase) DGWatchBase=lo+off+q;
                found++;
            }
            DGFreeRead(buf,got);
            off+=got?got:want;
            if(!got) off+=want;
        }
    }
    fprintf(dbg,"WATCHALL done found=%d\n",found);
    fflush(dbg);
    return found;
}

/* ===== وحدة الصيد المستقلّة v15: بلوكات + ترجمة + كائنات — ذرّية، بلا اعتماديات ===== */
#define DGH_BLK 12
static uint8_t *DGHBlk[DGH_BLK];
static uint32_t DGHBlkLen[DGH_BLK];
static int DGHN=0;
/* التقاط ذرّي أثناء المسح: أي بلوك فيه None^XOR يُحفظ فورًا */
static BOOL DGHGrab(const uint8_t *buf, uint64_t got, uint64_t absAt){
    if(DGHN>=DGH_BLK||got<0x400) return NO;
    for(uint64_t i=0;i+8<got;i+=2){
        for(int k=0;k<3;k++){
            uint8_t kk=(k==0)?0:(k==1?0x0E:0xD2);
            if(buf[i+2]==('N'^kk)&&buf[i+3]==('o'^kk)&&buf[i+4]==('n'^kk)&&buf[i+5]==('e'^kk)&&buf[i+6]==(0^kk)){
                for(int b=0;b<DGHN;b++) if(DGHBlk[b]==buf) return NO;
                DGHBlk[DGHN]=(uint8_t*)malloc(got);
                memcpy(DGHBlk[DGHN],buf,got);
                DGHBlkLen[DGHN]=(uint32_t)got;
                DGHN++;
                return YES;
            }
        }
    }
    return NO;
}
/* ترجمة id بالترميز الصحيح (>>18, ×2, len=hdr>>6, XOR×3) */
static BOOL DGHName(uint32_t id, char *out, int outLen){
    out[0]=0;
    if(!DGHN) return NO;
    uint32_t bi=id>>18, uoff=(id&0x3FFFF)*2;
    for(int b=0;b<DGHN;b++){
        if(uoff+74>DGHBlkLen[b]) continue;
        const uint8_t *blk=DGHBlk[b];
        uint16_t hdr; memcpy(&hdr,blk+uoff,2);
        uint32_t len=hdr>>6;
        if(len<2||len>=(uint32_t)outLen||len>72) continue;
        for(int k=0;k<3;k++){
            uint8_t kk=(k==0)?0:(k==1?0x0E:0xD2);
            char t[80]; BOOL ok=YES;
            for(uint32_t i=0;i<len;i++){ char c=(char)(blk[uoff+2+i]^kk); t[i]=c; if(c<32||c>126) ok=NO; }
            t[len]=0;
            if(ok&&t[0]){ strncpy(out,t,outLen-1); out[outLen-1]=0; return YES; }
        }
    }
    return NO;
}
/* كاسح الكائنات المستقل: vtab في __TEXT + اسم من DGHName */
static int DGHHunt(FILE *dbg){
    if(!DGHN||!DGGameTextLo) return 0;
    uint64_t tLo=DGGameTextLo, tHi=DGGameTextHi;
    int hits=0;
    for(uint32_t ri=0; ri<DGRegionCount && hits<15; ri++){
        uint64_t lo=DGRegions[ri*2], hi=DGRegions[ri*2+1];
        uint64_t sz=hi-lo;
        if(sz<0x8000||sz>0x40000000ULL) continue;
        if(lo>=tLo&&lo<tHi) continue;
        uint64_t off=0;
        while(off+8<sz && hits<15){
            uint64_t want=sz-off; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(lo+off,want,&got);
            if(!buf){ off+=want; continue; }
            DGHGrab(buf,got,lo+off);
            uint64_t lim=got-0x24;
            for(uint64_t q=0;q<lim && hits<15;q+=8){
                uint64_t obj; memcpy(&obj,buf+q,8);
                if(obj<0x100000000ULL||(obj&7)||obj>=tLo) continue;
                uint64_t v=0;
                if(!DGReadQ(obj,&v)||v<tLo||v>=tHi) continue;
                uint64_t g2=0; uint8_t *nb=DGSafeRead(obj+0x1c,4,&g2);
                if(!nb||g2<4){ if(nb)DGFreeRead(nb,g2); continue; }
                uint32_t nid; memcpy(&nid,nb,4); DGFreeRead(nb,g2);
                char nm[64]="";
                if(nid&&DGHName(nid,nm,sizeof nm)&&strlen(nm)>=3){
                    uint64_t cls=0; char cn[64]="";
                    if(DGReadQ(obj+0x8,&cls)&&cls){
                        uint8_t *cb=DGSafeRead(cls+0x1c,4,&g2);
                        if(cb&&g2>=4){ uint32_t cid; memcpy(&cid,cb,4); DGFreeRead(cb,g2); DGHName(cid,cn,sizeof cn); }
                    }
                    fprintf(dbg,"DGHIT @ 0x%llx name=%s class=%s\n",(unsigned long long)obj,nm,cn);
                    hits++;
                }
            }
            DGFreeRead(buf,got);
            off+=got?got:want;
            if(!got) off+=want;
        }
    }
    fprintf(dbg,"DGHUNT blocks=%d hits=%d\n",DGHN,hits);
    fflush(dbg);
    return hits;
}

/* ===== v16 FINAL: pattern-scan + ADRL + فك DeltaForce الحقيقي + مشي كائنات ===== */
static uint64_t DGTextLo=0, DGTextHi=0;
static uint64_t DGGUObj=0, DGGNamePool=0;

/* فك اسم DeltaForce الحقيقي (من iOS_UEDumper DeltaForce.hpp) */
static void DGDecName(char *str, uint32_t len){
    if(!str||!len) return;
    uint32_t key=0;
    switch(len%9){
        case 0: key=((len&0x1F)+len); break;
        case 1: key=((len^0xDF)+len); break;
        case 2: key=((len|0xCF)+len); break;
        case 3: key=(33*len); break;
        case 4: key=(len+(len>>2)); break;
        case 5: key=(3*len+5); break;
        case 6: key=(((4*len)|5)+len); break;
        case 7: key=(((len>>4)|7)+len); break;
        case 8: key=((len^0xC)+len); break;
        default: key=((len^0x40)+len); break;
    }
    for(uint32_t i=0;i<len;i++) str[i]=(char)((key&0x80)^~str[i]);
}

/* نمط بايتات مع ? wildcard → أول تطابق في __text */
static uint64_t DGPatScan(const char *pat, int len){
    if(!DGTextLo) return 0;
    /* أول بايت ثابت للـ memchr */
    uint8_t first=(uint8_t)pat[0];
    uint64_t sz=DGTextHi-DGTextLo;
    uint64_t off=0;
    while(off<sz){
        uint64_t want=sz-off; if(want>33554432) want=33554432;
        uint64_t got=0;
        uint8_t *buf=DGSafeRead(DGTextLo+off,want,&got);
        if(!buf){ off+=want; continue; }
        uint64_t lim=got>(uint64_t)len?got-len:0;
        for(uint64_t q=0;q<lim;q++){
            if(buf[q]!=first) continue;
            BOOL ok=YES;
            for(int k=1;k<len;k++){
                if(pat[k]!='?'&&buf[q+k]!=(uint8_t)pat[k]){ ok=NO; break; }
            }
            if(ok){ uint64_t r=DGTextLo+off+q; DGFreeRead(buf,got); return r; }
        }
        DGFreeRead(buf,got);
        off+=got?got:want;
        if(!got) off+=want;
    }
    return 0;
}

/* فك ADRL (ADRP+ADD) عند العنوان */
static uint64_t DGDecodeADRL(uint64_t ins){
    uint32_t w1=0; uint64_t g=0;
    uint8_t *b=DGSafeRead(ins,8,&g);
    if(!b||g<8){ if(b)DGFreeRead(b,g); return 0; }
    memcpy(&w1,b,4); uint32_t w2; memcpy(&w2,b+4,4); DGFreeRead(b,g);
    if((w1&0x9F000000)!=0x90000000) return 0;      /* ADRP */
    if((w2&0xFF000000)!=0x91000000) return 0;      /* ADD imm */
    uint64_t imm=(((w1>>5)&0x7FFFF)<<14)|(((w1>>29)&3)<<12);
    uint64_t pg=(ins&~0xFFFULL)+imm;
    uint64_t add=((w2>>10)&0xFFF) << (12*((w2>>22)&1));
    return pg+add;
}

/* نسخة م robust: مرساة قصيرة نادرة + ADRL + تحقق ذاتي بالقراءة الحية */
static void DGResolveOfficial(FILE *dbg){
    if(!DGTextLo){ if(DGGameTextLo){ DGTextLo=DGGameTextLo; DGTextHi=DGGameTextHi; } else return; }
    /* مرساة GUObjectArray: 94 E0 23 00 — نادرة في __text */
    if(!DGGUObj){
        const char *anchor="\x94\xE0\x23\x00";
        uint64_t pos=0, sz=DGTextHi-DGTextLo;
        int tried=0;
        while(pos<sz && !DGGUObj && tried<40){
            uint64_t want=sz-pos; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(DGTextLo+pos,want,&got);
            if(!buf){ pos+=want; continue; }
            for(uint64_t q=0;q+0x18<=got && !DGGUObj && tried<40;q++){
                if(buf[q]!=0x94||buf[q+1]!=0xE0||buf[q+2]!=0x23||buf[q+3]!=0x00) continue;
                tried++;
                uint64_t ins=DGTextLo+pos+q;
                uint64_t cand=DGDecodeADRL(ins+0x11);
                if(!cand) continue;
                /* تحقق ذاتي: TUObjectArray عند cand+0x10: Num@+4، Objects@+0x10 */
                uint64_t tobj=cand+0x10;
                uint64_t g2=0; uint8_t *vb=DGSafeRead(tobj+0x4,16,&g2);
                if(!vb||g2<16){ if(vb)DGFreeRead(vb,g2); continue; }
                uint32_t num=0,maxe=0,mc=0,nc=0;
                memcpy(&num,vb,4); memcpy(&maxe,vb+4,4); memcpy(&mc,vb+8,4); memcpy(&nc,vb+12,4);
                DGFreeRead(vb,g2);
                if(num>5000&&num<0x2000000&&maxe>=num&&maxe<=0x10000000&&mc>=8&&mc<=65536&&nc>=1&&nc<=mc){
                    DGGUObj=cand;
                    fprintf(dbg,"GUOBJ-ANCHOR @ 0x%llx → 0x%llx VERIFIED Num=%u Max=0x%x Chunks=%u/%u\n",
                        (unsigned long long)ins,(unsigned long long)cand,num,maxe,nc,mc);
                }
            }
            DGFreeRead(buf,got);
            pos+=got?got:want;
            if(!got) pos+=want;
        }
    }
    /* مرساة GNamePool: 4F D3 (نادرة نسبيًا) مع تحقق None */
    if(!DGGNamePool){
        const char *anchor2="\x4F\xD3";
        uint64_t pos=0, sz=DGTextHi-DGTextLo;
        int tried=0;
        while(pos<sz && !DGGNamePool && tried<200){
            uint64_t want=sz-pos; if(want>33554432) want=33554432;
            uint64_t got=0;
            uint8_t *buf=DGSafeRead(DGTextLo+pos,want,&got);
            if(!buf){ pos+=want; continue; }
            for(uint64_t q=0;q+0x20<=got && !DGGNamePool && tried<200;q++){
                if(buf[q]!=0x4F||buf[q+1]!=0xD3) continue;
                tried++;
                uint64_t ins=DGTextLo+pos+q;
                uint64_t cand=DGDecodeADRL(ins+6);
                if(!cand) continue;
                /* BlocksOff = cand-8 → Blocks[0] → block → None? */
                uint64_t blocks=0,block=0;
                if(!DGReadQ(cand-8,&blocks)||!blocks) continue;
                if(!DGReadQ(blocks,&block)||!block) continue;
                uint64_t g2=0; uint8_t *e=DGSafeRead(block,64,&g2);
                if(!e) continue;
                uint16_t hdr=0; if(g2>=2) memcpy(&hdr,e,2);
                uint32_t len=hdr>>6;
                if(len==4&&g2>=6){
                    char nm[8]={0}; memcpy(nm,e+2,4);
                    DGDecName(nm,4);
                    if(memcmp(nm,"None",4)==0){ DGGNamePool=cand;
                        fprintf(dbg,"NAMEPOOL-ANCHOR @ 0x%llx → 0x%llx VERIFIED None\n",(unsigned long long)ins,(unsigned long long)cand);
                    }
                }
                DGFreeRead(e,g2);
            }
            DGFreeRead(buf,got);
            pos+=got?got:want;
            if(!got) pos+=want;
        }
    }
    fflush(dbg);
}

/* قراءة اسم عبر GNamePool الرسمي: block=id>>18, off=(id&0x3FFFF)*2, len=hdr>>6, فك حقيقي */
static BOOL DGOfficialName(uint32_t id, char *out, int outLen){
    out[0]=0;
    if(!DGGNamePool||!id) return NO;
    uint32_t bi=id>>18, uoff=(id&0x3FFFF)*2;
    uint64_t blocks=0, block=0;
    /* BlocksOff = struct-8 (الملف الرسمي: BlocksOff -= sizeof(void*)) */
    if(!DGReadQ(DGGNamePool-8,&blocks)||!blocks) return NO;
    if(!DGReadQ(blocks+(uint64_t)bi*8,&block)||!block) return NO;
    uint64_t g=0; uint8_t *e=DGSafeRead(block+uoff,80,&g);
    if(!e||g<4){ if(e)DGFreeRead(e,g); return NO; }
    uint16_t hdr; memcpy(&hdr,e,2);
    uint32_t len=hdr>>6;
    if(len<2||len>=(uint32_t)outLen||len+2>g){ DGFreeRead(e,g); return NO; }
    memcpy(out,e+2,len);
    DGFreeRead(e,g);
    DGDecName(out,len);
    out[len]=0;
    for(uint32_t i=0;out[i];i++) if(out[i]<32||out[i]>126){ out[0]=0; return NO; }
    return YES;
}

/* مشي الكائنات: Objects@+0x10 → chunks → items(0x18) → obj → name@+0x1c */
static int DGWalkObjects(FILE *dbg){
    if(!DGGUObj) return 0;
    uint64_t base=DGGUObj; /* FUObjectArray */
    uint64_t objObjects=base+0x10; /* TUObjectArray (الملف الرسمي) */
    uint64_t objectsPtr=0;
    if(!DGReadQ(objObjects+0x10,&objectsPtr)||!objectsPtr){ /* Objects قد يكون بعد GC ptrs */
        if(!DGReadQ(objObjects+0x8,&objectsPtr)||!objectsPtr) return 0;
    }
    int printed=0;
    for(int c=0;c<4&&printed<40;c++){
        uint64_t chunk=0;
        if(!DGReadQ(objectsPtr+(uint64_t)c*8,&chunk)||!chunk) break;
        for(int i=0;i<64&&printed<40;i++){
            uint64_t item=chunk+(uint64_t)i*0x18;
            uint64_t obj=0;
            if(!DGReadQ(item,&obj)||!obj||obj<0x100000000ULL||(obj&7)) continue;
            uint64_t got=0; uint8_t *nb=DGSafeRead(obj+0x1c,4,&got);
            if(!nb||got<4){ if(nb)DGFreeRead(nb,got); continue; }
            uint32_t nid; memcpy(&nid,nb,4); DGFreeRead(nb,got);
            char nm[80]="";
            if(nid&&DGOfficialName(nid,nm,sizeof nm)&&strlen(nm)>=3){
                fprintf(dbg,"OBJWALK [%d/%d] %s @ 0x%llx\n",c,i,nm,(unsigned long long)obj);
                printed++;
            }
        }
    }
    fprintf(dbg,"OBJWALK done printed=%d\n",printed);
    fflush(dbg);
    return printed;
}


/* ===== v17: المسح الدلالي النهائي — بلا أنماط، تأكيد رياضي بالقراءة ===== */
static int DGSemaNumVerified=0, DGSemaNameVerified=0;
static uint32_t DGMaxSeen=0;

static BOOL DGSemaVerifyGUObj(uint64_t cand, FILE *dbg, uint64_t fromIns){
    uint64_t tobj=cand+0x10; /* TUObjectArray */
    uint64_t g=0; uint8_t *vb=DGSafeRead(tobj+0x4,16,&g);
    if(!vb||g<16){ if(vb)DGFreeRead(vb,g); return NO; }
    uint32_t num=0,maxe=0,mc=0,nc=0;
    memcpy(&num,vb,4); memcpy(&maxe,vb+4,4); memcpy(&mc,vb+8,4); memcpy(&nc,vb+12,4);
    DGFreeRead(vb,g);
    /* البصمة الصارمة الحقيقية: Max ملايين + قسمة متسقة + نسبة مشغولية معقولة */
    if(!(num>5000&&num<0x400000&&maxe>=0x100000&&maxe<=0x10000000)) return NO;
    if(num>=maxe/2) return NO;                          /* الاستخدام الحقيقي << السعة */
    if(mc<8||mc>65536||nc<1||nc>mc) return NO;
    if(maxe%mc) return NO;                              /* القسمة يجب أن تتسق تمامًا */
    uint32_t per=maxe/mc; if(per<0x1000||per>0x20000) return NO;
    /* Objects pointer يجب أن يكون غير صفري */
    uint64_t op=0;
    if(!DGReadQ(cand+0x20,&op)||!op) return NO;
    if(!DGGUObj || maxe>DGMaxSeen){ /* الأكبر سعة = الحقيقي */
        DGGUObj=cand; DGMaxSeen=maxe;
        fprintf(dbg,"GUOBJ-SEMA @ ins 0x%llx → 0x%llx VERIFIED Num=%u Max=0x%x Chunks=%u/%u per=0x%x\n",
            (unsigned long long)fromIns,(unsigned long long)cand,num,maxe,nc,mc,per);
    }
    return YES;
}
static BOOL DGSemaVerifyNamePool(uint64_t cand, FILE *dbg, uint64_t fromIns){
    uint64_t blocks=0,block=0;
    if(!DGReadQ(cand-8,&blocks)||!blocks) return NO;
    if(!DGReadQ(blocks,&block)||!block) return NO;
    uint64_t g=0; uint8_t *e=DGSafeRead(block,64,&g);
    if(!e) return NO;
    BOOL ok=NO;
    if(g>=6){ uint16_t hdr=0; memcpy(&hdr,e,2); uint32_t len=hdr>>6;
        if(len==4){ char nm[8]={0}; memcpy(nm,e+2,4);
            DGDecName(nm,4); if(memcmp(nm,"None",4)==0) ok=YES;          /* فك رسمي */
            if(!ok){ memcpy(nm,e+2,4); nm[4]=0; if(memcmp(nm,"None",4)==0) ok=YES; } /* صريح */
        } }
    DGFreeRead(e,g);
    if(!ok) return NO;
    DGGNamePool=cand;
    fprintf(dbg,"NAMEPOOL-SEMA @ ins 0x%llx → 0x%llx VERIFIED None\n",(unsigned long long)fromIns,(unsigned long long)cand);
    return YES;
}

/* امشِ على كل ADRP في __text — هدفه ضمن bss؟ → جرب ADD → تحقق دلالي */
static void DGSemanticScan(FILE *dbg){
    if(!DGTextLo){ if(DGGameTextLo){ DGTextLo=DGGameTextLo; DGTextHi=DGGameTextHi; } else return; }
    uint64_t bssLo=0x117c6ca40+(DGTextLo-0x100000000ULL);
    uint64_t bssHi=0x1189952d0+(DGTextLo-0x100000000ULL);
    uint64_t sz=DGTextHi-DGTextLo;
    uint64_t off=0;
    int verified=0, checked=0;
    while(off+16<sz && verified<4 && checked<200000){
        uint64_t want=sz-off; if(want>33554432) want=33554432;
        uint64_t got=0;
        uint8_t *buf=DGSafeRead(DGTextLo+off,want,&got);
        if(!buf){ off+=want; continue; }
        uint64_t lim=got-16;
        for(uint64_t q=0;q<lim && verified<4 && checked<200000;q+=4){
            uint32_t w; memcpy(&w,buf+q,4);
            if((w&0x9F000000)!=0x90000000) continue; /* ADRP فقط */
            uint32_t rd=w&31;
            uint64_t imm=(((uint64_t)(w>>5)&0x7FFFF)<<14)|(((uint64_t)(w>>29)&3)<<12);
            uint64_t pg=((DGTextLo+off+q)&~0xFFFULL)+imm;
            if(pg<bssLo||pg>=bssHi) continue;
            /* ADD rd,rd,#imm في التعليمات الثلاث التالية */
            for(int k=1;k<=3;k++){
                uint32_t w2; memcpy(&w2,buf+q+k*4,4);
                if((w2&0xFF000000)==0x91000000&&(w2&31)==rd&&((w2>>5)&31)==rd){
                    uint64_t addr=pg+(((w2>>10)&0xFFF)<<(12*((w2>>22)&1)));
                    if(addr<bssLo||addr>=bssHi) break;
                    checked++;
                    uint64_t oldGUObj=DGGUObj;
                    if(DGSemaVerifyGUObj(addr,dbg,DGTextLo+off+q)){ if(DGGUObj!=oldGUObj) verified++; break; }
                    if(!DGGNamePool&&DGSemaVerifyNamePool(addr,dbg,DGTextLo+off+q)){ verified++; break; }
                    break;
                }
            }
        }
        DGFreeRead(buf,got);
        off+=got?got:want;
        if(!got) off+=want;
    }
    fprintf(dbg,"SEMASCAN done checked=%d verified=%d GUObj=%d Pool=%d\n",checked,verified,DGGUObj!=0,DGGNamePool!=0);
    fflush(dbg);
}

/* ===== v19 FINAL SWEEP: أسماء + كلاسات لاعبين + اكتشاف مواقع — دفعة واحدة ===== */
static int DGTryPoolCandidate(uint64_t npTry, FILE *dbg, uint64_t candFile){
    uint64_t blocks=0,block=0;
    if(!(DGReadQ(npTry-8,&blocks)&&DGReadQ(blocks,&block))) return 0;
    uint64_t g3=0; uint8_t *e=DGSafeRead(block,32,&g3);
    if(!e||g3<6){ if(e)DGFreeRead(e,g3); return 0; }
    uint16_t hdr=0; memcpy(&hdr,e,2); uint32_t len=hdr>>6;
    int ok=0;
    if(len==4){ char nm[8]={0}; memcpy(nm,e+2,4); DGDecName(nm,4);
        if(!memcmp(nm,"None",4)) ok=1;
        else { memcpy(nm,e+2,4); nm[4]=0; if(!memcmp(nm,"None",4)) ok=1; } }
    DGFreeRead(e,g3);
    if(ok){ DGGNamePool=npTry;
        fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None ✓ (cand 0x%llx)\n",(unsigned long long)npTry,(unsigned long long)candFile); }
    return ok;
}

static void DGFinalSweep(FILE *dbg){
    fprintf(dbg,"===== FINAL SWEEP START =====\n"); fflush(dbg);
    /* ① البول */
    if(!DGGNamePool){
        uint64_t slide=DGTextLo-0x100000000ULL;
        static const uint64_t kC[]={0x118870040ULL,0x118871040ULL,0x118872040ULL,0x11886f040ULL};
        for(int i=0;i<4&&!DGGNamePool;i++) DGTryPoolCandidate(kC[i]+slide,dbg,kC[i]);
    }
    /* ②+③+④ المشي الشامل */
    uint64_t objObjects=DGGUObj+0x10;
    uint64_t objectsPtr=0;
    if(!DGReadQ(objObjects+0x10,&objectsPtr)||!objectsPtr){ if(!DGReadQ(objObjects+0x8,&objectsPtr)||!objectsPtr){ fprintf(dbg,"SWEEP: no objects ptr\n"); return; } }
    int names=0, players=0;
    for(int c=0;c<3&&names<200;c++){
        uint64_t chunk=0;
        if(!DGReadQ(objectsPtr+(uint64_t)c*8,&chunk)||!chunk) continue;
        for(int i=0;i<2000&&names<200;i++){
            uint64_t item=chunk+(uint64_t)i*0x18;
            uint64_t obj=0;
            if(!DGReadQ(item,&obj)||!obj||obj<0x100000000ULL||(obj&7)) continue;
            uint64_t g=0; uint8_t *nb=DGSafeRead(obj+0x1c,4,&g);
            if(!nb||g<4){ if(nb)DGFreeRead(nb,g); continue; }
            uint32_t nid; memcpy(&nid,nb,4); DGFreeRead(nb,g);
            char nm[96]="";
            if(!nid||!DGOfficialName(nid,nm,sizeof nm)||strlen(nm)<2) continue;
            names++;
            if(names<=200) fprintf(dbg,"NAME [%d] %s\n",names,nm);
            /* ③ كلاس لاعب؟ */
            char low[96]; size_t L=strlen(nm); if(L>95)L=95;
            for(size_t x=0;x<=L;x++) low[x]=(char)tolower((unsigned char)nm[x]);
            if(strstr(low,"player")||strstr(low,"character")||strstr(low,"pawn")||strstr(low,"soldier")||strstr(low,"hero")||strstr(low,"avatar")){
                players++;
                fprintf(dbg,"PLAYERCLASS #%d name=%s @ 0x%llx\n",players,nm,(unsigned long long)obj);
                /* ④ اكتشاف RootComponent تلقائيًا + ⑤ سحب مواقع */
                for(uint64_t K=0x140;K<=0x220&&players<=5;K+=8){
                    uint64_t rc=0;
                    if(!DGReadQ(obj+K,&rc)||!rc||rc<0x100000000ULL||(rc&7)) continue;
                    uint8_t *cb=DGSafeRead(rc+0x1c,4,&g);
                    if(!cb||g<4){ if(cb)DGFreeRead(cb,g); continue; }
                    uint32_t cid; memcpy(&cid,cb,4); DGFreeRead(cb,g);
                    char cn[80]="";
                    if(cid&&DGOfficialName(cid,cn,sizeof cn)&&(strstr(cn,"SceneComponent")||strstr(cn,"Component"))){
                        fprintf(dbg,"RC-OFFSET %s +0x%llx → %s\n",nm,(unsigned long long)K,cn);
                        uint8_t *pd=DGSafeRead(rc+0x180,96,&g); /* نافذة مواقع USceneComponent */
                        if(pd){ fprintf(dbg,"POSDATA %s @ 0x%llx : ",nm,(unsigned long long)(rc+0x180));
                            for(uint64_t x=0;x<g;x++) fprintf(dbg,"%02x",pd[x]);
                            fprintf(dbg,"\n"); DGFreeRead(pd,g); }
                        break;
                    }
                }
            }
        }
    }
    fprintf(dbg,"===== FINAL SWEEP END: names=%d players=%d pool=%d =====\n",names,players,DGGNamePool!=0);
    fflush(dbg);
}

static void DGUE4Scan(void){
    static NSTimeInterval lastTry=0;
    static BOOL found=NO;
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    if(now-lastTry<30.0) return;
    lastTry=now;
    DGUE4ScanCount++;
    DGInitGameRanges();
    DGCollectRegions();
    DGLoadScanCfg();
    DGLoadXorKeys();
    NSString *outp=[NSTemporaryDirectory() stringByAppendingPathComponent:@"deltaguard_ue4.txt"];
    NSFileManager *fm=[NSFileManager defaultManager];
    NSDictionary *attrs=[fm attributesOfItemAtPath:outp error:nil];
    if(attrs && [attrs fileSize]>8388608){
        [fm moveItemAtPath:outp toPath:[outp stringByAppendingString:@".1"] error:nil];
    }
    FILE *dbg=fopen([outp UTF8String],"a"); /* تراكمي */
    if(!dbg) return;
    if(DGNamePool){ fprintf(dbg,"POOL already solved @ 0x%llx\n",(unsigned long long)DGNamePool); fflush(dbg); }
    if(DGSnapCount){ fprintf(dbg,"REGISTERED SNAPSHOTS ready=%d\n",DGSnapCount); fflush(dbg); }
    { static NSTimeInterval lastSweep=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(DGSnapCount>=2 && up>120.0 && up-lastSweep>300.0){ lastSweep=up; fprintf(dbg,"--- OBJSWEEP (t+%ds) ---\n",(int)up); DGObjectSweep(dbg); } }
    /* العناوين الثابتة المستخرجة من ثنائي .37117 (تحليل ساكن كامل):
       GUObjectArray=0x118881ab8 | GNamePool=0x118870040 — قراءة مباشرة بلا مسح */
    if(!DGGUObj && DGGameTextLo){
        uint64_t slide=DGGameTextLo-0x100000000ULL;
        uint64_t guTry=0x118881ab8ULL+slide;
        uint64_t g2=0; uint8_t *vb=DGSafeRead(guTry+0x14,4,&g2);
        if(vb&&g2>=4){
            uint32_t num=0; memcpy(&num,vb,4); DGFreeRead(vb,g2);
            if(num>5000&&num<0x400000){ DGGUObj=guTry;
                fprintf(dbg,"GUOBJ-DIRECT @ 0x%llx Num=%u ✓ (static .37117)\n",(unsigned long long)guTry,num); }
        }
        if(!DGGNamePool){
            /* مرشحو GNamePool من التحليل الساكن — جربهم بالترتيب مع تحقق None */
            static const uint64_t kPoolCands[]={0x118870040ULL,0x118871040ULL,0x118872040ULL,0x11886f040ULL};
            for(int pi=0;pi<4&&!DGGNamePool;pi++){
            uint64_t npTry=kPoolCands[pi]+slide;
            uint64_t blocks=0,block=0;
            if(!(DGReadQ(npTry-8,&blocks)&&DGReadQ(blocks,&block))) continue;
                uint64_t g3=0; uint8_t *e=DGSafeRead(block,32,&g3);
                if(e&&g3>=6){ uint16_t hdr=0; memcpy(&hdr,e,2); uint32_t len=hdr>>6;
                    if(len==4){ char nm[8]={0}; memcpy(nm,e+2,4); DGDecName(nm,4);
                        if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                            fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None ✓ (static .37117)\n",(unsigned long long)npTry); }
                        else { memcpy(nm,e+2,4); nm[4]=0;
                            if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                                fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None(plain) ✓\n",(unsigned long long)npTry); } }
                    } }
                if(e)DGFreeRead(e,g3);
            } /* for pi */
        }
    }
    { static BOOL semaDone=NO; if(!semaDone && !DGGUObj){ semaDone=YES; fprintf(dbg,"--- SEMASCAN START (fallback) ---\n"); DGSemanticScan(dbg); } }
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    DGResolveOfficial(dbg);
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    { static NSTimeInterval lastHunt=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(up>60.0 && up-lastHunt>120.0){ lastHunt=up; fprintf(dbg,"--- DGHUNT (t+%ds) ---\n",(int)up); DGHHunt(dbg); } }
    { static BOOL bssWatched=NO; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(!bssWatched && up>100.0){ bssWatched=YES; fprintf(dbg,"--- BSS WATCH (t+%ds) ---\n",(int)up); DGWatchBss(dbg); fprintf(dbg,"--- WATCH ALL (heap-inclusive) ---\n"); DGWatchAll(dbg); }
      if(DGWatchBase){
          uint64_t g=0; uint8_t *b=DGSafeRead(DGWatchBase,32,&g);
          if(b&&g>=16){
              if(!DGWatchInit){ memcpy(DGWatchLast,b,32); DGWatchInit=YES; }
              else if(memcmp(DGWatchLast,b,g<32?g:32)!=0){
                  fprintf(dbg,"WATCHDIFF t+%lds @ 0x%llx : ",(long)up,(unsigned long long)DGWatchBase);
                  for(uint64_t k=0;k<g;k++) fprintf(dbg,"%02x",b[k]);
                  fprintf(dbg,"\n");
                  memcpy(DGWatchLast,b,g<32?g:32);
              }
              DGFreeRead(b,g);
          }
      } }
    { static NSTimeInterval lastSweep=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(DGSnapCount>=2 && up>120.0 && up-lastSweep>300.0){ lastSweep=up; fprintf(dbg,"--- OBJSWEEP (t+%ds) ---\n",(int)up); DGObjectSweep(dbg); } }
    /* العناوين الثابتة المستخرجة من ثنائي .37117 (تحليل ساكن كامل):
       GUObjectArray=0x118881ab8 | GNamePool=0x118870040 — قراءة مباشرة بلا مسح */
    if(!DGGUObj && DGGameTextLo){
        uint64_t slide=DGGameTextLo-0x100000000ULL;
        uint64_t guTry=0x118881ab8ULL+slide;
        uint64_t g2=0; uint8_t *vb=DGSafeRead(guTry+0x14,4,&g2);
        if(vb&&g2>=4){
            uint32_t num=0; memcpy(&num,vb,4); DGFreeRead(vb,g2);
            if(num>5000&&num<0x400000){ DGGUObj=guTry;
                fprintf(dbg,"GUOBJ-DIRECT @ 0x%llx Num=%u ✓ (static .37117)\n",(unsigned long long)guTry,num); }
        }
        if(!DGGNamePool){
            /* مرشحو GNamePool من التحليل الساكن — جربهم بالترتيب مع تحقق None */
            static const uint64_t kPoolCands[]={0x118870040ULL,0x118871040ULL,0x118872040ULL,0x11886f040ULL};
            for(int pi=0;pi<4&&!DGGNamePool;pi++){
            uint64_t npTry=kPoolCands[pi]+slide;
            uint64_t blocks=0,block=0;
            if(!(DGReadQ(npTry-8,&blocks)&&DGReadQ(blocks,&block))) continue;
                uint64_t g3=0; uint8_t *e=DGSafeRead(block,32,&g3);
                if(e&&g3>=6){ uint16_t hdr=0; memcpy(&hdr,e,2); uint32_t len=hdr>>6;
                    if(len==4){ char nm[8]={0}; memcpy(nm,e+2,4); DGDecName(nm,4);
                        if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                            fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None ✓ (static .37117)\n",(unsigned long long)npTry); }
                        else { memcpy(nm,e+2,4); nm[4]=0;
                            if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                                fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None(plain) ✓\n",(unsigned long long)npTry); } }
                    } }
                if(e)DGFreeRead(e,g3);
            }
        }
    { static BOOL semaDone=NO; if(!semaDone && !DGGUObj){ semaDone=YES; fprintf(dbg,"--- SEMASCAN START (fallback) ---\n"); DGSemanticScan(dbg); } }
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    DGResolveOfficial(dbg);
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    { static NSTimeInterval lastHunt=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(up>60.0 && up-lastHunt>120.0){ lastHunt=up; fprintf(dbg,"--- DGHUNT (t+%ds) ---\n",(int)up); DGHHunt(dbg); } }
    { static BOOL bssWatched=NO; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(!bssWatched && up>100.0){ bssWatched=YES; fprintf(dbg,"--- BSS WATCH (t+%ds) ---\n",(int)up); DGWatchBss(dbg); fprintf(dbg,"--- WATCH ALL (heap-inclusive) ---\n"); DGWatchAll(dbg); }
      if(DGWatchBase){
          uint64_t g=0; uint8_t *b=DGSafeRead(DGWatchBase,32,&g);
          if(b&&g>=16){
              if(!DGWatchInit){ memcpy(DGWatchLast,b,32); DGWatchInit=YES; }
              else if(memcmp(DGWatchLast,b,g<32?g:32)!=0){
                  fprintf(dbg,"WATCHDIFF t+%lds @ 0x%llx : ",(long)up,(unsigned long long)DGWatchBase);
                  for(uint64_t k=0;k<g;k++) fprintf(dbg,"%02x",b[k]);
                  fprintf(dbg,"\n");
                  memcpy(DGWatchLast,b,g<32?g:32);
              }
              DGFreeRead(b,g);
          }
      } }
    { static NSTimeInterval lastSweep=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(DGSnapCount>=2 && up>120.0 && up-lastSweep>300.0){ lastSweep=up; fprintf(dbg,"--- OBJSWEEP (t+%ds) ---\n",(int)up); DGObjectSweep(dbg); } }
    /* العناوين الثابتة المستخرجة من ثنائي .37117 (تحليل ساكن كامل):
       GUObjectArray=0x118881ab8 | GNamePool=0x118870040 — قراءة مباشرة بلا مسح */
    if(!DGGUObj && DGGameTextLo){
        uint64_t slide=DGGameTextLo-0x100000000ULL;
        uint64_t guTry=0x118881ab8ULL+slide;
        uint64_t g2=0; uint8_t *vb=DGSafeRead(guTry+0x14,4,&g2);
        if(vb&&g2>=4){
            uint32_t num=0; memcpy(&num,vb,4); DGFreeRead(vb,g2);
            if(num>5000&&num<0x400000){ DGGUObj=guTry;
                fprintf(dbg,"GUOBJ-DIRECT @ 0x%llx Num=%u ✓ (static .37117)\n",(unsigned long long)guTry,num); }
        }
        if(!DGGNamePool){
            /* مرشحو GNamePool من التحليل الساكن — جربهم بالترتيب مع تحقق None */
            static const uint64_t kPoolCands[]={0x118870040ULL,0x118871040ULL,0x118872040ULL,0x11886f040ULL};
            for(int pi=0;pi<4&&!DGGNamePool;pi++){
            uint64_t npTry=kPoolCands[pi]+slide;
            uint64_t blocks=0,block=0;
            if(!(DGReadQ(npTry-8,&blocks)&&DGReadQ(blocks,&block))) continue;
                uint64_t g3=0; uint8_t *e=DGSafeRead(block,32,&g3);
                if(e&&g3>=6){ uint16_t hdr=0; memcpy(&hdr,e,2); uint32_t len=hdr>>6;
                    if(len==4){ char nm[8]={0}; memcpy(nm,e+2,4); DGDecName(nm,4);
                        if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                            fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None ✓ (static .37117)\n",(unsigned long long)npTry); }
                        else { memcpy(nm,e+2,4); nm[4]=0;
                            if(!memcmp(nm,"None",4)){ DGGNamePool=npTry;
                                fprintf(dbg,"NAMEPOOL-DIRECT @ 0x%llx None(plain) ✓\n",(unsigned long long)npTry); } }
                    } }
                if(e)DGFreeRead(e,g3);
            }
        }
    }
    { static BOOL semaDone=NO; if(!semaDone && !DGGUObj){ semaDone=YES; fprintf(dbg,"--- SEMASCAN START (fallback) ---\n"); DGSemanticScan(dbg); } }
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    DGResolveOfficial(dbg);
    if(DGGUObj){ static BOOL swept=NO; if(!swept){ swept=YES; DGFinalSweep(dbg); } }
    { static NSTimeInterval lastHunt=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(up>60.0 && up-lastHunt>120.0){ lastHunt=up; fprintf(dbg,"--- DGHUNT (t+%ds) ---\n",(int)up); DGHHunt(dbg); } }
    { static BOOL bssWatched=NO; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      if(!bssWatched && up>100.0){ bssWatched=YES; fprintf(dbg,"--- BSS WATCH (t+%ds) ---\n",(int)up); DGWatchBss(dbg); fprintf(dbg,"--- WATCH ALL (heap-inclusive) ---\n"); DGWatchAll(dbg); }
      if(DGWatchBase){
          uint64_t g=0; uint8_t *b=DGSafeRead(DGWatchBase,32,&g);
          if(b&&g>=16){
              if(!DGWatchInit){ memcpy(DGWatchLast,b,32); DGWatchInit=YES; }
              else if(memcmp(DGWatchLast,b,g<32?g:32)!=0){
                  fprintf(dbg,"WATCHDIFF t+%lds @ 0x%llx : ",(long)up,(unsigned long long)DGWatchBase);
                  for(uint64_t k=0;k<g;k++) fprintf(dbg,"%02x",b[k]);
                  fprintf(dbg,"\n");
                  memcpy(DGWatchLast,b,g<32?g:32);
              }
              DGFreeRead(b,g);
          }
      } }
    { const char *bm=[DGScanCfg[@"buildMark"] UTF8String];
      fprintf(dbg,"BUILDMARK: %s\n",bm?bm:"(none)"); }
    { static uint32_t sLastRegions=0; NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
      fprintf(dbg,"\n=== ATTEMPT %d | t+%lds | regions=%u\n",DGUE4ScanCount,(long)up,DGRegionCount);
      if(sLastRegions && DGRegionCount>sLastRegions+8) fprintf(dbg,"STATE: +%u regions (تحول مشهد/تحميل)\n",DGRegionCount-sLastRegions);
      if(sLastRegions && DGRegionCount<sLastRegions-8) fprintf(dbg,"STATE: -%u regions (تفريغ/انتقال)\n",sLastRegions-DGRegionCount);
      sLastRegions=DGRegionCount; }
    fflush(dbg);
    DGRunProbes(dbg);
    if(found){ fprintf(dbg,"END pool=%s gobjects=FOUND (probe refresh)\n",(DGNamePool||DGSnapCount)?"YES":"NO"); fclose(dbg); return; }
    if(!DGGameTextLo){ fprintf(dbg,"FAIL ranges\n"); fclose(dbg); return; }
    DGProbeBss(dbg);
    if(DGCfgBool(@"heapBlockScan",YES)) DGFindNameBlocksHeap(dbg);
    if(!DGSnapCount && DGBlockCount>0) DGEmergencySnapshot(dbg); /* طوارئ: التقط فورًا قبل أي validation آخر */
    BOOL preferRegistered=(DGBlockCount>0);
    if(preferRegistered){
        DGSnapshotPool(dbg);
        if(!DGSnapCount) fprintf(dbg,"REGISTERED snapshots unavailable; struct path intentionally skipped\n");
    } else {
        if(!DGNamePool) DGFindBlocksArray(dbg);
        if(DGNamePool) DGSnapshotPool(dbg);
        DGFindPakIndex(dbg);
        if(DGCfgBool(@"densityScan",NO)) DGFindPoolByDensity(dbg);
        if(!DGNamePool) DGFindNamePool(dbg);
        if(DGNamePool&&!DGSnapCount) DGSnapshotPool(dbg);
    }
    if(DGNamePool&&!preferRegistered){
        /* تشخيص بنية البلوك: dump أول 96 بايت + موضع None الدقيق */
        uint64_t blk0=0;
        BOOL blk0IsSnapshot=(DGSnapCount>0&&DGBlockSnap[0]!=NULL);
        if(blk0IsSnapshot) blk0=(uint64_t)DGBlockSnap[0];
        /* dump struct البول نفسه أولًا */
        { uint64_t gs=0; uint8_t *sp=DGSafeRead(DGNamePool,64,&gs);
          if(sp){ fprintf(dbg,"POOLSTRUCT @ 0x%llx s64=",(unsigned long long)DGNamePool);
            for(uint64_t k=0;k<gs;k++) fprintf(dbg,"%02x",sp[k]);
            fprintf(dbg,"\n"); DGFreeRead(sp,gs); } }
        if((blk0IsSnapshot||(DGReadQ(DGNamePool,&blk0)&&blk0>0x1000))){
            uint64_t g=0; uint8_t *raw=DGSafeRead(blk0,96,&g);
            if(!raw) fprintf(dbg,"BLOCK0 UNREADABLE blk0=0x%llx\n",(unsigned long long)blk0);
            if(raw){
                fprintf(dbg,"BLOCK0 @ 0x%llx source=%s head96=",(unsigned long long)blk0,blk0IsSnapshot?"snapshot":"live");
                for(uint64_t k=0;k<g;k++) fprintf(dbg,"%02x",raw[k]);
                fprintf(dbg,"\n");
                uint8_t *xr=DGSafeRead(blk0,96,&g);
                if(xr){ for(uint64_t k=0;k<g;k++) xr[k]^=0x0E;
                    fprintf(dbg,"BLOCK0 xor0E= ");
                    for(uint64_t k=0;k<g;k++) fprintf(dbg,"%02x",xr[k]);
                    fprintf(dbg,"\n");
                    for(uint64_t k=0;k+8<g;k+=2){
                        if(memcmp(xr+k,"None",4)==0){ fprintf(dbg,"NONE xor0E @ +0x%llx\n",(unsigned long long)k); break; }
                        if(memcmp(raw+k,"None",4)==0){ fprintf(dbg,"NONE raw @ +0x%llx\n",(unsigned long long)k); break; }
                    }
                    DGFreeRead(xr,g);
                }
                DGFreeRead(raw,g);
            }
        }
        fflush(dbg);
        /* فحص ذاتي: فك أسماء معروفة من البول المؤكد */
        /* مشي الإدخالات على اللقطة الذرية */
        int good=0;
        uint64_t blk0w=0;
        if(DGSnapCount && (blk0w=(uint64_t)DGBlockSnap[0])){
            uint32_t off=0;
            for(int e=0;e<256 && off<0x4000 && good<16;e++){
                char name[80]={0}; uint32_t next=off;
                BOOL decoded=DGDecodeNameEntry(blk0w,off,name,sizeof(name),&next);
                if(next<=off||next>0x4000) break;
                if(decoded){
                    fprintf(dbg,"POOLSAMPLE off=0x%x name=%s\n",off,name);
                    good++;
                }
                off=next;
            }
        }
        fprintf(dbg,"POOLSAMPLE total=%d (walked)\n",good);
        /* STRSCAN: مسح السلاسل المثبت من تحليل الـ dumps (≥4 أحرف) */
        { int sg=0;
          for(int b2=0;b2<DGSnapCount && sg<30;b2++){
            const uint8_t *blk=DGBlockSnap[b2];
            for(uint64_t i2=0;i2+4<0x8000 && sg<30;i2++){
                for(int k=0;k<DGXorKeyCount;k++){
                    uint8_t kk=DGXorKeys[k];
                    if((blk[i2]^kk)<0x20||(blk[i2]^kk)>0x7e) continue;
                    uint64_t L=0;
                    while(i2+L<0x8000&&L<47&&(blk[i2+L]^kk)>=0x20&&(blk[i2+L]^kk)<0x7f) L++;
                    if(L>=4 && (i2+L>=0x8000 || (blk[i2+L]^kk)==0)){
                        char nm[48];
                        for(uint64_t c=0;c<L;c++) nm[c]=(char)(blk[i2+c]^kk);
                        nm[L]=0;
                        fprintf(dbg,"STRSCAN reg#%d len=%llu %s\n",b2,(unsigned long long)L,nm);
                        sg++; i2+=L;
                        break;
                    }
                }
            }
          }
          fprintf(dbg,"STRSCAN total=%d\n",sg);
        }
        fflush(dbg);
    }
    if(preferRegistered&&DGSnapCount){
        int good=0;
        for(int b=0;b<DGSnapCount&&good<16;b++){
            uint32_t off=DGBlockNoneOff[b];
            for(int e=0;e<256&&off<DG_SNAP_SIZE&&good<16;e++){
                char name[80]={0}; uint32_t next=off;
                BOOL decoded=DGDecodeNameEntry((uint64_t)DGBlockSnap[b],off,name,sizeof(name),&next);
                if(next<=off||next>DG_SNAP_SIZE) break;
                if(decoded){
                    fprintf(dbg,"POOLSAMPLE reg#%d off=0x%x name=%s\n",DGBlockRegIndex[b],off,name);
                    good++;
                }
                off=next;
            }
        }
        fprintf(dbg,"POOLSAMPLE total=%d (registered walk)\n",good);
        fflush(dbg);
    }
    if((DGNamePool||DGSnapCount) && !DGUE4FoundFlag){
        fprintf(dbg,"PHASE2: البحث عن GObjects بالتحقق من الأسماء...\n");
        fflush(dbg);
        if(DGFindGObjects(dbg)) found=YES;
    } else if(DGNamePool||DGSnapCount){
        fprintf(dbg,"PHASE1 OK pool=0x%llx (solved earlier)\n",(unsigned long long)DGNamePool);
    }
    fprintf(dbg,"END pool=%s gobjects=%s\n",(DGNamePool||DGSnapCount)?"YES":"NO",found?"FOUND":"PENDING");
    fclose(dbg);
}
}

/* بدائل يدوية إذا غابت الدوال عن التصدير */
static void* DGUnbox(void *obj){
    if(DGIL2CPP.object_unbox) return DGIL2CPP.object_unbox(obj);
    return obj?((char*)obj+0x10):NULL; /* بيانات القيمة بعد رأس Il2CppObject */
}
static int32_t DGStrLen(void *s){
    if(!s) return 0;
    if(DGIL2CPP.string_length) return DGIL2CPP.string_length(s);
    return *(volatile int32_t*)((char*)s+0x10);
}
static const uint16_t* DGStrChars(void *s){
    if(!s) return NULL;
    if(DGIL2CPP.string_chars) return DGIL2CPP.string_chars(s);
    return (const uint16_t*)((char*)s+0x14);
}

/* كتابة ملف تشخيص يحدد مكان رموز IL2CPP بدقة + تفريغ أسماء الرموز */
static void DGWriteDiag(void){
    static NSTimeInterval lastWrite=0;
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    if(lastWrite>0 && now-lastWrite<2.0) return; /* كل ثانيتين كحد أقصى */
    lastWrite=now;

    NSMutableString *m=[NSMutableString string];
    [m appendFormat:@"DeltaGuard IL2CPP diag | %@\n",[NSDate date]];
    [m appendFormat:@"available=%d | %s | hit=%s | images=%u\n",DGIL2CPP.available,DGDiagShort,DGHitImage,DGImagesScanned];
    [m appendFormat:@"cryptid=%d | anchorHost=%s\n",DGMainCryptid(),DGAnchorHost];
    [m appendFormat:@"metadata@0x%llx size=%llu | syms=%u hits=%u\n",(unsigned long long)DGMetaAddr,(unsigned long long)DGMetaSize,DGSymCount,DGSymHits];

    /* فحص صحة الماسك: مراسي متعددة معروفة الوجود */
    static const char *probes[]={"NSLog","malloc","objc_msgSend","il2cpp_class_get_name",NULL};
    uint32_t c0=_dyld_image_count();
    for(int q=0;probes[q];q++){
        uint32_t hitIdx=UINT32_MAX;
        for(uint32_t i=0;i<c0;i++){ if(DGExportLookupU(i,probes[q])){ hitIdx=i; break; } }
        [m appendFormat:@"probe %s -> %s\n",probes[q],hitIdx!=UINT32_MAX?"FOUND":"—"];
    }

    /* صور اللعبة/Unity وحالة il2cpp_domain_get في كل منها */
    uint32_t c=_dyld_image_count();
    for(uint32_t i=0;i<c;i++){
        const char *p=_dyld_get_image_name(i);
        if(!p) continue;
        if(!strstr(p,"elta") && !strstr(p,"Unity") && !strstr(p,"il2cpp") && !strstr(p,"GameAssembly") && !strstr(p,"ramework")) continue;
        void *s=DGExportLookup(i,"il2cpp_domain_get");
        [m appendFormat:@"%s -> %s\n",p,s?"IL2CPP_EXPORT ✅":"—"];
    }
    NSString *state=[m copy];
    if(DGLastDiag && [state isEqualToString:DGLastDiag]) return;
    DGLastDiag=state;
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"deltaguard_il2cpp_diag.txt"];
    [m writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    /* تفريغ أسماء كل الرموز المصدّرة لصور اللعبة/Unity — مرة واحدة لكل عملية */
    static BOOL dumped=NO;
    if(!dumped){
        dumped=YES;
        NSMutableString *out=[NSMutableString string];
        NSUInteger total=0;
        for(uint32_t i=0;i<c;i++){
            const char *p=_dyld_get_image_name(i);
            if(!p) continue;
            if(!strstr(p,"elta") && !strstr(p,"Unity") && !strstr(p,"GameAssembly") && !strstr(p,"il2cpp")) continue;
            [out appendFormat:@"=== %s ===\n",p];
            DGDumpImageExports(i,out,&total);
        }
        [out appendFormat:@"\nTOTAL: %lu\n",(unsigned long)total];
        NSString *epath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"deltaguard_exports.txt"];
        [out writeToFile:epath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    /* نتائج المستكشف الحي */
    [m appendFormat:@"PROBE: started=%d fired=%d alloc=%u enter=%u classes=%d matches=%d\n",
        DGProbeStarted,DGProbeEverFired,(unsigned)DGAllocCount,(unsigned)DGEnterCount,DGSeenCount,DGMatchCount];
    if(DGMatchCount>0){
        [m appendString:@"MATCHES: "];
        for(int i=0;i<DGMatchCount;i++) [m appendFormat:@"%s ",DGMatchNames[i]];
        [m appendString:@"\n"];
    }
    [m appendString:@"SEEN(first 40):\n"];
    for(int i=0;i<DGSeenCount && i<40;i++) [m appendFormat:@"  %s x%u\n",DGSeen[i].name,DGSeen[i].allocs];
}

/* البحث عن كلاس عبر كل الصور — يعيد أول مطابقة */
static void* DGFindClass(const char *nameSpace, const char *name){
    if(!DGIL2CPP.available || !DGIL2CPP.domain_get || !DGIL2CPP.domain_get_assemblies) return NULL;
    size_t n=0;
    void **assemblies=DGIL2CPP.domain_get_assemblies(DGIL2CPP.domain_get(),&n);
    if(!assemblies) return NULL;
    for(size_t i=0;i<n;i++){
        if(!assemblies[i]) continue;
        void *img=DGIL2CPP.assembly_get_image(assemblies[i]);
        if(!img) continue;
        void *klass=DGIL2CPP.class_from_name(img,nameSpace,name);
        if(klass) return klass;
    }
    return NULL;
}

static BOOL DGNameMatches(const char *name){
    if(!name) return NO;
    static const char *kw[]={"player","character","entity","soldier","pawn","actor","avatar","humanoid",NULL};
    char lower[128];
    size_t len=strlen(name);
    if(len>=sizeof(lower)) return NO;
    for(size_t i=0;i<=len;i++) lower[i]=(char)tolower((unsigned char)name[i]);
    for(int k=0;kw[k];k++){ if(strstr(lower,kw[k])) return YES; }
    return NO;
}

/* حالة مشتركة لرابط الزيارة — function pointer يتطلب دالة C حقيقية بدون التقاط متغيرات */
static const char *(*DGClassNameFn)(void*)=NULL;
static const char *(*DGClassNsFn)(void*)=NULL;
static int DGFoundCount=0;

static void DGClassVisitCB(void *klass, void *userData){
    (void)userData;
    if(!klass || DGFoundCount>=24 || !DGClassNameFn || !DGClassNsFn) return;
    const char *nm=DGClassNameFn(klass);
    if(nm && DGNameMatches(nm)){
        const char *ns=DGClassNsFn(klass);
        NSString *s=[NSString stringWithFormat:@"%s%s%s",ns&&strlen(ns)?ns:"",ns&&strlen(ns)?".":"",nm];
        [DGCandidateClasses addObject:s];
        DGFoundCount++;
    }
}

/* فلترة الكلاسات المرشحة — تُستدعى مرة واحدة فقط */
static void DGScanCandidateClasses(void){
    if(DGCandidatesScanned) return;
    DGResolveIL2CPP();
    if(!DGIL2CPP.available) return;
    if(!DGCandidateClasses) DGCandidateClasses=[NSMutableArray array];
    [DGCandidateClasses removeAllObjects];

    /* نحتاج il2cpp_class_get_name و il2cpp_class_get_namespace: نجلبهما عبر dlopen على نفس المكتبة */
    uint32_t count=_dyld_image_count();
    for(uint32_t i=0;i<count;i++){
        const char *path=_dyld_get_image_name(i);
        if(!path) continue;
        void *h=dlopen(path,RTLD_NOLOAD|RTLD_LAZY);
        if(!h) continue;
        if(dlsym(h,"il2cpp_domain_get")){
            DGClassNameFn=(const char*(*)(void*))dlsym(h,"il2cpp_class_get_name");
            DGClassNsFn=(const char*(*)(void*))dlsym(h,"il2cpp_class_get_namespace");
            break;
        }
    }
    if(!DGClassNameFn || !DGClassNsFn) return;

    if(DGIL2CPP.class_for_each){
        /* مسار سريع: زيارة كل الكلاسات عبر callback من نوع C */
        DGFoundCount=0;
        DGIL2CPP.class_for_each(DGClassVisitCB,NULL);
        DGClassesSeen=YES;
    } else {
        /* مسار بديل: بحث مباشر عن أسماء شائعة */
        static const struct { const char *ns; const char *name; } guesses[]={
            {"UnityEngine","Transform"},
            {"UnityEngine","Camera"},
            {"", "Player"},
            {"", "PlayerController"},
            {"", "LocalPlayer"},
            {"", "Character"},
            {"", "GamePlayer"},
            {"", "BasePlayer"},
            {"", "Soldier"},
            {"", "Avatar"},
            {NULL,NULL}
        };
        int found=0;
        for(int i=0;guesses[i].name && found<24;i++){
            void *k=DGFindClass(guesses[i].ns,guesses[i].name);
            if(k){
                const char *nm=DGClassNameFn(k);
                const char *ns=DGClassNsFn(k);
                NSString *s=[NSString stringWithFormat:@"%s%s%s",ns&&strlen(ns)?ns:"",ns&&strlen(ns)?".":"",nm?nm:guesses[i].name];
                [DGCandidateClasses addObject:s];
                found++;
            }
        }
        DGClassesSeen=YES;
    }
    DGCandidatesScanned=YES;
}

/* قراءة اسم المشهد النشط — يعمل بعد تحميل Unity بالكامل */
static NSString* DGGetSceneName(void){
    DGResolveIL2CPP();
    if(!DGIL2CPP.available) return nil;
    static void *smClass=NULL; static void *getActive=NULL; static void *sceneClass=NULL; static void *getName=NULL;
    /* إعادة الحل في كل مرة: إذا نقص أي تابع نصفر الكل لإعادة المحاولة لاحقاً */
    smClass=DGFindClass("UnityEngine.SceneManagement","SceneManager");
    getActive=smClass?DGIL2CPP.class_get_method_from_name(smClass,"GetActiveScene",0):NULL;
    sceneClass=DGFindClass("UnityEngine.SceneManagement","Scene");
    getName=sceneClass?DGIL2CPP.class_get_method_from_name(sceneClass,"get_name",0):NULL;
    if(!smClass||!getActive||!sceneClass||!getName) return nil;
    void *exc=NULL;
    void *boxed=DGIL2CPP.runtime_invoke(getActive,NULL,NULL,&exc);
    if(!boxed||exc) return nil;
    void *sceneData=DGUnbox(boxed);
    if(!sceneData) return nil;
    void *nameObj=DGIL2CPP.runtime_invoke(getName,sceneData,NULL,&exc);
    if(!nameObj||exc) return nil;
    int32_t len=DGStrLen(nameObj);
    const uint16_t *chars=DGStrChars(nameObj);
    if(!chars||len<=0) return @"";
    return [[NSString alloc] initWithCharacters:(const unichar*)chars length:len];
}

/* قراءة قاعدة الكاميرا الكاملة: الموضع + الاتجاهات + زاوية الرؤية */
static BOOL DGGetCameraBasis(void){
    DGResolveIL2CPP();
    if(!DGIL2CPP.available) return NO;
    static void *camClass=NULL,*getMain=NULL,*getTransform=NULL,*getPosition=NULL,*getForward=NULL,*getRight=NULL,*getFov=NULL;
    static void *transformClass=NULL,*getUp=NULL;
    camClass=DGFindClass("UnityEngine","Camera");
    getMain=camClass?DGIL2CPP.class_get_method_from_name(camClass,"get_main",0):NULL;
    getTransform=camClass?DGIL2CPP.class_get_method_from_name(camClass,"get_transform",0):NULL;
    getForward=camClass?DGIL2CPP.class_get_method_from_name(camClass,"get_forward",0):NULL;
    getRight=camClass?DGIL2CPP.class_get_method_from_name(camClass,"get_right",0):NULL;
    getFov=camClass?DGIL2CPP.class_get_method_from_name(camClass,"get_fieldOfView",0):NULL;
    transformClass=DGFindClass("UnityEngine","Transform");
    getPosition=transformClass?DGIL2CPP.class_get_method_from_name(transformClass,"get_position",0):NULL;
    getUp=transformClass?DGIL2CPP.class_get_method_from_name(transformClass,"get_up",0):NULL;
    if(!camClass||!getMain||!getTransform||!transformClass||!getPosition||!getForward||!getRight||!getUp||!getFov){
        DGHavCamBasis=NO;
        return NO;
    }
    void *exc=NULL;
    void *cam=DGIL2CPP.runtime_invoke(getMain,NULL,NULL,&exc);
    if(!cam||exc){ DGHavCamBasis=NO; return NO; }
    void *tr=DGIL2CPP.runtime_invoke(getTransform,cam,NULL,&exc);
    if(!tr||exc){ DGHavCamBasis=NO; return NO; }
    float *v=NULL;
    void *boxed=DGIL2CPP.runtime_invoke(getPosition,tr,NULL,&exc);
    if(!boxed||exc){ DGHavCamBasis=NO; return NO; }
    v=(float*)DGUnbox(boxed);
    if(!v){ DGHavCamBasis=NO; return NO; }
    memcpy(DGCamPos,v,sizeof(float)*3);
    boxed=DGIL2CPP.runtime_invoke(getForward,tr,NULL,&exc);
    if(!boxed||exc){ DGHavCamBasis=NO; return NO; }
    v=(float*)DGUnbox(boxed);
    if(!v){ DGHavCamBasis=NO; return NO; }
    memcpy(DGCamFwd,v,sizeof(float)*3);
    boxed=DGIL2CPP.runtime_invoke(getRight,tr,NULL,&exc);
    if(!boxed||exc){ DGHavCamBasis=NO; return NO; }
    v=(float*)DGUnbox(boxed);
    if(!v){ DGHavCamBasis=NO; return NO; }
    memcpy(DGCamRight,v,sizeof(float)*3);
    boxed=DGIL2CPP.runtime_invoke(getUp,tr,NULL,&exc);
    if(!boxed||exc){ DGHavCamBasis=NO; return NO; }
    v=(float*)DGUnbox(boxed);
    if(!v){ DGHavCamBasis=NO; return NO; }
    memcpy(DGCamUp,v,sizeof(float)*3);
    boxed=DGIL2CPP.runtime_invoke(getFov,cam,NULL,&exc);
    if(!boxed||exc){ DGHavCamBasis=NO; return NO; }
    v=(float*)DGUnbox(boxed);
    if(!v){ DGHavCamBasis=NO; return NO; }
    DGCamFov=v[0];
    if(DGCamFov<20.0f||DGCamFov>150.0f) DGCamFov=60.0f;
    DGHavCamBasis=YES;
    return YES;
}

/* قراءة موضع الكاميرا — للحبة واللوحة */
static BOOL DGGetCameraPosition(float *x,float *y,float *z){
    if(!DGGetCameraBasis()) return NO;
    *x=DGCamPos[0]; *y=DGCamPos[1]; *z=DGCamPos[2];
    return YES;
}

/* إسقاط نقطة عالمية على شاشة الجهاز — يُستخدم للخطوط الآن ولـ ESP لاحقاً */
static BOOL DGProjectToScreen(const float *world, CGFloat *sx, CGFloat *sy){
    if(!DGHavCamBasis) return NO;
    float rx=world[0]-DGCamPos[0], ry=world[1]-DGCamPos[1], rz=world[2]-DGCamPos[2];
    float depth=rx*DGCamFwd[0]+ry*DGCamFwd[1]+rz*DGCamFwd[2];
    if(depth<0.5f) return NO;
    float lx=rx*DGCamRight[0]+ry*DGCamRight[1]+rz*DGCamRight[2];
    float ly=rx*DGCamUp[0]+ry*DGCamUp[1]+rz*DGCamUp[2];
    CGRect b=[UIScreen mainScreen].bounds;
    CGFloat focal=(b.size.height*0.5f)/tanf((DGCamFov*0.5f)*(float)M_PI/180.0f);
    *sx=b.size.width*0.5f + focal*(lx/depth);
    *sy=b.size.height*0.5f - focal*(ly/depth);
    return YES;
}

/* طبقة خطوط الكشف التجريبية — لا تستقبل اللمس إطلاقاً */
@interface DGEspDebugView : UIView @end
@implementation DGEspDebugView
- (void)drawRect:(CGRect)rect{
    (void)rect;
    if(!DGDebugLines || !DGHavCamBasis) return;
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGRect b=self.bounds;
    CGFloat cx=b.size.width*0.5f, cy=b.size.height*0.5f;

    /* مربع تصويب صغير في المنتصف */
    CGContextSetStrokeColorWithColor(c,[UIColor colorWithWhite:1 alpha:0.30].CGColor);
    CGContextSetLineWidth(c,1.0f);
    CGContextStrokeRect(c,CGRectMake(cx-5,cy-5,10,10));

    /* خط أمامي: المركز → نقطة على بعد 8m أمام الكاميرا */
    float pf[3]={DGCamPos[0]+DGCamFwd[0]*8.0f, DGCamPos[1]+DGCamFwd[1]*8.0f, DGCamPos[2]+DGCamFwd[2]*8.0f};
    CGFloat sx,sy;
    if(DGProjectToScreen(pf,&sx,&sy)){
        CGContextSetStrokeColorWithColor(c,[UIColor colorWithRed:0.3 green:1 blue:0.4 alpha:0.9].CGColor);
        CGContextSetLineWidth(c,2.0f);
        CGContextMoveToPoint(c,cx,cy);
        CGContextAddLineToPoint(c,sx,sy);
        CGContextStrokePath(c);
        CGContextSetFillColorWithColor(c,[UIColor colorWithRed:0.3 green:1 blue:0.4 alpha:1].CGColor);
        CGContextFillEllipseInRect(c,CGRectMake(sx-3,sy-3,6,6));
    }

    /* محور اليمين: أحمر قصير */
    float pr[3]={DGCamPos[0]+DGCamRight[0]*4.0f, DGCamPos[1]+DGCamRight[1]*4.0f, DGCamPos[2]+DGCamRight[2]*4.0f};
    if(DGProjectToScreen(pr,&sx,&sy)){
        CGContextSetStrokeColorWithColor(c,[UIColor colorWithRed:1 green:0.35 blue:0.35 alpha:0.9].CGColor);
        CGContextSetLineWidth(c,1.5f);
        CGContextMoveToPoint(c,cx,cy);
        CGContextAddLineToPoint(c,sx,sy);
        CGContextStrokePath(c);
    }

    /* محور الأعلى: أزرق قصير */
    float pu[3]={DGCamPos[0]+DGCamUp[0]*4.0f, DGCamPos[1]+DGCamUp[1]*4.0f, DGCamPos[2]+DGCamUp[2]*4.0f};
    if(DGProjectToScreen(pu,&sx,&sy)){
        CGContextSetStrokeColorWithColor(c,[UIColor colorWithRed:0.4 green:0.6 blue:1 alpha:0.9].CGColor);
        CGContextSetLineWidth(c,1.5f);
        CGContextMoveToPoint(c,cx,cy);
        CGContextAddLineToPoint(c,sx,sy);
        CGContextStrokePath(c);
    }
}
@end

static BOOL DGIsTrainingMode(NSString *scene){
    if(DGForceTraining) return YES;
    if(!scene) return NO;
    NSString *low=[scene lowercaseString];
    return [low containsString:@"train"] || [low containsString:@"practice"] || [low containsString:@"range"];
}

// ===== نهاية المرحلة 1 =====
static NSString *DGMemoryString(void){
    task_vm_info_data_t info; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS){
#if defined(TASK_VM_INFO_REV3)
        return [NSString stringWithFormat:@"%.1f MB",info.phys_footprint/1048576.0];
#else
        return [NSString stringWithFormat:@"%.1f MB",(info.internal+info.compressed/2)/1048576.0]; /* إصلاح: القسمة على البايت كامل */
#endif
    }
    return @"غير متاح";
}

/* هل الشاشة تقدر تعرض أكثر من 60 فعلياً؟ */
static BOOL DGCanUnlock(void){ return DGRealMaxFPS>=90; }

// ===== 90 FPS: السوازل — تشتغل فقط إذا العتاد يقدر يعرض =====

static void DGSwizzle(Class c, SEL a, SEL b){
    if(!c) return;
    Method m1=class_getInstanceMethod(c,a), m2=class_getInstanceMethod(c,b);
    if(m1 && m2) method_exchangeImplementations(m1,m2);
}

@interface UIScreen (DG90)
@end
@implementation UIScreen (DG90)
- (NSInteger)dg_maximumFramesPerSecond{
    if(DG90Enabled && DGCanUnlock()){
        NSInteger real=[self dg_maximumFramesPerSecond];
        return real<120?120:real;
    }
    return [self dg_maximumFramesPerSecond];
}
@end

@interface CADisplayLink (DG90)
@end
@implementation CADisplayLink (DG90)
- (void)dg_setPreferredFramesPerSecond:(NSInteger)fps{
    if(DG90Enabled && DGCanUnlock() && fps<90) fps=90;
    [self dg_setPreferredFramesPerSecond:fps];
}
- (NSInteger)dg_preferredFramesPerSecond{
    NSInteger fps=[self dg_preferredFramesPerSecond];
    if(DG90Enabled && DGCanUnlock() && fps<90) return 90;
    return fps;
}
- (void)dg_setPreferredFrameRateRange:(DGFrameRateRange)r{
    if(DG90Enabled && DGCanUnlock()){
        if(r.maximum<90) r.maximum=90;
        if(r.preferred<90) r.preferred=90;
        if(r.minimum>r.maximum) r.minimum=r.maximum;
    }
    [self dg_setPreferredFrameRateRange:r];
}
- (DGFrameRateRange)dg_preferredFrameRateRange{
    DGFrameRateRange r=[self dg_preferredFrameRateRange];
    if(DG90Enabled && DGCanUnlock()){
        if(r.maximum<90) r.maximum=90;
        if(r.preferred<90) r.preferred=90;
    }
    return r;
}
@end

static void DGSwizzleFPS(void){
    static dispatch_once_t once;
    dispatch_once(&once,^{
        DGSwizzle(NSClassFromString(@"UIScreen"), @selector(maximumFramesPerSecond), @selector(dg_maximumFramesPerSecond));
        Class link=NSClassFromString(@"CADisplayLink");
        DGSwizzle(link, @selector(setPreferredFramesPerSecond:), @selector(dg_setPreferredFramesPerSecond:));
        DGSwizzle(link, @selector(preferredFramesPerSecond), @selector(dg_preferredFramesPerSecond));
        DGSwizzle(link, @selector(setPreferredFrameRateRange:), @selector(dg_setPreferredFrameRateRange:));
        DGSwizzle(link, @selector(preferredFrameRateRange), @selector(dg_preferredFrameRateRange));
    });
}

// ===== نافذة Pass-Through: اللمس يمر للعبة إلا على عناصرنا =====

@interface DGPassThroughWindow : UIWindow @end
@implementation DGPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    UIView *hit=[super hitTest:point withEvent:event];
    if(!hit || hit==self || hit==self.rootViewController.view) return nil;
    return hit;
}
@end

// ===== سلوك الزر العائم: شفافية خمول، التصاق بالحواف، حفظ الموضع =====

static void DGCancelIdle(void){
    if(DGIdleBlock){ dispatch_block_cancel(DGIdleBlock); DGIdleBlock=nil; }
}

static void DGScheduleIdle(void){
    DGCancelIdle();
    DGIdleBlock=dispatch_block_create(0,^{
        DGFloatButton *b=DGButton;
        if(b && !b.isHighlighted && !b.isDGMinimized){
            [UIView animateWithDuration:0.4 animations:^{ b.alpha=0.45; }];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),DGIdleBlock);
}

static void DGSnapButton(DGFloatButton *btn){
    if(!btn) return;
    CGRect sb=[UIScreen mainScreen].bounds;
    CGFloat half=btn.bounds.size.width/2;
    CGFloat x=(btn.center.x<sb.size.width/2)?(10+half):(sb.size.width-10-half);
    CGFloat y=MIN(MAX(btn.center.y,70),sb.size.height-90);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
        btn.center=CGPointMake(x,y);
    } completion:nil];
}

static void DGSaveButtonPos(void){
    if(!DGButton) return;
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(DGButton.frame.origin) forKey:DGFloatPosKey];
}

static void DGRestoreButtonPos(CGRect *frame){
    NSString *s=[[NSUserDefaults standardUserDefaults] stringForKey:DGFloatPosKey];
    if(s){
        CGPoint o=CGPointFromString(s);
        if(o.x>=0 && o.y>=0) *frame=(CGRect){o,frame->size};
    }
}

static void DGHaptic(void){
    if(@available(iOS 10.0,*)){
        UIImpactFeedbackGenerator *g=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [g prepare];
        [g impactOccurred];
    }
}

/* ===== نظام واجهة موحّد — لون وهوية واحدة لكل العناصر ===== */
static UIColor *DGAccentColor(void){ return [UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1]; }

static void DGStyleButton(DGFloatButton *btn, CGFloat size){
    btn.bounds=CGRectMake(0,0,size,size);
    btn.layer.cornerRadius=size/2;
    btn.backgroundColor=[UIColor colorWithWhite:0.04 alpha:0.9];
    btn.layer.borderColor=DGAccentColor().CGColor;
    btn.layer.borderWidth=1.5;
    btn.clipsToBounds=YES;
}

/* بطاقة قسم: عنوان ملوّن في الأعلى + خلفية موحّدة */
static UIView *DGMakeCard(CGRect frame, NSString *titleText){
    UIView *card=[[UIView alloc] initWithFrame:frame];
    card.backgroundColor=[UIColor colorWithWhite:1 alpha:0.055];
    card.layer.cornerRadius=12;
    UILabel *t=[[UILabel alloc] initWithFrame:CGRectMake(12,9,frame.size.width-24,16)];
    t.text=titleText;
    t.textColor=DGAccentColor();
    t.font=[UIFont boldSystemFontOfSize:12];
    [card addSubview:t];
    return card;
}

/* صف تفعيل: نص واضح + مفتاح — الحالة تُقرأ من المفتاح نفسه */
static UIView *DGToggleRow(CGFloat y, NSString *text, SEL action, UISwitch * __strong *outSwitch){
    UIView *row=[[UIView alloc] initWithFrame:CGRectMake(0,y,276,34)];
    UILabel *l=[[UILabel alloc] initWithFrame:CGRectMake(12,0,204,34)];
    l.text=text; l.textColor=[UIColor whiteColor]; l.font=[UIFont systemFontOfSize:13];
    UISwitch *sw=[[UISwitch alloc] initWithFrame:CGRectMake(215,1,51,32)];
    sw.transform=CGAffineTransformMakeScale(0.8,0.8);
    sw.onTintColor=DGAccentColor();
    [sw addTarget:[DGMenu class] action:action forControlEvents:UIControlEventValueChanged];
    [row addSubview:l]; [row addSubview:sw];
    if(outSwitch) *outSwitch=sw;
    return row;
}

@implementation DGFloatButton

/* سحب بالضغط المطوّل: الضغط العادي يبقى للفتح، والسحب ما يتعارض مع النقرة */
- (void)dgLongPress:(UILongPressGestureRecognizer *)g{
    CGPoint p=[g locationInView:DGWindow];
    if(g.state==UIGestureRecognizerStateBegan){
        DGCancelIdle();
        DGHaptic();
        [UIView animateWithDuration:0.1 animations:^{ self.alpha=1.0; self.transform=CGAffineTransformMakeScale(1.12,1.12); }];
    } else if(g.state==UIGestureRecognizerStateChanged){
        self.center=CGPointMake(p.x,p.y-32); /* يطفو فوق الإصبع */
    } else if(g.state==UIGestureRecognizerStateEnded || g.state==UIGestureRecognizerStateCancelled){
        [UIView animateWithDuration:0.15 animations:^{ self.transform=CGAffineTransformIdentity; }];
        DGSnapButton(self);
        DGSaveButtonPos();
        DGScheduleIdle();
    }
}

/* نقرة مزدوجة: تصغير إلى نقطة صغيرة حتى لا تعيق التجارب */
- (void)dgDoubleTap:(UITapGestureRecognizer *)g{
    (void)g;
    self.dgMinimized=!self.dgMinimized;
    CGFloat size=self.dgMinimized?26:50;
    DGCancelIdle();
    DGHaptic();
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0 animations:^{
        self.frame=CGRectMake(self.center.x-size/2,self.center.y-size/2,size,size);
        self.layer.cornerRadius=size/2;
        self.titleLabel.font=[UIFont systemFontOfSize:self.dgMinimized?11:20];
        self.alpha=1.0;
    } completion:^(BOOL f){ (void)f; DGScheduleIdle(); }];
    if(self.dgMinimized && DGPanel && !DGPanel.isHidden) [DGMenu hidePanel];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [super touchesBegan:touches withEvent:event];
    DGCancelIdle();
    self.alpha=1.0;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [super touchesEnded:touches withEvent:event];
    DGScheduleIdle();
}
@end

@implementation DGMenu

+ (void)start{
    if(DGStarted) return;
    DGStarted=YES;
    DGRealMaxFPS=[UIScreen mainScreen].maximumFramesPerSecond;
    DG90Enabled=[[NSUserDefaults standardUserDefaults] boolForKey:DG90Key];
    DGForceTraining=[[NSUserDefaults standardUserDefaults] boolForKey:DGForceTrainingKey];
    DGDebugLines=[[NSUserDefaults standardUserDefaults] boolForKey:DGDebugLinesKey];
    DGSwizzleFPS();
    [self install];
}

+ (void)install{
    if(DGWindow) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [DGMenu build]; });
}

+ (void)build{
    if(DGWindow) return;
    DGSessionStart=[NSDate date];
    DGWindow=[[DGPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DGWindow.windowLevel=UIWindowLevelStatusBar+100;
    DGWindow.rootViewController=[UIViewController new];
    DGWindow.rootViewController.view.backgroundColor=[UIColor clearColor];
    DGWindow.hidden=NO;
    UIView *root=DGWindow.rootViewController.view;

    /* ===== الزر العائم — نظيف، سلس، لا يعيق ===== */
    CGRect btnFrame=CGRectMake(20,140,50,50);
    DGRestoreButtonPos(&btnFrame);
    DGButton=[DGFloatButton buttonWithType:UIButtonTypeCustom];
    DGButton.frame=btnFrame;
    DGStyleButton(DGButton,50);
    [DGButton setTitle:@"🛡" forState:UIControlStateNormal];
    DGButton.titleLabel.font=[UIFont systemFontOfSize:20];
    [DGButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgLongPress:)];
    hold.minimumPressDuration=0.25;
    [DGButton addGestureRecognizer:hold];
    UITapGestureRecognizer *dt=[[UITapGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgDoubleTap:)];
    dt.numberOfTapsRequired=2;
    [DGButton addGestureRecognizer:dt];
    [root addSubview:DGButton];
    DGScheduleIdle();

    /* ===== اللوحة: ترويسة + تمرير + بطاقات أقسام ===== */
    CGRect panelFrame=CGRectMake(60,110,300,400);
    NSString *ps=[[NSUserDefaults standardUserDefaults] stringForKey:DGPanelPosKey];
    if(ps){
        CGPoint o=CGPointFromString(ps);
        if(o.x>=0 && o.y>=0) panelFrame=(CGRect){o,panelFrame.size};
    }
    DGPanel=[[UIView alloc] initWithFrame:panelFrame];
    DGPanel.backgroundColor=[UIColor colorWithWhite:0.05 alpha:0.97];
    DGPanel.layer.cornerRadius=16;
    DGPanel.layer.borderColor=[DGAccentColor() colorWithAlphaComponent:0.55].CGColor;
    DGPanel.layer.borderWidth=1;
    DGPanel.layer.shadowColor=[UIColor blackColor].CGColor;
    DGPanel.layer.shadowOpacity=0.45;
    DGPanel.layer.shadowRadius=14;
    DGPanel.layer.shadowOffset=CGSizeMake(0,8);
    DGPanel.hidden=YES;

    /* الترويسة — منطقة السحب الوحيدة، واضحة وثابتة */
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,300,46)];
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(14,6,230,20)];
    title.text=@"🛡 حارس دلتا";
    title.textColor=[UIColor whiteColor]; title.font=[UIFont boldSystemFontOfSize:15];
    UILabel *sub=[[UILabel alloc] initWithFrame:CGRectMake(14,26,230,13)];
    sub.text=@"DeltaGuard iOS — المرحلة 2: ماسح UE4";
    sub.textColor=[UIColor colorWithWhite:1 alpha:0.45]; sub.font=[UIFont systemFontOfSize:9];
    UIButton *closeB=[UIButton buttonWithType:UIButtonTypeSystem];
    closeB.frame=CGRectMake(258,9,32,28);
    [closeB setTitle:@"✕" forState:UIControlStateNormal];
    closeB.titleLabel.font=[UIFont boldSystemFontOfSize:15];
    closeB.tintColor=[UIColor colorWithWhite:1 alpha:0.6];
    [closeB addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    UIView *sep=[[UIView alloc] initWithFrame:CGRectMake(14,45.5,272,0.5)];
    sep.backgroundColor=[UIColor colorWithWhite:1 alpha:0.1];
    [header addSubview:title]; [header addSubview:sub]; [header addSubview:closeB]; [header addSubview:sep];
    UIPanGestureRecognizer *panelPan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dgPanelPan:)];
    [header addGestureRecognizer:panelPan];
    [DGPanel addSubview:header];

    DGScroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,300,354)];
    DGScroll.showsVerticalScrollIndicator=NO;
    DGScroll.alwaysBounceVertical=YES;
    DGScroll.delaysContentTouches=NO;
    UIView *content=[[UIView alloc] initWithFrame:CGRectMake(0,0,300,360)];
    [DGScroll addSubview:content];

    /* — البطاقة 1: الحالة — */
    UIView *c1=DGMakeCard(CGRectMake(12,12,276,64),@"📊 الحالة");
    DGStatsLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,28,252,30)];
    DGStatsLabel.textColor=[UIColor colorWithRed:0.45 green:1 blue:0.65 alpha:1];
    DGStatsLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    DGStatsLabel.numberOfLines=2;
    [c1 addSubview:DGStatsLabel];
    [content addSubview:c1];

    /* — البطاقة 2: ماسح UE4 — الأهم — */
    UIView *c2=DGMakeCard(CGRectMake(12,84,276,124),@"🎯 ماسح UE4 — GUObjectArray");
    DGUE4Label=[[UILabel alloc] initWithFrame:CGRectMake(12,28,252,44)];
    DGUE4Label.textColor=[UIColor colorWithRed:1 green:0.85 blue:0.3 alpha:1];
    DGUE4Label.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    DGUE4Label.numberOfLines=3;
    DGUE4Label.text=@"UE4: الماسح لم يبدأ";
    [c2 addSubview:DGUE4Label];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(12,76,252,40)];
    hint.text=@"يفحص كل 30 ثانية تلقائيًا\nعند ✅: اهتزاز — اخرج وأرسل deltaguard_ue4.txt";
    hint.textColor=[UIColor colorWithWhite:1 alpha:0.5];
    hint.font=[UIFont systemFontOfSize:9];
    hint.numberOfLines=2;
    [c2 addSubview:hint];
    [content addSubview:c2];

    /* — البطاقة 3: التحميل الموثق — */
    /* — البطاقة 4: التحميل الحي — */
    UIView *c4=DGMakeCard(CGRectMake(12,216,276,118),@"📥 ملف التحليل — 5 أجزاء (416MB)");
    DGDLButton=[UIButton buttonWithType:UIButtonTypeSystem];
    DGDLButton.frame=CGRectMake(12,30,252,28);
    [DGDLButton setTitle:@"بدء التحميل من GitHub" forState:UIControlStateNormal];
    [DGDLButton addTarget:self action:@selector(dgStartDownload) forControlEvents:UIControlEventTouchUpInside];
    [c4 addSubview:DGDLButton];
    DGDLBar=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    DGDLBar.frame=CGRectMake(12,64,252,6);
    DGDLBar.progress=0; DGDLBar.progressTintColor=DGAccentColor();
    [c4 addSubview:DGDLBar];
    DGDLProgressLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,72,252,14)];
    DGDLProgressLabel.text=@"0 / 416 MB (0%)";
    DGDLProgressLabel.textColor=[UIColor colorWithWhite:1 alpha:0.55];
    DGDLProgressLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    [c4 addSubview:DGDLProgressLabel];
    DGDLStatusLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,86,252,28)];
    DGDLStatusLabel.text=@"⚪ لم يبدأ";
    DGDLStatusLabel.textColor=[UIColor whiteColor];
    DGDLStatusLabel.font=[UIFont systemFontOfSize:10];
    DGDLStatusLabel.numberOfLines=2;
    [c4 addSubview:DGDLStatusLabel];
    [content addSubview:c4];


    DGScroll.contentSize=CGSizeMake(300,360);

    [DGPanel addSubview:DGScroll];
    [root addSubview:DGPanel];

    [self syncUI];
    [DGStatsLabel setText:[self statsText]];

    DGLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [DGLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DGStatsTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    DGDiscoveryTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateDiscovery) userInfo:nil repeats:YES];
    [self updateDiscovery];
}

/* سحب اللوحة من شريط العنوان مع التثبيت داخل الشاشة والحفظ */
+ (void)dgPanelPan:(UIPanGestureRecognizer *)g{
    CGPoint t=[g translationInView:DGWindow];
    static CGPoint start;
    if(g.state==UIGestureRecognizerStateBegan) start=DGPanel.center;
    DGPanel.center=CGPointMake(start.x+t.x,start.y+t.y);
    [g setTranslation:CGPointZero inView:DGWindow];
    if(g.state==UIGestureRecognizerStateEnded || g.state==UIGestureRecognizerStateCancelled){
        CGRect b=[UIScreen mainScreen].bounds;
        CGFloat pw=DGPanel.bounds.size.width, ph=DGPanel.bounds.size.height;
        CGFloat cx=MIN(MAX(DGPanel.center.x,pw/2),b.size.width-pw/2);
        CGFloat cy=MIN(MAX(DGPanel.center.y,ph/2+40),b.size.height-ph/2-40);
        [UIView animateWithDuration:0.25 animations:^{ DGPanel.center=CGPointMake(cx,cy); }];
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(DGPanel.frame.origin) forKey:DGPanelPosKey];
    }
}

+ (void)dg90Changed:(UISwitch *)sw{
    DG90Enabled=sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:DG90Enabled forKey:DG90Key];
    [DGStatsLabel setText:[self statsText]];
}

+ (void)dgTrainingChanged:(UISwitch *)sw{
    DGForceTraining=sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:DGForceTraining forKey:DGForceTrainingKey];
    [self updateDiscovery];
}

+ (void)dgDebugChanged:(UISwitch *)sw{
    DGDebugLines=sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:DGDebugLines forKey:DGDebugLinesKey];
    if(!DGDebugLines && DGEspView) [DGEspView setNeedsDisplay];
}

/* مزامنة كل الواجهة مع الحالة الفعلية — تُستدعى عند فتح اللوحة */
+ (void)syncUI{
    if(DG90Switch){
        BOOL can=DGCanUnlock();
        DG90Switch.enabled=can;
        DG90Switch.on=can && DG90Enabled;
        DG90Note.hidden=can;
    }
    if(DGTrainingSwitch) DGTrainingSwitch.on=DGForceTraining;
    if(DGDebugSwitch) DGDebugSwitch.on=DGDebugLines;
}

+ (void)updateDiscovery{
    if(!DGPanel && !DGCoordPill) return;

    /* (1) حالة IL2CPP + كتابة التشخيص عند كل تغير */
    DGResolveIL2CPP();
    DGWriteDiag();
    DGStartProbe(); /* يشتغل فقط عند اكتمال المراسي والدوال — وإلا يصمت */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0),^{
        DGUE4Scan();              /* الأولوية القصوى: GUObjectArray الحي */
        DGDumpSymbols();
        DGScanMemoryForMetadata();
    });

    /* (2) المشهد النشط */
    NSString *scene=DGGetSceneName();

    /* عند اكتشاف أول مشهد فعلي: نفّذ فحص الكلاسات مرة واحدة */
    if(scene && scene.length>0 && !DGCandidatesScanned){
        DGScanCandidateClasses();
    }

    BOOL training=DGIsTrainingMode(scene);

    /* (3) تحديث واجهة اللوحة */
    if(DGSceneLabel){
        if(!DGIL2CPP.available){
            DGSceneLabel.text=[NSString stringWithFormat:@"⚠️ %@ | جزئي:%d/4",[[NSString alloc] initWithUTF8String:DGDiagShort],DGIL2CPP.partialAPIs];
        } else if(!scene || scene.length==0){
            DGSceneLabel.text=[NSString stringWithFormat:@"IL2CPP ✅ (%zu assembly) | المشهد: …",DGIL2CPP.assemblies];
        } else {
            DGSceneLabel.text=[NSString stringWithFormat:@"IL2CPP ✅ (%zu assembly)%@ | المشهد: %@%@",DGIL2CPP.assemblies,DGIL2CPP.resolvedViaOffsets?@" 📐offsets":@"",scene,training?@" 🎯":@""];
        }
    }

    if(DGCandidatesLabel){
        if(!DGIL2CPP.available){
            DGCandidatesLabel.text=@"واجهة il2cpp الكاملة غير مصدَّرة (KiwiVM)\nالحل: أوفسيتات من التحليل ← DGOffsets في Tweak.m\nأو ابحث في deltaguard_exports.txt عن domain/invoke";
        } else if(!DGCandidatesScanned){
            DGCandidatesLabel.text=@"فحص الكلاسات المرشحة: جارٍ…";
        } else if(DGCandidateClasses.count==0){
            DGCandidatesLabel.text=@"لا كلاسات مرشحة بعد — أضف كلمات مفتاحية في DGNameMatches";
        } else {
            NSMutableString *ms=[NSMutableString stringWithFormat:@"🧪 alloc:%u enter:%u | كلاسات:%d | مطابق:%d\n",(unsigned)DGAllocCount,(unsigned)DGEnterCount,DGSeenCount,DGMatchCount];
            if(DGMatchCount>0){
                [ms appendString:@"مطابقات: "];
                for(int i=0;i<DGMatchCount && i<3;i++) [ms appendFormat:@"%s ",DGMatchNames[i]];
                [ms appendString:@"\n"];
            }
            NSUInteger shown=0;
            for(int i=0;i<DGSeenCount && shown<3;i++){
                if(DGSeen[i].allocs>1){ [ms appendFormat:@"• %s ×%u\n",DGSeen[i].name,DGSeen[i].allocs]; shown++; }
            }
            DGCandidatesLabel.text=ms;
        }
    }

    /* (3.5) حالة ماسح UE4 — حي */
    if(DGUE4Label){
        DGUE4Label.text=[NSString stringWithFormat:@"UE4: %s",DGUE4Stat];
        DGUE4Label.textColor=DGUE4FoundFlag?[UIColor systemGreenColor]:[UIColor colorWithRed:1 green:0.85 blue:0.3 alpha:1];
    }

    /* (4) قراءة الإحداثيات — تظهر فقط في وضع التدريب */
    float px=0,py=0,pz=0;
    BOOL havePos=(training && DGGetCameraPosition(&px,&py,&pz));
    if(DGCoordLabel){
        if(training){
            DGCoordLabel.text=havePos?
                [NSString stringWithFormat:@"📍 %.2f  %.2f  %.2f",px,py,pz]:
                @"📍 الإحداثيات: بانتظار تهيئة الكاميرا…";
        } else {
            DGCoordLabel.text=@"📍 الإحداثيات: دخّل وضع التدريب للقراءة";
        }
    }

    /* (5) الحبة المصغرة أعلى الشاشة */
    if(DGCoordPill){
        DGCoordPill.hidden=!training;
        if(training){
            DGCoordPill.text=havePos?
                [NSString stringWithFormat:@"📍 %.1f / %.1f / %.1f",px,py,pz]:
                @"📍 بانتظار الكاميرا…";
        }
    }
}

/* ===== نهاية منطق المرحلة 1 ===== */

+ (void)frame:(CADisplayLink *)l{
    (void)l;
    DGFrameCount++;
    /* تحديث قاعدة الكاميرا وإعادة رسم خطوط التجربة — فقط عند تفعيلها */
    if(DGDebugLines && DGEspView){
        if(DGGetCameraBasis()) [DGEspView setNeedsDisplay];
    }
}
+ (void)updateStats{ DGFPS=DGFrameCount; DGFrameCount=0; [DGStatsLabel setText:[self statsText]]; }

+ (NSString *)statsText{
    NSTimeInterval up=-[DGSessionStart timeIntervalSinceNow];
    return [NSString stringWithFormat:@"الذاكرة: %@ | التشغيل: %02d:%02d\nDeltaGuard v0.11.4 — UE4",
        DGMemoryString(),(int)(up/60),((int)up)%60];
}

+ (void)togglePanel{
    DGHaptic();
    [self syncUI];
    if(DGPanel.isHidden){
        DGPanel.hidden=NO;
        DGPanel.alpha=0;
        DGPanel.transform=CGAffineTransformMakeScale(0.85,0.85);
        [UIView animateWithDuration:0.2 animations:^{ DGPanel.alpha=1; DGPanel.transform=CGAffineTransformIdentity; }];
        [self updateDiscovery];
    } else {
        [UIView animateWithDuration:0.15 animations:^{ DGPanel.alpha=0; DGPanel.transform=CGAffineTransformMakeScale(0.9,0.9); }
                         completion:^(BOOL f){ DGPanel.hidden=YES; DGPanel.transform=CGAffineTransformIdentity; DGPanel.alpha=1; }];
    }
}
+ (void)hidePanel{ DGPanel.hidden=YES; }
+ (void)quitGame{
    DGStatsLabel.text=@"جاري إنهاء اللعبة…";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ exit(0); });
}
@end

/* ============================================================
   v0.7.2 — مدير التحميل الحي (5 أجزاء + تجميع + تحقق SHA-256)
   ============================================================ */
@implementation DGMenu (DGDownload)

+ (void)dgStartDownload{
    if(DGDLBusy) return;
    DGDLBusy=YES; DGDLPartsDone=0; DGDLCurrentPart=0;
    DGDLBar.progress=0;
    DGDLProgressLabel.text=@"0 / 416 MB (0%)";
    DGDLStatusLabel.text=@"⬇️ بدأ التحميل...";
    DGDLButton.enabled=NO;
    [DGDLButton setTitle:@"⏳ جارٍ التحميل..." forState:UIControlStateNormal];
    DGDLBuffer=[NSMutableData data];
    DGDLDelegate=[DGDownloadDelegate new];
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    DGDLSession=[NSURLSession sessionWithConfiguration:cfg delegate:DGDLDelegate delegateQueue:nil];
    [DGMenu dgStartPart:0];
}

+ (void)dgStartPart:(int)idx{
    DGDLCurrentPartBytes=0;
    DGDLResponseValid=NO;
    DGDLHTTPStatusCode=0;
    NSString *u=[NSString stringWithFormat:@"https://raw.githubusercontent.com/aosaid3224-ops/Zain-iOS-Tools/main/DeltaForceClient/DeltaForceClient.part%03d",idx+1];
    dispatch_async(dispatch_get_main_queue(),^{
        DGDLStatusLabel.text=[NSString stringWithFormat:@"⬇️ يحمّل الجزء %d/5 ...",idx+1];
    });
    NSURLSessionDataTask *t=[DGDLSession dataTaskWithURL:[NSURL URLWithString:u]];
    [t resume];
}

+ (void)dgAssemble{
    dispatch_async(dispatch_get_main_queue(),^{ DGDLStatusLabel.text=@"🔧 تجميع الأجزاء الخمسة..."; });
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *outp=[NSTemporaryDirectory() stringByAppendingPathComponent:@"DeltaForceClient"];
    [fm removeItemAtPath:outp error:nil];
    [fm createFileAtPath:outp contents:nil attributes:nil];
    NSFileHandle *of=[NSFileHandle fileHandleForWritingAtPath:outp];
    if(!of){
        dispatch_async(dispatch_get_main_queue(),^{ DGDLStatusLabel.text=@"❌ تعذر إنشاء الملف المجمع"; DGDLButton.enabled=YES; DGDLBusy=NO; });
        return;
    }
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    for(int i=1;i<=5;i++){
        NSString *p=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dfpart%03d",i]];
        NSFileHandle *fh=[NSFileHandle fileHandleForReadingAtPath:p];
        if(!fh){
            [of closeFile]; [fm removeItemAtPath:outp error:nil];
            dispatch_async(dispatch_get_main_queue(),^{ DGDLStatusLabel.text=[NSString stringWithFormat:@"❌ الجزء %d مفقود؛ أعد التحميل",i]; DGDLButton.enabled=YES; DGDLBusy=NO; });
            return;
        }
        while(YES){
            NSData *c=[fh readDataOfLength:8388608];
            if(!c||!c.length) break;
            CC_SHA256_Update(&ctx,c.bytes,(CC_LONG)c.length);
            [of writeData:c];
        }
        [fh closeFile];
        [fm removeItemAtPath:p error:nil];
    }
    [of closeFile];
    unsigned char dig[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(dig,&ctx);
    NSMutableString *hs=[NSMutableString string];
    for(int i=0;i<32;i++) [hs appendFormat:@"%02x",dig[i]];
    long fsz=(long)[[fm attributesOfItemAtPath:outp error:nil][NSFileSize] longLongValue];
    BOOL ok=(fsz==416167600L && [hs isEqualToString:DGDLExpectedSHA256]);
    dispatch_async(dispatch_get_main_queue(),^{
        DGDLBar.progress=1.0f;
        DGDLProgressLabel.text=@"416 / 416 MB (100%)";
        DGDLStatusLabel.text=[NSString stringWithFormat:@"%@ | الحجم: %ld بايت | SHA256: %@...",
            ok?@"✅ اكتمل فعليًا — بصمة مطابقة":@"❌ التجميع انتهى لكن البصمة غير مطابقة",fsz,[hs substringToIndex:16]];
        DGDLButton.enabled=YES;
        [DGDLButton setTitle:@"🔄 إعادة التحميل" forState:UIControlStateNormal];
        DGDLBusy=NO;
    });
}

@end

@implementation DGDownloadDelegate

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))c{
    [DGDLBuffer setLength:0];
    DGDLCurrentPartBytes=0;
    DGDLHTTPStatusCode=[r isKindOfClass:[NSHTTPURLResponse class]]?[(NSHTTPURLResponse *)r statusCode]:0;
    DGDLResponseValid=([r isKindOfClass:[NSHTTPURLResponse class]] && DGDLHTTPStatusCode==200);
    c(DGDLResponseValid?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
}

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{
    if(!DGDLResponseValid) return;
    [DGDLBuffer appendData:d];
    DGDLCurrentPartBytes+=(long)d.length;
    long cur=DGDLPartsDone+DGDLCurrentPartBytes;
    float f=(float)cur/416167600.0f;
    dispatch_async(dispatch_get_main_queue(),^{
        DGDLBar.progress=f;
        DGDLProgressLabel.text=[NSString stringWithFormat:@"%ld / 416 MB (%d%%)",cur/1000000,(int)(f*100.0f)];
    });
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e{
    long bytes=DGDLCurrentPartBytes;
    NSInteger status=DGDLHTTPStatusCode;
    BOOL valid=DGDLResponseValid && DGDLCurrentPart>=0 && DGDLCurrentPart<5 && bytes==DGDLPartSizes[DGDLCurrentPart];
    if(e || !valid){
        NSString *reason=e.localizedDescription;
        if(!DGDLResponseValid) reason=[NSString stringWithFormat:@"استجابة HTTP غير صالحة (%ld)",(long)status];
        else if(!valid) reason=[NSString stringWithFormat:@"حجم الجزء غير صحيح (%ld بايت)",bytes];
        dispatch_async(dispatch_get_main_queue(),^{
            DGDLStatusLabel.text=[NSString stringWithFormat:@"❌ خطأ في الجزء %d: %@",DGDLCurrentPart+1,reason?:@"فشل غير معروف"];
            DGDLButton.enabled=YES;
            [DGDLButton setTitle:@"🔄 إعادة المحاولة" forState:UIControlStateNormal];
            DGDLBusy=NO;
        });
        [s invalidateAndCancel];
        return;
    }
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dfpart%03d",DGDLCurrentPart+1]];
    if(![DGDLBuffer writeToFile:out atomically:YES]){
        dispatch_async(dispatch_get_main_queue(),^{ DGDLStatusLabel.text=@"❌ تعذّر حفظ الجزء؛ أعد المحاولة"; DGDLButton.enabled=YES; [DGDLButton setTitle:@"🔄 إعادة المحاولة" forState:UIControlStateNormal]; DGDLBusy=NO; });
        [s invalidateAndCancel];
        return;
    }
    DGDLPartsDone+=bytes;
    DGDLCurrentPart++;
    if(DGDLCurrentPart<5){ [DGMenu dgStartPart:DGDLCurrentPart]; }
    else { [DGMenu dgAssemble]; [s finishTasksAndInvalidate]; }
}

@end

__attribute__((constructor)) static void DGEntry(void){
    @autoreleasepool{
        /* لا نستدعي UIKit من constructor: UIScreen غير مهيأ بعد وقد يسبب deadlock في iOS 18. */
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                               object:nil
                                                                queue:[NSOperationQueue mainQueue]
                                                           usingBlock:^(NSNotification *note){
                (void)note;
                [DGMenu start];
            }];
            UIApplication *app=[UIApplication sharedApplication];
            if(app.applicationState==UIApplicationStateActive || app.applicationState==UIApplicationStateInactive){
                [DGMenu start];
            }
        });
    }
}
