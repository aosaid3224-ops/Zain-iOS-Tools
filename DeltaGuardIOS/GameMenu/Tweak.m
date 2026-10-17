#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdlib.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#ifndef LC_DYLD_EXPORTS_TRIE
#define LC_DYLD_EXPORTS_TRIE 0x80000033 /* شجرة تصدير dyld3 الحديثة — Xcode 13+ */
#endif

/* نفس تخطيط CAFrameRateRange (iOS 15+) */
typedef struct { float minimum; float maximum; float preferred; } DGFrameRateRange;

@interface DGMenu : NSObject
+ (void)hidePanel;
+ (void)install;
+ (void)start;
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
static char DGAnchorHost[256]="";
static uint64_t DGMetaAddr=0;
static uint64_t DGCSharpAddr=0;
static uint64_t DGMetaSize=0;

/* فحص كل ذاكرة العملية (mach_vm_region) — الـ metadata قد يكون mmap خارج صور dyld */
static void DGScanMemoryForMetadata(void){
    static BOOL tried=NO; if(tried) return; tried=YES;
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:@"global-metadata.dat"];
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];
    mach_vm_address_t addr=0x100000000;
    const char *cs="Assembly-CSharp";
    const size_t csLen=strlen(cs);
    for(;;){
        mach_vm_size_t size=0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj=MACH_PORT_NULL;
        kern_return_t kr=mach_vm_region(mach_task_self(),&addr,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&cnt,&obj);
        if(kr!=KERN_SUCCESS) break;
        if(obj!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),obj);
        if((info.protection&VM_PROT_READ) && size>4096 && size<0x40000000ULL){ /* أقل من 1GB */
            const uint8_t *base=(const uint8_t*)(uintptr_t)addr;
            uint64_t rem=(uint64_t)size;
            const uint8_t *p=base;
            while(rem>csLen+8){
                p=(const uint8_t*)memchr(p,0xAF,rem-(csLen+8));
                if(!p) break;
                uint32_t v,ver;
                memcpy(&v,p,4);
                if(v==0xFAB11BAFu){
                    memcpy(&ver,p+4,4);
                    if(ver>=21 && ver<=40){
                        uint64_t dump=rem>100663296?100663296:rem;
                        NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:out];
                        if(!fh){ [[NSFileManager defaultManager] createFileAtPath:out contents:nil attributes:nil]; fh=[NSFileHandle fileHandleForWritingAtPath:out]; }
                        if(fh){
                            [fh truncateFileAtOffset:0];
                            [fh writeData:[NSData dataWithBytesNoCopy:(void*)p length:(NSUInteger)dump freeWhenDone:NO]];
                            [fh closeFile];
                            DGMetaAddr=(uint64_t)(uintptr_t)p;
                            DGMetaSize=dump;
                            NSString *docs=@"/var/mobile/Documents";
                            [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
                            NSString *destination=[docs stringByAppendingPathComponent:@"global-metadata.dat"];
                            [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
                            [[NSFileManager defaultManager] copyItemAtPath:out toPath:destination error:nil];
                        }
                        return; /* اكتمل */
                    }
                }
                rem=(uint64_t)(base+size)-(uint64_t)(p+1);
                p=p+1;
            }
        }
        addr+=size;
        if(addr<0x100000000) break;
    }
}

/* تحديد مكان سلاسل metadata كنصوص دلالية */
static void DGFindCSharpStrings(void){
    const char *cs="Assembly-CSharp";
    const size_t csLen=strlen(cs);
    mach_vm_address_t addr=0x100000000;
    for(;;){
        mach_vm_size_t size=0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj=MACH_PORT_NULL;
        kern_return_t kr=mach_vm_region(mach_task_self(),&addr,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&cnt,&obj);
        if(kr!=KERN_SUCCESS) break;
        if(obj!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),obj);
        if((info.protection&VM_PROT_READ) && size>csLen+8 && size<0x40000000ULL){
            const uint8_t *base=(const uint8_t*)(uintptr_t)addr;
            const uint8_t *hit=(const uint8_t*)memchr(base,cs[0],size-csLen);
            while(hit){
                if(memcmp(hit,cs,csLen)==0){ DGCSharpAddr=(uint64_t)(uintptr_t)hit; return; }
                uint64_t off=(uint64_t)(hit-base)+1;
                if(off>=size-csLen) break;
                hit=(const uint8_t*)memchr(base+off,cs[0],size-csLen-off);
            }
        }
        addr+=size;
        if(addr<0x100000000) break;
    }
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
    [m appendFormat:@"metadata@0x%llx size=%llu | csharpStrings@0x%llx\n",(unsigned long long)DGMetaAddr,(unsigned long long)DGMetaSize,(unsigned long long)DGCSharpAddr];

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

    /* حبة الإحداثيات أعلى الشاشة — أثناء التدريب فقط */
    DGCoordPill=[[UILabel alloc] initWithFrame:CGRectMake(0,54,220,26)];
    DGCoordPill.center=CGPointMake([UIScreen mainScreen].bounds.size.width/2,DGCoordPill.center.y);
    DGCoordPill.backgroundColor=[UIColor colorWithWhite:0 alpha:0.55];
    DGCoordPill.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGCoordPill.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    DGCoordPill.textAlignment=NSTextAlignmentCenter;
    DGCoordPill.layer.cornerRadius=13;
    DGCoordPill.clipsToBounds=YES;
    DGCoordPill.hidden=YES;
    DGCoordPill.userInteractionEnabled=NO;
    [root addSubview:DGCoordPill];

    /* طبقة خطوط الكشف — لا تلمس شيئاً */
    DGEspView=[[DGEspDebugView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DGEspView.backgroundColor=[UIColor clearColor];
    DGEspView.opaque=NO;
    DGEspView.userInteractionEnabled=NO;
    [root addSubview:DGEspView];

    /* ===== اللوحة: ترويسة + تمرير + بطاقات أقسام ===== */
    CGRect panelFrame=CGRectMake(60,110,300,460);
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
    sub.text=@"DeltaGuard iOS — المرحلة 1: الاستكشاف";
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

    DGScroll=[[UIScrollView alloc] initWithFrame:CGRectMake(0,46,300,414)];
    DGScroll.showsVerticalScrollIndicator=NO;
    DGScroll.alwaysBounceVertical=YES;
    DGScroll.delaysContentTouches=NO;
    UIView *content=[[UIView alloc] initWithFrame:CGRectMake(0,0,300,470)];
    [DGScroll addSubview:content];

    /* — البطاقة 1: الإحصائيات — */
    UIView *c1=DGMakeCard(CGRectMake(12,12,276,92),@"📊 الإحصائيات");
    DGStatsLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,30,252,52)];
    DGStatsLabel.textColor=[UIColor colorWithRed:0.45 green:1 blue:0.65 alpha:1];
    DGStatsLabel.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    DGStatsLabel.numberOfLines=3;
    [c1 addSubview:DGStatsLabel];
    [content addSubview:c1];

    /* — البطاقة 2: التفعيلات — كل حالة تُقرأ من المفتاح نفسه — */
    UIView *c2=DGMakeCard(CGRectMake(12,112,276,168),@"⚡ التفعيلات");
    UIView *r1=DGToggleRow(30,@"فتح 90 FPS",@selector(dg90Changed:),&DG90Switch);
    UIView *r2=DGToggleRow(66,@"وضع التدريب (قراءة الإحداثيات)",@selector(dgTrainingChanged:),&DGTrainingSwitch);
    UIView *r3=DGToggleRow(102,@"خطوط الكشف التجريبية",@selector(dgDebugChanged:),&DGDebugSwitch);
    DG90Note=[[UILabel alloc] initWithFrame:CGRectMake(12,136,252,28)];
    DG90Note.text=@"⚠️ شاشتك 60Hz — التفعيل لن يغيّر معدل الإطارات فعلياً";
    DG90Note.textColor=[UIColor systemYellowColor];
    DG90Note.font=[UIFont systemFontOfSize:10];
    DG90Note.numberOfLines=2;
    [c2 addSubview:r1]; [c2 addSubview:r2]; [c2 addSubview:r3]; [c2 addSubview:DG90Note];
    [content addSubview:c2];

    /* — البطاقة 3: استكشاف الكائنات — */
    UIView *c3=DGMakeCard(CGRectMake(12,288,276,168),@"🔍 استكشاف الكائنات");
    DGSceneLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,30,252,16)];
    DGSceneLabel.textColor=[UIColor whiteColor];
    DGSceneLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    DGCoordLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,48,252,18)];
    DGCoordLabel.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGCoordLabel.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    DGCandidatesLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,68,252,90)];
    DGCandidatesLabel.textColor=[UIColor colorWithWhite:1 alpha:0.65];
    DGCandidatesLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    DGCandidatesLabel.numberOfLines=6;
    [c3 addSubview:DGSceneLabel]; [c3 addSubview:DGCoordLabel]; [c3 addSubview:DGCandidatesLabel];
    [content addSubview:c3];

    DGScroll.contentSize=CGSizeMake(300,470);
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
        DGScanMemoryForMetadata();
        DGFindCSharpStrings();
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
    NSString *mode;
    if(!DG90Enabled) mode=@"متوقف";
    else if(DGCanUnlock()) mode=@"مفعّل ✅";
    else mode=@"مفعّل — بلا فائدة (60Hz)";
    return [NSString stringWithFormat:@"إطارات الشاشة: %ld Hz | الذاكرة: %@\nمدة التشغيل: %02d:%02d | 90FPS: %@",
        (long)DGRealMaxFPS,DGMemoryString(),(int)(up/60),((int)up)%60,mode];
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
