#import "IPAExportManager.h"
#import "SPRootHide.h"
#import "RootlessManager.h"
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <libkern/OSByteOrder.h>
#import "RuntimeEnvironment.h"

extern char **environ;

static NSString *IPAExportErrorDomain = @"com.aosaid.ipainstallerpro.export";

@interface IPAExportManager ()
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *mvPath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *zipPath;
@property (nonatomic, strong) NSString *shellPath;
@property (nonatomic, strong) NSString *fouldecryptPath;
@property (nonatomic, strong) NSString *flexdecryptPath;
@property (nonatomic, strong) NSString *modernDecryptPath;
@property (nonatomic, strong) NSString *unzipPath;
@property (nonatomic, strong, nullable) NSString *helperPath;
@end

@implementation IPAExportManager

+ (instancetype)sharedManager {
    static IPAExportManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        RootlessManager *rootless = [RootlessManager sharedManager];
        _cpPath = [rootless resolvePath:@"/bin/cp"];
        _mvPath = [rootless resolvePath:@"/bin/mv"];
        _chmodPath = [rootless resolvePath:@"/usr/bin/chmod"];
        _rmPath = [rootless resolvePath:@"/bin/rm"];
        _zipPath = [rootless resolvePath:@"/usr/bin/zip"];
        _shellPath = [rootless resolvePath:@"/bin/sh"];
        _fouldecryptPath = [rootless resolvePath:@"/usr/local/bin/fouldecrypt"];
        _flexdecryptPath = [rootless resolvePath:@"/usr/local/bin/flexdecrypt2"];
        _modernDecryptPath = [rootless resolvePath:@"/usr/local/bin/ipadecrypt-helper"];
        _unzipPath = [rootless resolvePath:@"/usr/bin/unzip"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:_shellPath]) _shellPath = @"/bin/sh";

        RuntimeEnvironment *rt = [RuntimeEnvironment sharedEnvironment];
        NSMutableArray<NSString *> *helperCandidates = [NSMutableArray arrayWithObjects:
            [rootless resolvePath:@"/usr/bin/ipainstallerpro_helper"],
            @"/usr/bin/ipainstallerpro_helper",
            nil];
        if (rt.bootstrapPath) {
            [helperCandidates addObject:[rt.bootstrapPath stringByAppendingPathComponent:@"usr/bin/ipainstallerpro_helper"]];
        } else {
            [helperCandidates addObject:@"/var/jb/usr/bin/ipainstallerpro_helper"];
        }
        for (NSString *candidate in helperCandidates) {
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
                _helperPath = candidate;
                break;
            }
        }
    }
    return self;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:IPAExportErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: description ?: @"تعذر استخراج IPA"}];
}

- (BOOL)isDirectoryWithoutSymlinkAtPath:(NSString *)path {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return NO;
    return S_ISDIR(st.st_mode);
}

- (BOOL)runCommand:(NSString *)command
              args:(NSArray<NSString *> *)args
    workingDirectory:(NSString *)workingDirectory
              error:(NSError **)error {
    if (command.length == 0 || ![[NSFileManager defaultManager] isExecutableFileAtPath:command]) {
        if (error) *error = [self errorWithCode:10 description:@"الأداة المطلوبة غير موجودة أو غير قابلة للتنفيذ"];
        return NO;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    NSString *spawnCommand = command;
    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:command];
    if (workingDirectory.length > 0) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:self.shellPath]) {
            posix_spawn_file_actions_destroy(&actions);
            if (error) *error = [self errorWithCode:11 description:@"أداة تشغيل الأوامر غير متاحة للأرشفة"];
            return NO;
        }
        spawnCommand = self.shellPath;
        argvStrings = [NSMutableArray arrayWithObjects:self.shellPath,
                       @"-c", @"cd \"$1\" && shift && exec \"$@\"",
                       @"ipa-export", SPToolPathForTool(self.shellPath, workingDirectory), SPToolPathForTool(self.shellPath, command), nil];
        [argvStrings addObjectsFromArray:SPToolArguments(command, args ?: @[])];
    } else {
        [argvStrings addObjectsFromArray:SPToolArguments(command, args ?: @[])];
    }

    char **argv = calloc(argvStrings.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = (char *)argvStrings[i].fileSystemRepresentation;
    argv[argvStrings.count] = NULL;

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, spawnCommand.fileSystemRepresentation, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    if (spawnStatus != 0) {
        if (error) *error = [self errorWithCode:12 description:[NSString stringWithFormat:@"تعذر تشغيل الأداة (errno=%d)", spawnStatus]];
        return NO;
    }

    int waitStatus = 0;
    if (waitpid(pid, &waitStatus, 0) < 0 || !WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) {
        if (error) *error = [self errorWithCode:13 description:[NSString stringWithFormat:@"فشلت الأداة (exit=%d)", WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1]];
        return NO;
    }
    return YES;
}

- (BOOL)runPrivilegedCommand:(NSString *)command
                         args:(NSArray<NSString *> *)args
                         error:(NSError **)error {
    if (self.helperPath.length == 0) {
        if (error) *error = [self errorWithCode:20 description:@"لا يتوفر root helper لفك تشفير التطبيق أو تعديل ملفاته"];
        return NO;
    }
    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObjects:self.helperPath, command, nil];
    [argvStrings addObjectsFromArray:SPToolArguments(command, args ?: @[])];
    char **argv = calloc(argvStrings.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = (char *)argvStrings[i].fileSystemRepresentation;
    argv[argvStrings.count] = NULL;

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, self.helperPath.fileSystemRepresentation, NULL, NULL, argv, environ);
    free(argv);
    if (spawnStatus != 0) {
        if (error) *error = [self errorWithCode:21 description:[NSString stringWithFormat:@"تعذر تشغيل root helper (errno=%d)", spawnStatus]];
        return NO;
    }
    int waitStatus = 0;
    if (waitpid(pid, &waitStatus, 0) < 0) {
        if (error) *error = [self errorWithCode:22 description:[NSString stringWithFormat:@"فشل انتظار root helper (errno=%d)", errno]];
        return NO;
    }
    if (WIFSIGNALED(waitStatus)) {
        if (error) *error = [self errorWithCode:23 description:[NSString stringWithFormat:@"توقّف root helper بإشارة %d أثناء تشغيل الأداة", WTERMSIG(waitStatus)]];
        return NO;
    }
    if (!WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) {
        if (error) *error = [self errorWithCode:24 description:[NSString stringWithFormat:@"فشل root helper (exit=%d)", WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1]];
        return NO;
    }
    return YES;
}

- (uint32_t)readUInt32:(const uint8_t *)bytes offset:(size_t)offset swapped:(BOOL)swapped {
    uint32_t value = 0;
    memcpy(&value, bytes + offset, sizeof(value));
    return swapped ? OSSwapInt32(value) : value;
}

- (BOOL)parseMachOBytes:(const uint8_t *)bytes length:(size_t)length encrypted:(BOOL *)encrypted {
    if (length < sizeof(uint32_t)) return NO;
    uint32_t magic = 0;
    memcpy(&magic, bytes, sizeof(magic));
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        BOOL swapped = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        BOOL fat64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        if (length < 8) return NO;
        uint32_t count = [self readUInt32:bytes offset:4 swapped:swapped];
        size_t archSize = fat64 ? 32 : 20;
        if (count > 128 || 8 + (size_t)count * archSize > length) return NO;
        BOOL found = NO;
        for (uint32_t i = 0; i < count; i++) {
            size_t off = 8 + (size_t)i * archSize;
            uint64_t sliceOffset = fat64
                ? ((uint64_t)[self readUInt32:bytes offset:off + 8 swapped:swapped] << 32) | [self readUInt32:bytes offset:off + 12 swapped:swapped]
                : [self readUInt32:bytes offset:off + 8 swapped:swapped];
            uint64_t sliceSize = fat64
                ? ((uint64_t)[self readUInt32:bytes offset:off + 16 swapped:swapped] << 32) | [self readUInt32:bytes offset:off + 20 swapped:swapped]
                : [self readUInt32:bytes offset:off + 12 swapped:swapped];
            if (sliceOffset >= length || sliceSize > length - sliceOffset) continue;
            BOOL sliceEncrypted = NO;
            if ([self parseMachOBytes:bytes + sliceOffset length:(size_t)sliceSize encrypted:&sliceEncrypted]) {
                found = YES;
                if (sliceEncrypted && encrypted) *encrypted = YES;
            }
        }
        return found;
    }

    BOOL swapped = NO;
    BOOL is64 = NO;
    if (magic == MH_MAGIC_64) is64 = YES;
    else if (magic == MH_MAGIC) is64 = NO;
    else if (magic == MH_CIGAM_64) { is64 = YES; swapped = YES; }
    else if (magic == MH_CIGAM) { is64 = NO; swapped = YES; }
    else return NO;

    size_t headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (length < headerSize) return NO;
    uint32_t ncmds = [self readUInt32:bytes offset:16 swapped:swapped];
    uint32_t sizeofcmds = [self readUInt32:bytes offset:20 swapped:swapped];
    if (ncmds > 4096 || sizeofcmds > length - headerSize) return NO;
    size_t cursor = headerSize;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (cursor + 8 > length) return NO;
        uint32_t cmd = [self readUInt32:bytes offset:cursor swapped:swapped];
        uint32_t cmdsize = [self readUInt32:bytes offset:cursor + 4 swapped:swapped];
        if (cmdsize < 8 || cursor + cmdsize > length) return NO;
        uint32_t baseCmd = cmd & ~LC_REQ_DYLD;
        if ((baseCmd == LC_ENCRYPTION_INFO || baseCmd == LC_ENCRYPTION_INFO_64) && cmdsize >= 20) {
            uint32_t cryptid = [self readUInt32:bytes offset:cursor + 16 swapped:swapped];
            if (cryptid != 0 && encrypted) *encrypted = YES;
        }
        cursor += cmdsize;
    }
    return YES;
}

- (BOOL)isMachOAtPath:(NSString *)path encrypted:(BOOL *)encrypted {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 4) return NO;
    BOOL value = NO;
    BOOL result = [self parseMachOBytes:data.bytes length:data.length encrypted:&value];
    if (encrypted) *encrypted = value;
    return result;
}

- (NSArray<NSString *> *)machOPathsInBundle:(NSString *)bundlePath encrypted:(NSMutableArray<NSString *> *)encryptedPaths {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        NSString *path = [bundlePath stringByAppendingPathComponent:relative];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        BOOL encrypted = NO;
        if ([self isMachOAtPath:path encrypted:&encrypted]) {
            [paths addObject:path];
            if (encrypted && encryptedPaths) [encryptedPaths addObject:path];
        }
    }
    return paths;
}

- (BOOL)normalizeMachOPermissions:(NSArray<NSString *> *)machOPaths error:(NSError **)error {
    for (NSString *path in machOPaths) {
        struct stat st;
        mode_t mode = 0755;
        if (stat(path.fileSystemRepresentation, &st) == 0) mode = st.st_mode | 0755;
        if (chmod(path.fileSystemRepresentation, mode) != 0 && ![self runPrivilegedCommand:self.chmodPath args:@[[NSString stringWithFormat:@"%o", mode & 0777], path] error:error]) return NO;
    }
    return YES;
}

- (BOOL)removeCodeSignaturesFromBundle:(NSString *)bundlePath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *signatureDirectories = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        if ([relative.lastPathComponent isEqualToString:@"_CodeSignature"]) {
            [signatureDirectories addObject:[bundlePath stringByAppendingPathComponent:relative]];
            [enumerator skipDescendants];
        }
    }
    for (NSString *path in signatureDirectories) {
        if (![fm removeItemAtPath:path error:nil] && ![self runPrivilegedCommand:self.rmPath args:@[@"-rf", path] error:error]) return NO;
    }
    return YES;
}

- (void)exportApplicationAtPath:(NSString *)bundlePath
                  suggestedName:(NSString *)suggestedName
                     completion:(IPAExportCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *error = nil;
        NSString *workDirectory = nil;
        NSURL *resultURL = nil;
        @try {
            if (bundlePath.length == 0 || ![self isDirectoryWithoutSymlinkAtPath:bundlePath]) {
                error = [self errorWithCode:1 description:@"مسار التطبيق غير صالح أو غير متاح للقراءة"];
            }
            NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = error ? nil : [NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *executableName = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? info[@"CFBundleExecutable"] : nil;
            if (!error && (info.count == 0 || executableName.length == 0)) error = [self errorWithCode:2 description:@"Info.plist أو executable غير صالح"];
            NSString *executablePath = executableName.length > 0 ? [bundlePath stringByAppendingPathComponent:executableName] : nil;
            if (!error && ![fm isReadableFileAtPath:executablePath]) error = [self errorWithCode:3 description:@"executable الرئيسي غير موجود أو غير قابل للقراءة"];
            if (!error && ![fm isExecutableFileAtPath:self.zipPath]) error = [self errorWithCode:4 description:@"أداة zip غير مثبتة؛ لا يمكن إنشاء IPA"];

            if (!error) {
                NSString *uuid = [NSUUID UUID].UUIDString;
                workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"IPAExport-%@", uuid]];
                NSString *payloadDirectory = [workDirectory stringByAppendingPathComponent:@"Payload"];
                if (![fm createDirectoryAtPath:payloadDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
                    if (!error) error = [self errorWithCode:5 description:@"تعذر إنشاء مساحة مؤقتة للتصدير"];
                }
                NSString *bundleName = bundlePath.lastPathComponent;
                NSString *copiedBundle = [payloadDirectory stringByAppendingPathComponent:bundleName];
                if (!error && ![self runCommand:self.cpPath args:@[@"-Rp", bundlePath, copiedBundle] workingDirectory:nil error:&error]) {
                    if (!error) error = [self errorWithCode:6 description:@"فشل نسخ التطبيق إلى مساحة التصدير"];
                }

                NSMutableArray<NSString *> *encryptedPaths = [NSMutableArray array];
                NSArray<NSString *> *machOPaths = error ? @[] : [self machOPathsInBundle:copiedBundle encrypted:encryptedPaths];
                BOOL decryptedAny = NO;
                if (!error && encryptedPaths.count > 0) {
                    if (self.helperPath.length == 0) {
                        error = [self errorWithCode:24 description:@"هذا التطبيق يحتوي Mach-O مشفرًا، لكن root helper غير متاح لفك تشفيره بأمان."];
                    } else {
                        BOOL modernDecrypted = NO;
                        NSError *modernError = nil;
                        NSString *bundleIdentifier = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : @"";
                        if ([fm isExecutableFileAtPath:self.modernDecryptPath] && bundleIdentifier.length > 0) {
                            NSString *modernIPA = [workDirectory stringByAppendingPathComponent:@"decrypted-modern.ipa"];
                            NSString *modernExtract = [workDirectory stringByAppendingPathComponent:@"decrypted-modern"];
                            [fm removeItemAtPath:modernIPA error:nil];
                            [fm removeItemAtPath:modernExtract error:nil];
                            if ([self runPrivilegedCommand:self.modernDecryptPath args:@[@"decrypt", bundleIdentifier, bundlePath, modernIPA] error:&modernError]) {
                                if ([fm createDirectoryAtPath:modernExtract withIntermediateDirectories:YES attributes:nil error:&modernError] &&
                                    [self runCommand:self.unzipPath args:@[@"-q", modernIPA, @"-d", modernExtract] workingDirectory:nil error:&modernError]) {
                                    NSString *modernBundle = [[modernExtract stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:bundleName];
                                    NSDictionary *modernBundleAttrs = [fm attributesOfItemAtPath:modernBundle error:nil];
                                    if ([modernBundleAttrs[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                                        if (![fm removeItemAtPath:copiedBundle error:&modernError]) {
                                            [self runPrivilegedCommand:self.rmPath args:@[@"-rf", copiedBundle] error:nil];
                                        }
                                        if ([fm moveItemAtPath:modernBundle toPath:copiedBundle error:&modernError]) modernDecrypted = YES;
                                    }
                                }
                            }
                            if (modernDecrypted) decryptedAny = YES;
                        }

                        if (!modernDecrypted) {
                            for (NSString *sourcePath in encryptedPaths) {
                                NSString *decryptedPath = [sourcePath stringByAppendingString:@".decrypted"];
                                NSError *firstToolError = modernError;
                                BOOL decrypted = NO;
                                [fm removeItemAtPath:decryptedPath error:nil];

                                if ([fm isExecutableFileAtPath:self.fouldecryptPath]) {
                                    NSError *toolError = nil;
                                    decrypted = [self runPrivilegedCommand:self.fouldecryptPath args:@[sourcePath, decryptedPath] error:&toolError];
                                    if (!decrypted && !firstToolError) firstToolError = toolError;
                                }

                                if (!decrypted && [fm isExecutableFileAtPath:self.flexdecryptPath]) {
                                    NSString *flexOutput = [NSTemporaryDirectory() stringByAppendingPathComponent:sourcePath.lastPathComponent];
                                    [fm removeItemAtPath:flexOutput error:nil];
                                    NSError *toolError = nil;
                                    decrypted = [self runPrivilegedCommand:self.flexdecryptPath args:@[sourcePath] error:&toolError];
                                    if (decrypted && [fm fileExistsAtPath:flexOutput]) decrypted = [fm moveItemAtPath:flexOutput toPath:decryptedPath error:&toolError];
                                    if (!decrypted && !firstToolError) firstToolError = toolError;
                                }

                                BOOL stillEncrypted = NO;
                                NSDictionary *attrs = [fm attributesOfItemAtPath:decryptedPath error:nil];
                                if (!decrypted || ![fm isReadableFileAtPath:decryptedPath] || [attrs[@"NSFileSize"] unsignedLongLongValue] == 0 || ![self isMachOAtPath:decryptedPath encrypted:&stillEncrypted] || stillEncrypted) {
                                    NSString *reason = firstToolError.localizedDescription ?: @"لم تتوفر أداة فك تشفير صالحة";
                                    error = [self errorWithCode:25 description:[NSString stringWithFormat:@"تعذر فك تشفير %@: %@", sourcePath.lastPathComponent, reason]];
                                    break;
                                }
                                if (![self runPrivilegedCommand:self.mvPath args:@[@"-f", decryptedPath, sourcePath] error:&error]) break;
                                decryptedAny = YES;
                            }
                        }

                        if (!error && decryptedAny) {
                            NSMutableArray<NSString *> *remainingEncrypted = [NSMutableArray array];
                            [self machOPathsInBundle:copiedBundle encrypted:remainingEncrypted];
                            if (remainingEncrypted.count > 0) {
                                error = [self errorWithCode:28 description:[NSString stringWithFormat:@"بقيت %lu ملفات Mach-O مشفرة بعد فك الحزمة", (unsigned long)remainingEncrypted.count]];
                            }
                        }
                    }
                }

                if (!error) {
                    machOPaths = [self machOPathsInBundle:copiedBundle encrypted:NULL];
                    if (![self normalizeMachOPermissions:machOPaths error:&error]) {
                        if (!error) error = [self errorWithCode:26 description:@"تعذر إصلاح صلاحيات ملفات Mach-O"];
                    }
                }
                if (!error && decryptedAny && ![self removeCodeSignaturesFromBundle:copiedBundle error:&error]) {
                    if (!error) error = [self errorWithCode:27 description:@"تعذر إزالة التواقيع القديمة بعد فك التشفير"];
                }

                NSString *copiedInfoPath = [copiedBundle stringByAppendingPathComponent:@"Info.plist"];
                NSString *copiedExecutablePath = executableName.length > 0 ? [copiedBundle stringByAppendingPathComponent:executableName] : nil;
                if (!error && (![fm fileExistsAtPath:copiedInfoPath] || ![fm isReadableFileAtPath:copiedExecutablePath])) error = [self errorWithCode:7 description:@"فشل التحقق من النسخة قبل إنشاء IPA"];

                NSString *safeName = suggestedName.length > 0 ? suggestedName : (info[@"CFBundleIdentifier"] ?: bundleName.stringByDeletingPathExtension);
                safeName = [safeName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
                safeName = [safeName stringByReplacingOccurrencesOfString:@"\\" withString:@"-"];
                safeName = [safeName stringByReplacingOccurrencesOfString:@":" withString:@"-"];
                safeName = [safeName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (safeName.length == 0) safeName = @"Application";
                NSString *outputName = [safeName.pathExtension.lowercaseString isEqualToString:@"ipa"] ? safeName : [safeName stringByAppendingPathExtension:@"ipa"];
                NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:outputName];
                NSUInteger collision = 2;
                while ([fm fileExistsAtPath:outputPath]) {
                    NSString *stem = [outputName stringByDeletingPathExtension];
                    outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%lu).ipa", stem, (unsigned long)collision++]];
                }
                if (!error) {
                    BOOL zipped = [self runCommand:self.zipPath args:@[@"-qry", outputPath, @"Payload"] workingDirectory:workDirectory error:&error];
                    NSDictionary *attrs = [fm attributesOfItemAtPath:outputPath error:nil];
                    if (!zipped || ![fm isReadableFileAtPath:outputPath] || [attrs[@"NSFileSize"] unsignedLongLongValue] < 22) {
                        if (!error) error = [self errorWithCode:8 description:@"تم إنشاء أرشيف غير صالح أو فارغ"];
                    } else {
                        resultURL = [NSURL fileURLWithPath:outputPath];
                    }
                }
            }
        } @catch (NSException *exception) {
            error = [self errorWithCode:9 description:[NSString stringWithFormat:@"حدث خطأ أثناء استخراج IPA: %@", exception.reason ?: @"غير معروف"]];
        }
        if (workDirectory.length > 0) [fm removeItemAtPath:workDirectory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(resultURL, error);
        });
    });
}

- (void)cloneApplicationAtPath:(NSString *)bundlePath
                   suggestedName:(NSString *)suggestedName
                 bundleIdentifier:(NSString *)bundleIdentifier
                       completion:(IPAExportCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *cloneURL = nil;
        NSError *error = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *sourceName = suggestedName.length > 0 ? suggestedName : bundlePath.lastPathComponent.stringByDeletingPathExtension;
        NSString *newID = bundleIdentifier;
        NSString *workDirectory = nil;
        @try {
            if (bundlePath.length == 0 || ![self isDirectoryWithoutSymlinkAtPath:bundlePath]) {
                error = [self errorWithCode:40 description:@"مسار التطبيق غير صالح للتكرار"];
            }
            if (!error && newID.length == 0) {
                error = [self errorWithCode:41 description:@"Bundle ID الجديد غير صالح"];
            }
            NSRegularExpression *idRegex = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$" options:0 error:nil];
            if (!error && [idRegex numberOfMatchesInString:newID options:0 range:NSMakeRange(0, newID.length)] == 0) {
                error = [self errorWithCode:42 description:@"Bundle ID الجديد لا يطابق صيغة iOS"];
            }
            NSDictionary *sourceInfo = error ? nil : [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
            NSString *sourceID = [sourceInfo[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? sourceInfo[@"CFBundleIdentifier"] : nil;
            NSString *sourceExecutable = [sourceInfo[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? sourceInfo[@"CFBundleExecutable"] : nil;
            if (!error && (sourceID.length == 0 || [sourceID isEqualToString:newID])) {
                error = [self errorWithCode:43 description:@"Bundle ID التكرار يجب أن يكون مختلفًا عن التطبيق الأصلي"];
            }
            if (!error && sourceExecutable.length == 0) {
                error = [self errorWithCode:44 description:@"Info.plist لا يحتوي executable صالحًا"];
            }

            if (!error) {
                dispatch_semaphore_t exportSemaphore = dispatch_semaphore_create(0);
                __block NSURL *exportedURL = nil;
                __block NSError *exportError = nil;
                [self exportApplicationAtPath:bundlePath suggestedName:sourceName completion:^(NSURL *ipaURL, NSError *exportedError) {
                    exportedURL = ipaURL;
                    exportError = exportedError;
                    dispatch_semaphore_signal(exportSemaphore);
                }];
                dispatch_semaphore_wait(exportSemaphore, DISPATCH_TIME_FOREVER);
                if (!exportedURL || exportError) {
                    error = exportError ?: [self errorWithCode:45 description:@"فشل تجهيز التطبيق قبل التكرار"];
                } else {
                    NSString *uuid = [NSUUID UUID].UUIDString;
                    workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"IPAClone-%@", uuid]];
                    NSString *payloadDirectory = [workDirectory stringByAppendingPathComponent:@"Payload"];
                    if (![fm createDirectoryAtPath:payloadDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
                        if (!error) error = [self errorWithCode:46 description:@"تعذر إنشاء مساحة التكرار"];
                    }
                    if (!error && ![self runCommand:self.unzipPath args:@[@"-q", exportedURL.path, @"-d", workDirectory] workingDirectory:nil error:&error]) {
                        if (!error) error = [self errorWithCode:47 description:@"تعذر فتح IPA المجهز للتكرار"];
                    }
                    NSString *cloneApp = nil;
                    if (!error) {
                        for (NSString *item in [fm contentsOfDirectoryAtPath:payloadDirectory error:nil]) {
                            if ([item.pathExtension.lowercaseString isEqualToString:@"app"]) {
                                cloneApp = [payloadDirectory stringByAppendingPathComponent:item];
                                break;
                            }
                        }
                        if (cloneApp.length == 0) error = [self errorWithCode:48 description:@"لم يتم العثور على التطبيق داخل Payload"];
                    }

                    BOOL (^rewriteInfo)(NSString *, NSString *, NSString *) = ^BOOL(NSString *infoPath, NSString *replacementID, NSString *replacementName) {
                        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
                        if (!dict) return NO;
                        dict[@"CFBundleIdentifier"] = replacementID;
                        if (replacementName.length > 0) {
                            dict[@"CFBundleDisplayName"] = replacementName;
                            dict[@"CFBundleName"] = replacementName;
                        }
                        return [dict writeToFile:infoPath atomically:YES];
                    };

                    if (!error) {
                        NSString *cloneInfoPath = [cloneApp stringByAppendingPathComponent:@"Info.plist"];
                        NSString *cloneName = [NSString stringWithFormat:@"%@ نسخة", sourceName.length > 0 ? sourceName : @"التطبيق"];
                        if (!rewriteInfo(cloneInfoPath, newID, cloneName)) {
                            error = [self errorWithCode:49 description:@"تعذر تحديث هوية التطبيق المكرر"];
                        }

                        NSDirectoryEnumerator *enumerator = error ? nil : [fm enumeratorAtPath:cloneApp];
                        NSString *relative = nil;
                        while (!error && (relative = [enumerator nextObject])) {
                            if (![relative.pathExtension.lowercaseString isEqualToString:@"appex"]) continue;
                            NSString *appexPath = [cloneApp stringByAppendingPathComponent:relative];
                            NSString *appexInfoPath = [appexPath stringByAppendingPathComponent:@"Info.plist"];
                            NSDictionary *appexInfo = [NSDictionary dictionaryWithContentsOfFile:appexInfoPath];
                            NSString *oldAppexID = [appexInfo[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? appexInfo[@"CFBundleIdentifier"] : nil;
                            NSString *suffix = oldAppexID.length > sourceID.length ? [oldAppexID substringFromIndex:sourceID.length] : @".Extension";
                            while ([suffix hasPrefix:@"."]) suffix = [suffix substringFromIndex:1];
                            suffix = [suffix stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
                            NSString *newAppexID = suffix.length > 0 ? [NSString stringWithFormat:@"%@.%@", newID, suffix] : [NSString stringWithFormat:@"%@.Extension", newID];
                            NSString *appexName = [appexInfo[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? appexInfo[@"CFBundleDisplayName"] : nil;
                            if (!rewriteInfo(appexInfoPath, newAppexID, appexName)) {
                                error = [self errorWithCode:50 description:[NSString stringWithFormat:@"تعذر تحديث هوية الامتداد %@", relative.lastPathComponent]];
                                break;
                            }
                            [enumerator skipDescendants];
                        }
                    }

                    if (!error && ![self removeCodeSignaturesFromBundle:cloneApp error:&error]) {
                        if (!error) error = [self errorWithCode:51 description:@"تعذر إزالة التواقيع القديمة من النسخة المكررة"];
                    }
                    if (!error) {
                        NSMutableArray *encrypted = [NSMutableArray array];
                        NSArray *cloneMachO = [self machOPathsInBundle:cloneApp encrypted:encrypted];
                        if (encrypted.count > 0 || cloneMachO.count == 0 || ![self normalizeMachOPermissions:cloneMachO error:&error]) {
                            if (!error) error = [self errorWithCode:52 description:@"تعذر التحقق من ملفات Mach-O في النسخة المكررة"];
                        }
                    }
                    if (!error) {
                        NSString *safe = [sourceName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
                        safe = [safe stringByReplacingOccurrencesOfString:@"\\" withString:@"-"];
                        safe = [safe stringByReplacingOccurrencesOfString:@":" withString:@"-"];
                        safe = [safe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if (safe.length == 0) safe = @"Application";
                        safe = [safe stringByAppendingString:@" نسخة"];
                        NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[safe stringByAppendingPathExtension:@"ipa"]];
                        NSUInteger collision = 2;
                        while ([fm fileExistsAtPath:outputPath]) {
                            NSString *candidate = [NSString stringWithFormat:@"%@ (%lu)", safe, (unsigned long)collision++];
                            outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[candidate stringByAppendingPathExtension:@"ipa"]];
                        }
                        if (![self runCommand:self.zipPath args:@[@"-qry", outputPath, @"Payload"] workingDirectory:workDirectory error:&error]) {
                            if (!error) error = [self errorWithCode:53 description:@"تعذر إعادة حزم IPA المكررة"];
                        } else {
                            cloneURL = [NSURL fileURLWithPath:outputPath];
                        }
                    }
                    [fm removeItemAtURL:exportedURL error:nil];
                }
            }
        } @catch (NSException *exception) {
            error = [self errorWithCode:54 description:[NSString stringWithFormat:@"حدث خطأ أثناء تكرار التطبيق: %@", exception.reason ?: @"غير معروف"]];
        }
        if (workDirectory.length > 0) [fm removeItemAtPath:workDirectory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(cloneURL, error);
        });
    });
}

@end
