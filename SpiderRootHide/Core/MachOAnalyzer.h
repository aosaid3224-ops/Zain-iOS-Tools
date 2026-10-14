#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MachOParseStatus) {
    MachOParseNotAttempted = 0,
    MachOParseSuccess = 1,
    MachOParsePartial = 2,
    MachOParseFailed = 3
};

@interface MachOSlice : NSObject
@property (nonatomic, assign) uint32_t cputype;
@property (nonatomic, assign) uint32_t cpusubtype;
@property (nonatomic, assign) uint64_t offset;
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) NSString *architectureName;
@property (nonatomic, assign) BOOL encrypted;
@property (nonatomic, assign) uint32_t encryptionID;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MachODependency : NSObject
@property (nonatomic, strong) NSString *rawInstallName;
@property (nonatomic, assign) BOOL isWeak;
@property (nonatomic, strong) NSString *sourceExecutablePath;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MachORPath : NSObject
@property (nonatomic, strong) NSString *rawPath;
@property (nonatomic, strong) NSString *sourceExecutablePath;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MachOLoadCommand : NSObject
@property (nonatomic, assign) uint32_t cmd;
@property (nonatomic, assign) uint32_t cmdsize;
@property (nonatomic, strong) NSString *cmdDescription;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MachOAnalysisResult : NSObject
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) uint32_t magic;
@property (nonatomic, strong) NSString *magicName;
@property (nonatomic, assign) uint32_t machOType;
@property (nonatomic, strong) NSString *machOTypeName;
@property (nonatomic, strong) NSArray<MachOSlice *> *slices;
@property (nonatomic, strong) NSArray<MachODependency *> *dependencies;
@property (nonatomic, strong) NSArray<MachORPath *> *rpaths;
@property (nonatomic, strong) NSArray<MachOLoadCommand *> *loadCommands;
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) NSString *minOSVersion;
@property (nonatomic, strong) NSString *sdkVersion;
@property (nonatomic, assign) uint32_t platform;
@property (nonatomic, strong) NSString *platformName;
@property (nonatomic, assign) BOOL hasCodeSignature;
@property (nonatomic, assign) BOOL hasEncryptedSlice;
@property (nonatomic, assign) uint32_t encryptedSliceCount;
@property (nonatomic, assign) BOOL hasEncryptedArm64Slice;
@property (nonatomic, assign) uint32_t encryptedArm64SliceCount;
@property (nonatomic, assign) uint32_t codeSignatureOffset;
@property (nonatomic, assign) uint32_t codeSignatureSize;
@property (nonatomic, assign) MachOParseStatus parseStatus;
@property (nonatomic, strong) NSString *parseError;
@property (nonatomic, strong) NSString *source;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface MachOAnalyzer : NSObject
+ (instancetype)sharedAnalyzer;
- (MachOAnalysisResult *)analyzeFileAtPath:(NSString *)path;
@end
