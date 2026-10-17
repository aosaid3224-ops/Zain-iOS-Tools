#import <UIKit/UIKit.h>
#import <mach/mach.h>
#include <stdlib.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

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
static UIButton *DG90Button;
static UIButton *DGTrainingButton;
static UIButton *DGDebugButton;
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

/* البحث عن رمز مصدّر داخل صورة محمّلة عبر شجرة التصدير — دون الحاجة لـ dlopen */
static void* DGExportLookup(uint32_t idx, const char *sym){
    const struct mach_header_64 *mh=(const struct mach_header_64 *)_dyld_get_image_header(idx);
    if(!mh || mh->magic!=MH_MAGIC_64) return NULL;
    uint64_t slide=_dyld_get_image_vmaddr_slide(idx);
    const uint8_t *cs=(const uint8_t*)mh+sizeof(struct mach_header_64);
    const uint8_t *sgBase=cs;
    for(uint32_t i=0;i<mh->ncmds;i++){
        const struct load_command *lc=(const struct load_command*)cs;
        if(lc->cmd==LC_DYLD_INFO || lc->cmd==LC_DYLD_INFO_ONLY){
            const struct dyld_info_command *di=(const struct dyld_info_command*)lc;
            if(di->export_size==0) return NULL;
            const uint8_t *sg=sgBase;
            uint64_t va=0;
            for(uint32_t j=0;j<mh->ncmds;j++){
                const struct load_command *l2=(const struct load_command*)sg;
                if(l2->cmd==LC_SEGMENT_64){
                    const struct segment_command_64 *seg=(const struct segment_command_64*)sg;
                    if(di->export_off>=seg->fileoff && di->export_off<seg->fileoff+seg->filesize){
                        va=seg->vmaddr+(di->export_off-seg->fileoff)+slide;
                        break;
                    }
                }
                sg+=l2->cmdsize;
            }
            if(!va) return NULL;
            const uint8_t *trie=(const uint8_t*)(uintptr_t)va;
            void *out=NULL;
            DGTrieNode(trie,trie,trie+di->export_size,sym,"",slide,&out);
            return out;
        }
        cs+=lc->cmdsize;
    }
    return NULL;
}

/* ===== حالة التشخيص ===== */
static unsigned DGImagesScanned=0;
static char DGHitImage[128]="";
static char DGDiagShort[64]="—";
static NSString *DGLastDiag=nil;

static void DGResolveOne(uint32_t idx, const char *name, void **slot){
    void *p=DGExportLookup(idx,name);
    if(!p){
        const char *path=_dyld_get_image_name(idx);
        void *h=path?dlopen(path,RTLD_NOLOAD|RTLD_LAZY):NULL;
        if(h) p=dlsym(h,name);
    }
    if(p) *slot=p;
}

/* الحل الرئيسي: شجرة التصدير أولاً ثم dlsym لأي نقص — مع بدائل يدوية لاحقاً */
static void DGResolveIL2CPP(void){
    if(DGIL2CPP.available) return;
    memset(&DGIL2CPP,0,sizeof(DGIL2CPP));
    uint32_t count=_dyld_image_count();
    DGImagesScanned=count;
    for(uint32_t i=0;i<count;i++){
        void *probe=DGExportLookup(i,"il2cpp_domain_get");
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
        snprintf(DGDiagShort,sizeof(DGDiagShort),"لا رمز | صور:%u",count);
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

/* كتابة ملف تشخيص يحدد مكان رموز IL2CPP بدقة */
static void DGWriteDiag(void){
    NSMutableString *m=[NSMutableString string];
    [m appendFormat:@"DeltaGuard IL2CPP diag | %@\n",[NSDate date]];
    [m appendFormat:@"available=%d | %s | hit=%s | images=%u\n",DGIL2CPP.available,DGDiagShort,DGHitImage,DGImagesScanned];
    uint32_t c=_dyld_image_count();
    for(uint32_t i=0;i<c;i++){
        const char *p=_dyld_get_image_name(i);
        if(!p) continue;
        if(!strstr(p,"elta") && !strstr(p,"Unity") && !strstr(p,"il2cpp") && !strstr(p,"GameAssembly") && !strstr(p,"ramework") && !strstr(p,"rameworks")) continue;
        void *s=DGExportLookup(i,"il2cpp_domain_get");
        [m appendFormat:@"%s -> %s\n",p,s?"IL2CPP_EXPORT ✅":"—"];
    }
    NSString *state=[m copy];
    if(DGLastDiag && [state isEqualToString:DGLastDiag]) return;
    DGLastDiag=state;
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"deltaguard_il2cpp_diag.txt"];
    [m writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    CGFloat size=self.dgMinimized?30:52;
    DGCancelIdle();
    DGHaptic();
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0 animations:^{
        self.frame=CGRectMake(self.center.x-size/2,self.center.y-size/2,size,size);
        self.layer.cornerRadius=size/2;
        self.titleLabel.font=[UIFont systemFontOfSize:self.dgMinimized?13:22];
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

    CGRect btnFrame=CGRectMake(20,140,52,52);
    DGRestoreButtonPos(&btnFrame);
    DGButton=[DGFloatButton buttonWithType:UIButtonTypeCustom];
    DGButton.frame=btnFrame;
    DGButton.layer.cornerRadius=26;
    DGButton.backgroundColor=[UIColor colorWithWhite:0.05 alpha:0.9];
    DGButton.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGButton.layer.borderWidth=2;
    DGButton.clipsToBounds=YES;
    [DGButton setTitle:@"🛡" forState:UIControlStateNormal];
    DGButton.titleLabel.font=[UIFont systemFontOfSize:22];
    [DGButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgLongPress:)];
    hold.minimumPressDuration=0.3;
    [DGButton addGestureRecognizer:hold];
    UITapGestureRecognizer *dt=[[UITapGestureRecognizer alloc] initWithTarget:DGButton action:@selector(dgDoubleTap:)];
    dt.numberOfTapsRequired=2;
    [DGButton addGestureRecognizer:dt];
    [root addSubview:DGButton];
    DGScheduleIdle();

    /* حبة إحداثيات مصغّرة تظهر أعلى الشاشة أثناء التدريب فقط — لا تعيق اللعب */
    DGCoordPill=[[UILabel alloc] initWithFrame:CGRectMake(0,54,220,26)];
    DGCoordPill.center=CGPointMake([UIScreen mainScreen].bounds.size.width/2,DGCoordPill.center.y);
    DGCoordPill.backgroundColor=[UIColor colorWithWhite:0.0 alpha:0.55];
    DGCoordPill.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGCoordPill.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    DGCoordPill.textAlignment=NSTextAlignmentCenter;
    DGCoordPill.layer.cornerRadius=13;
    DGCoordPill.clipsToBounds=YES;
    DGCoordPill.hidden=YES;
    DGCoordPill.userInteractionEnabled=NO;
    [root addSubview:DGCoordPill];

    /* طبقة خطوط الكشف التجريبية — شفافة تماماً ولا تستقبل أي لمس */
    DGEspView=[[DGEspDebugView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DGEspView.backgroundColor=[UIColor clearColor];
    DGEspView.opaque=NO;
    DGEspView.userInteractionEnabled=NO;
    [root addSubview:DGEspView];

    CGRect panelFrame=CGRectMake(50,180,280,372);
    NSString *ps=[[NSUserDefaults standardUserDefaults] stringForKey:DGPanelPosKey];
    if(ps){
        CGPoint o=CGPointFromString(ps);
        if(o.x>=0 && o.y>=0) panelFrame=(CGRect){o,panelFrame.size};
    }
    DGPanel=[[UIView alloc] initWithFrame:panelFrame];
    DGPanel.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.92];
    DGPanel.layer.cornerRadius=14;
    DGPanel.layer.borderColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1].CGColor;
    DGPanel.layer.borderWidth=1.5;
    DGPanel.hidden=YES;

    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(30,10,220,24)];
    title.text=@"🛡 حارس دلتا — أداة العملية";
    title.textColor=[UIColor whiteColor]; title.textAlignment=NSTextAlignmentCenter; title.font=[UIFont boldSystemFontOfSize:14];
    title.userInteractionEnabled=YES;
    UIPanGestureRecognizer *panelPan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dgPanelPan:)];
    [title addGestureRecognizer:panelPan];
    [DGPanel addSubview:title];

    UIButton *closeB=[UIButton buttonWithType:UIButtonTypeSystem];
    closeB.frame=CGRectMake(246,6,26,28);
    [closeB setTitle:@"✕" forState:UIControlStateNormal];
    closeB.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    closeB.tintColor=[UIColor lightGrayColor];
    [closeB addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [DGPanel addSubview:closeB];

    DGStatsLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,38,260,44)];
    DGStatsLabel.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGStatsLabel.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    DGStatsLabel.numberOfLines=2;
    DGStatsLabel.textAlignment=NSTextAlignmentCenter;
    [DGPanel addSubview:DGStatsLabel];

    DG90Button=[UIButton buttonWithType:UIButtonTypeSystem];
    DG90Button.frame=CGRectMake(20,86,240,30);
    [DG90Button addTarget:self action:@selector(toggle90) forControlEvents:UIControlEventTouchUpInside];
    [self update90Button];
    [DGPanel addSubview:DG90Button];

    /* ===== قسم استكشاف الكائنات — المرحلة 1 ===== */
    UILabel *discTitle=[[UILabel alloc] initWithFrame:CGRectMake(10,120,260,16)];
    discTitle.text=@"🔍 استكشاف الكائنات — المرحلة 1";
    discTitle.textColor=[UIColor colorWithRed:0.2 green:0.85 blue:1 alpha:1];
    discTitle.font=[UIFont boldSystemFontOfSize:11];
    discTitle.textAlignment=NSTextAlignmentCenter;
    [DGPanel addSubview:discTitle];

    DGSceneLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,138,260,16)];
    DGSceneLabel.textColor=[UIColor whiteColor];
    DGSceneLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    DGSceneLabel.textAlignment=NSTextAlignmentCenter;
    [DGPanel addSubview:DGSceneLabel];

    DGCoordLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,154,260,18)];
    DGCoordLabel.textColor=[UIColor colorWithRed:0.4 green:1 blue:0.6 alpha:1];
    DGCoordLabel.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    DGCoordLabel.textAlignment=NSTextAlignmentCenter;
    [DGPanel addSubview:DGCoordLabel];

    DGCandidatesLabel=[[UILabel alloc] initWithFrame:CGRectMake(10,174,260,72)];
    DGCandidatesLabel.textColor=[UIColor lightGrayColor];
    DGCandidatesLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    DGCandidatesLabel.numberOfLines=5;
    DGCandidatesLabel.textAlignment=NSTextAlignmentLeft;
    DGCandidatesLabel.adjustsFontSizeToFitWidth=NO;
    [DGPanel addSubview:DGCandidatesLabel];

    DGTrainingButton=[UIButton buttonWithType:UIButtonTypeSystem];
    DGTrainingButton.frame=CGRectMake(20,250,240,28);
    [DGTrainingButton addTarget:self action:@selector(toggleTraining) forControlEvents:UIControlEventTouchUpInside];
    [self updateTrainingButton];
    [DGPanel addSubview:DGTrainingButton];

    DGDebugButton=[UIButton buttonWithType:UIButtonTypeSystem];
    DGDebugButton.frame=CGRectMake(20,282,240,28);
    [DGDebugButton addTarget:self action:@selector(toggleDebug) forControlEvents:UIControlEventTouchUpInside];
    [self updateDebugButton];
    [DGPanel addSubview:DGDebugButton];
    /* ===== نهاية قسم الاستكشاف ===== */

    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,314,260,26)];
    hint.text=@"اضغط مطولاً للسحب • نقرة للفتح • نقرتان للتصغير";
    hint.textColor=[UIColor lightGrayColor]; hint.textAlignment=NSTextAlignmentCenter; hint.font=[UIFont systemFontOfSize:10];
    hint.numberOfLines=1;
    [DGPanel addSubview:hint];

    UILabel *ver=[[UILabel alloc] initWithFrame:CGRectMake(196,346,66,16)];
    ver.text=@"v0.5.2-stage1";
    ver.textColor=[UIColor lightGrayColor]; ver.textAlignment=NSTextAlignmentRight; ver.font=[UIFont systemFontOfSize:9]; ver.alpha=0.6;
    [DGPanel addSubview:ver];

    [root addSubview:DGPanel];
    DGLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    [DGLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DGStatsTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateStats) userInfo:nil repeats:YES];
    DGDiscoveryTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateDiscovery) userInfo:nil repeats:YES];
    [DGStatsLabel setText:[self statsText]];
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

+ (void)toggle90{
    DG90Enabled=!DG90Enabled;
    [[NSUserDefaults standardUserDefaults] setBool:DG90Enabled forKey:DG90Key];
    [self update90Button];
    [DGStatsLabel setText:[self statsText]];
}

+ (void)update90Button{
    NSString *title;
    UIColor *color=[UIColor labelColor];
    if(!DG90Enabled) title=@"⚡ تفعيل 90 FPS";
    else if(DGCanUnlock()){ title=@"⚡ 90 FPS: مفعّل ✅"; color=[UIColor systemGreenColor]; }
    else { title=@"⚡ 90 FPS: غير متاح — شاشتك 60Hz"; color=[UIColor systemYellowColor]; }
    [DG90Button setTitle:title forState:UIControlStateNormal];
    DG90Button.tintColor=color;
}

/* ===== المرحلة 1: منطق الاستكشاف ===== */

+ (void)toggleTraining{
    DGForceTraining=!DGForceTraining;
    [[NSUserDefaults standardUserDefaults] setBool:DGForceTraining forKey:DGForceTrainingKey];
    [self updateTrainingButton];
    [self updateDiscovery];
}

+ (void)updateTrainingButton{
    NSString *title=DGForceTraining?@"🎯 وضع التدريب: مفعّل يدوياً":@"🎯 وضع التدريب: تلقائي (حسب المشهد)";
    UIColor *color=DGForceTraining?[UIColor systemGreenColor]:[UIColor labelColor];
    [DGTrainingButton setTitle:title forState:UIControlStateNormal];
    DGTrainingButton.tintColor=color;
}

+ (void)toggleDebug{
    DGDebugLines=!DGDebugLines;
    [[NSUserDefaults standardUserDefaults] setBool:DGDebugLines forKey:DGDebugLinesKey];
    [self updateDebugButton];
    if(!DGDebugLines && DGEspView) [DGEspView setNeedsDisplay];
}

+ (void)updateDebugButton{
    NSString *title=DGDebugLines?@"📐 خطوط الكشف: مفعّلة ✅":@"📐 خطوط الكشف (تجربة): معطّلة";
    UIColor *color=DGDebugLines?[UIColor systemGreenColor]:[UIColor labelColor];
    [DGDebugButton setTitle:title forState:UIControlStateNormal];
    DGDebugButton.tintColor=color;
}

+ (void)updateDiscovery{
    if(!DGPanel && !DGCoordPill) return;

    /* (1) حالة IL2CPP + كتابة التشخيص عند كل تغير */
    DGResolveIL2CPP();
    DGWriteDiag();

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
            DGSceneLabel.text=[NSString stringWithFormat:@"IL2CPP: غير متاح | %s",DGDiagShort];
        } else if(!scene || scene.length==0){
            DGSceneLabel.text=[NSString stringWithFormat:@"IL2CPP ✅ (%zu assembly) | المشهد: …",DGIL2CPP.assemblies];
        } else {
            DGSceneLabel.text=[NSString stringWithFormat:@"IL2CPP ✅ (%zu assembly) | المشهد: %@%@",DGIL2CPP.assemblies,scene,training?@" 🎯":@""];
        }
    }

    if(DGCandidatesLabel){
        if(!DGIL2CPP.available){
            DGCandidatesLabel.text=@"IL2CPP غير متاح — الماسك الحالي لا يرى الرموز";
        } else if(!DGCandidatesScanned){
            DGCandidatesLabel.text=@"فحص الكلاسات المرشحة: جارٍ…";
        } else if(DGCandidateClasses.count==0){
            DGCandidatesLabel.text=@"لا كلاسات مرشحة بعد — أضف كلمات مفتاحية في DGNameMatches";
        } else {
            NSMutableString *ms=[NSMutableString stringWithFormat:@"كلاسات مرشحة (%lu):\n",(unsigned long)DGCandidateClasses.count];
            NSUInteger max=MIN(DGCandidateClasses.count,4);
            for(NSUInteger i=0;i<max;i++) [ms appendFormat:@"• %@\n",DGCandidateClasses[i]];
            if(DGCandidateClasses.count>4) [ms appendFormat:@"… +%lu أخرى",(unsigned long)(DGCandidateClasses.count-4)];
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
