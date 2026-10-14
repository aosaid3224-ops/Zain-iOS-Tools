#import "IPAArchiveExtractor.h"
#import "SPRootHide.h"
#import "RootlessManager.h"
#import "Logger.h"
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

extern char **environ;

@implementation IPAArchiveExtractionResult
@end

@interface IPAArchiveExtractionTask ()
@property (nonatomic, assign) pid_t processID;
@end

@implementation IPAArchiveExtractionTask

- (void)cancel {
    self.cancellationRequested = YES;
    pid_t pid = self.processID;
    if (pid > 0) kill(pid, SIGTERM);
}

@end

@interface IPAArchiveExtractor ()
@end

@implementation IPAArchiveExtractor

+ (instancetype)sharedExtractor {
    static IPAArchiveExtractor *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSString *)privateWorkspaceRoot {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupport = paths.firstObject ?: NSTemporaryDirectory();
    return [[applicationSupport stringByAppendingPathComponent:@"IPAInstallerPro"] stringByAppendingPathComponent:@"IPAExtractor"];
}

- (NSString *)defaultOutputDirectoryForIPAPath:(NSString *)ipaPath {
    NSString *sourceName = [[ipaPath lastPathComponent] stringByDeletingPathExtension];
    if (sourceName.length == 0) sourceName = @"IPA";
    return [[self privateWorkspaceRoot] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ — Extracted", sourceName]];
}

- (NSString *)uniqueOutputDirectoryForIPAPath:(NSString *)ipaPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *workspace = [self privateWorkspaceRoot];
    [fm createDirectoryAtPath:workspace withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *base = [self defaultOutputDirectoryForIPAPath:ipaPath];
    NSString *candidate = base;
    NSUInteger suffix = 2;
    while ([fm fileExistsAtPath:candidate]) {
        candidate = [NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)suffix++];
    }
    return candidate;
}

- (IPAArchiveExtractionResult *)resultForSource:(NSString *)source success:(BOOL)success output:(NSString *)output message:(NSString *)message error:(NSString *)error {
    IPAArchiveExtractionResult *result = [[IPAArchiveExtractionResult alloc] init];
    result.success = success;
    result.sourcePath = source ?: @"";
    result.outputPath = output;
    result.statusMessage = message ?: @"";
    result.errorMessage = error ?: @"";
    return result;
}

- (NSString *)resolvedUnzipPath {
    NSString *resolved = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:resolved]) return resolved;
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/unzip"]) return @"/usr/bin/unzip";
    return nil;
}

- (int)runExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments task:(IPAArchiveExtractionTask *)task captureOutput:(BOOL)captureOutput output:(NSString **)output error:(NSString **)error {
    if (path.length == 0) return 127;
    int pipefd[2] = {-1, -1};
    if (captureOutput && pipe(pipefd) != 0) return 127;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    if (captureOutput) {
        posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&actions, pipefd[0]);
        posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    } else {
        int devNull = open("/dev/null", O_WRONLY);
        if (devNull >= 0) {
            posix_spawn_file_actions_adddup2(&actions, devNull, STDOUT_FILENO);
            posix_spawn_file_actions_adddup2(&actions, devNull, STDERR_FILENO);
            posix_spawn_file_actions_addclose(&actions, devNull);
        }
    }

    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:path];
    [argvStrings addObjectsFromArray:SPToolArguments(path, arguments ?: @[])];
    char **argv = calloc(argvStrings.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = (char *)argvStrings[i].UTF8String;
    argv[argvStrings.count] = NULL;

    pid_t pid = 0;
    if (task.isCancellationRequested) {
        posix_spawn_file_actions_destroy(&actions);
        free(argv);
        if (captureOutput) { close(pipefd[0]); close(pipefd[1]); }
        return ECANCELED;
    }
    int spawnStatus = posix_spawn(&pid, path.fileSystemRepresentation, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    free(argv);
    if (captureOutput) close(pipefd[1]);
    if (spawnStatus != 0) {
        task.processID = 0;
        if (captureOutput) close(pipefd[0]);
        return spawnStatus;
    }

    task.processID = pid;
    NSMutableData *captured = [NSMutableData data];
    if (captureOutput) {
        uint8_t buffer[32768];
        ssize_t count;
        while ((count = read(pipefd[0], buffer, sizeof(buffer))) > 0) {
            [captured appendBytes:buffer length:(NSUInteger)count];
        }
        close(pipefd[0]);
    }

    int waitStatus = 0;
    pid_t waited = 0;
    do {
        waited = waitpid(pid, &waitStatus, WNOHANG);
        if (waited == 0) usleep(100000);
    } while (waited == 0);
    task.processID = 0;
    if (waited < 0) return 127;
    if (output) *output = [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"";
    if (error) *error = [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"";
    return WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : 128;
}

- (BOOL)isSafeExtractedPath:(NSString *)relativePath {
    if (relativePath.length == 0) return YES;
    if ([relativePath hasPrefix:@"/"] || [relativePath hasPrefix:@"\\"]) return NO;
    for (NSString *component in [relativePath pathComponents]) {
        if ([component isEqualToString:@".."] || [component isEqualToString:@"."]) return NO;
    }
    return YES;
}

- (BOOL)validateExtractedSymlinksUnderPath:(NSString *)root error:(NSString **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
    NSString *relative;
    while ((relative = [enumerator nextObject])) {
        NSString *fullPath = [root stringByAppendingPathComponent:relative];
        struct stat st = {0};
        if (lstat(fullPath.fileSystemRepresentation, &st) != 0) {
            if (error) *error = [NSString stringWithFormat:@"تعذر فحص الناتج: %@", relative];
            return NO;
        }
        if (!S_ISLNK(st.st_mode)) continue;
        NSString *linkTarget = [fm destinationOfSymbolicLinkAtPath:fullPath error:nil];
        BOOL safeTarget = NO;
        if (linkTarget.length > 0 && ![linkTarget hasPrefix:@"/"] && ![linkTarget hasPrefix:@"\\"]) {
            NSString *rootPath = [root stringByStandardizingPath];
            NSString *resolvedTarget = [[[fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:linkTarget] stringByStandardizingPath];
            NSString *rootPrefix = [rootPath stringByAppendingString:@"/"];
            safeTarget = [resolvedTarget isEqualToString:rootPath] || [resolvedTarget hasPrefix:rootPrefix];
        }
        if (!safeTarget) {
            if (error) *error = [NSString stringWithFormat:@"رابط رمزي غير آمن داخل الناتج: %@", relative];
            return NO;
        }
    }
    return YES;
}

- (IPAArchiveExtractionTask *)extractIPAAtPath:(NSString *)ipaPath outputPath:(NSString *)outputPath progress:(IPAArchiveExtractionProgress)progress completion:(IPAArchiveExtractionCompletion)completion {
    NSString *source = [ipaPath copy];
    NSString *requestedOutput = [outputPath copy];
    IPAArchiveExtractionTask *task = [[IPAArchiveExtractionTask alloc] init];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        void (^report)(double, NSString *) = ^(double value, NSString *status) {
            if (!progress) return;
            dispatch_async(dispatch_get_main_queue(), ^{ progress(value, status ?: @""); });
        };
        void (^finish)(IPAArchiveExtractionResult *) = ^(IPAArchiveExtractionResult *result) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
        };
        void (^fail)(NSString *) = ^(NSString *message) {
            IPAArchiveExtractionResult *failed = [self resultForSource:source success:NO output:nil message:(task.isCancellationRequested ? @"تم إلغاء فك الحزمة" : @"فشل فك الحزمة") error:message];
            failed.cancelled = task.isCancellationRequested;
            finish(failed);
        };

        report(0.02, @"التحقق من ملف IPA...");
        if (task.isCancellationRequested) { fail(@"أُلغيت قبل البدء"); return; }
        if (source.length == 0 || ![source.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            fail(@"يجب اختيار ملف بامتداد .ipa");
            return;
        }
        struct stat sourceStat = {0};
        if (lstat(source.fileSystemRepresentation, &sourceStat) != 0 || !S_ISREG(sourceStat.st_mode)) {
            fail(@"ملف IPA غير موجود أو ليس ملفًا عاديًا");
            return;
        }
        NSString *workspace = [[self privateWorkspaceRoot] stringByStandardizingPath];
        NSString *outputDirectory = [[requestedOutput stringByDeletingLastPathComponent] stringByStandardizingPath];
        NSString *workspacePrefix = [workspace stringByAppendingString:@"/"];
        if (requestedOutput.length == 0 || (![outputDirectory isEqualToString:workspace] && ![outputDirectory hasPrefix:workspacePrefix])) {
            fail(@"مسار الناتج يجب أن يكون داخل مساحة العمل الخاصة بالأداة");
            return;
        }
        if ([fm fileExistsAtPath:requestedOutput]) {
            fail(@"مجلد الناتج موجود مسبقًا؛ اختر اسمًا فريدًا آمنًا");
            return;
        }

        NSString *unzip = [self resolvedUnzipPath];
        if (unzip.length == 0) {
            fail(@"لم يتم العثور على unzip عبر resolver البيئة الحالي");
            return;
        }

        report(0.08, @"التحقق من سلامة أرشيف ZIP...");
        NSString *testOutput = nil;
        int testExit = [self runExecutable:unzip arguments:@[@"-tq", source] task:task captureOutput:YES output:&testOutput error:nil];
        if (testExit != 0) {
            fail(testOutput.length > 0 ? testOutput : @"أرشيف IPA غير صالح أو تالف");
            return;
        }
        NSString *listingOutput = nil;
        int listingExit = [self runExecutable:unzip arguments:@[@"-Z1", source] task:task captureOutput:YES output:&listingOutput error:nil];
        if (listingExit != 0 || listingOutput.length == 0) {
            fail(@"تعذر قراءة قائمة محتويات IPA للتحقق من المسارات");
            return;
        }
        for (NSString *rawEntry in [listingOutput componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *entry = [rawEntry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (entry.length > 0 && ![self isSafeExtractedPath:entry]) {
                fail([NSString stringWithFormat:@"مسار ZIP غير آمن: %@", entry]);
                return;
            }
        }

        NSString *temporary = [workspace stringByAppendingPathComponent:[NSString stringWithFormat:@".ipa-unpack-%@.tmp", [NSUUID UUID].UUIDString]];
        NSError *directoryError = nil;
        if (![fm createDirectoryAtPath:temporary withIntermediateDirectories:NO attributes:nil error:&directoryError]) {
            fail(directoryError.localizedDescription ?: @"تعذر إنشاء مساحة مؤقتة");
            return;
        }

        report(0.15, @"استخراج كامل لمحتويات IPA...");
        int extractExit = [self runExecutable:unzip arguments:@[@"-q", @"-o", source, @"-d", temporary] task:task captureOutput:NO output:nil error:nil];
        if (extractExit != 0) {
            [fm removeItemAtPath:temporary error:nil];
            fail(@"فشل unzip أثناء استخراج محتويات الحزمة");
            return;
        }

        report(0.72, @"فحص بنية الناتج والروابط الرمزية...");
        NSString *payload = [temporary stringByAppendingPathComponent:@"Payload"];
        BOOL payloadIsDirectory = NO;
        if (![fm fileExistsAtPath:payload isDirectory:&payloadIsDirectory] || !payloadIsDirectory) {
            [fm removeItemAtPath:temporary error:nil];
            fail(@"اكتمل unzip لكن الناتج لا يحتوي على Payload صالح");
            return;
        }
        NSString *linkError = nil;
        if (![self validateExtractedSymlinksUnderPath:temporary error:&linkError]) {
            [fm removeItemAtPath:temporary error:nil];
            fail(linkError ?: @"تم رفض رابط رمزي غير آمن");
            return;
        }

        __block NSUInteger entries = 0;
        __block unsigned long long bytes = 0;
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:temporary];
        NSString *relative;
        while ((relative = [enumerator nextObject])) {
            entries++;
            NSDictionary *attrs = [fm attributesOfItemAtPath:[temporary stringByAppendingPathComponent:relative] error:nil];
            bytes += [attrs[NSFileSize] unsignedLongLongValue];
        }
        report(0.88, @"تجهيز المجلد النهائي...");
        NSError *moveError = nil;
        if (![fm moveItemAtPath:temporary toPath:requestedOutput error:&moveError]) {
            [fm removeItemAtPath:temporary error:nil];
            fail(moveError.localizedDescription ?: @"تعذر إنشاء مجلد الناتج النهائي");
            return;
        }

        if (task.isCancellationRequested) {
            [fm removeItemAtPath:requestedOutput error:nil];
            fail(@"أُلغيت قبل إتمام النتيجة");
            return;
        }
        IPAArchiveExtractionResult *result = [self resultForSource:source success:YES output:requestedOutput message:@"تم فك حزمة IPA بالكامل" error:nil];
        result.extractedEntryCount = entries;
        result.extractedByteCount = bytes;
        report(1.0, @"اكتمل فك الحزمة بنجاح");
        [[Logger sharedLogger] info:[NSString stringWithFormat:@"IPA archive unpacked: %@ -> %@ entries=%lu bytes=%llu", source, requestedOutput, (unsigned long)entries, bytes]];
        finish(result);
    });
    return task;
}

@end
