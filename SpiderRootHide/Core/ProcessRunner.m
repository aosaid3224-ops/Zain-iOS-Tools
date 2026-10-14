#import "ProcessRunner.h"
#import "CommandResult.h"
#import "Logger.h"
#import "SPRootHide.h"

#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>

extern char **environ;

@interface ProcessRunner ()
@property (nonatomic, strong) dispatch_queue_t runnerQueue;
@end

@implementation ProcessRunner

+ (instancetype)sharedRunner {
    static ProcessRunner *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _runnerQueue = dispatch_queue_create("com.spider.processrunner", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (CommandResult *)runCommand:(NSString *)path
                    arguments:(NSArray<NSString *> *)arguments
                      timeout:(NSTimeInterval)timeout {
    if (path.length == 0) {
        return [[CommandResult alloc] initWithCommandPath:@""
                                                  arguments:arguments
                                                   exitCode:-1
                                               signalNumber:0
                                                 spawnError:ENOENT
                                                 stdoutText:@""
                                                 stderrText:@""
                                                 stdoutData:[NSData data]
                                                 stderrData:[NSData data]
                                                   duration:0.0
                                                   timedOut:NO];
    }

    arguments = SPToolArguments(path, arguments);

    NSDate *start = [NSDate date];
    int stdoutPipe[2] = {-1, -1};
    int stderrPipe[2] = {-1, -1};

    if (pipe(stdoutPipe) != 0 || pipe(stderrPipe) != 0) {
        return [[CommandResult alloc] initWithCommandPath:path
                                                  arguments:arguments
                                                   exitCode:-1
                                               signalNumber:0
                                                 spawnError:errno
                                                 stdoutText:@""
                                                 stderrText:@""
                                                 stdoutData:[NSData data]
                                                 stderrData:[NSData data]
                                                   duration:0.0
                                                   timedOut:NO];
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]);
    posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[1]);

    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:path];
    [argvStrings addObjectsFromArray:arguments ?: @[]];
    char **argv = calloc(argvStrings.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvStrings.count; i++) {
        argv[i] = (char *)[argvStrings[i] UTF8String];
    }
    argv[argvStrings.count] = NULL;

    pid_t pid = 0;
    int spawnErr = posix_spawn(&pid, path.fileSystemRepresentation, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    free(argv);

    close(stdoutPipe[1]);
    close(stderrPipe[1]);

    if (spawnErr != 0) {
        close(stdoutPipe[0]);
        close(stderrPipe[0]);
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"ProcessRunner: spawn failed for %@ (errno=%d: %s)", path, spawnErr, strerror(spawnErr)]];
        return [[CommandResult alloc] initWithCommandPath:path
                                                  arguments:arguments
                                                   exitCode:-1
                                               signalNumber:0
                                                 spawnError:spawnErr
                                                 stdoutText:@""
                                                 stderrText:@""
                                                 stdoutData:[NSData data]
                                                 stderrData:[NSData data]
                                                   duration:[[NSDate date] timeIntervalSinceDate:start]
                                                   timedOut:NO];
    }

    NSMutableData *stdoutData = [NSMutableData data];
    NSMutableData *stderrData = [NSMutableData data];
    BOOL finished = NO;
    BOOL timedOut = NO;
    int status = 0;

    NSDate *deadline = (timeout > 0) ? [NSDate dateWithTimeIntervalSinceNow:timeout] : nil;

    while (!finished) {
        struct pollfd fds[2];
        fds[0].fd = stdoutPipe[0];
        fds[0].events = POLLIN;
        fds[1].fd = stderrPipe[0];
        fds[1].events = POLLIN;

        int remainingMs = -1;
        if (deadline) {
            remainingMs = (int)([deadline timeIntervalSinceNow] * 1000.0);
            if (remainingMs <= 0) {
                timedOut = YES;
                break;
            }
        }

        int ret = poll(fds, 2, remainingMs);
        if (ret < 0 && errno != EINTR) {
            break;
        }
        if (ret == 0 && deadline) {
            timedOut = YES;
            break;
        }

        uint8_t buf[4096];
        if (fds[0].revents & POLLIN) {
            ssize_t n = read(stdoutPipe[0], buf, sizeof(buf));
            if (n > 0) [stdoutData appendBytes:buf length:(NSUInteger)n];
        }
        if (fds[1].revents & POLLIN) {
            ssize_t n = read(stderrPipe[0], buf, sizeof(buf));
            if (n > 0) [stderrData appendBytes:buf length:(NSUInteger)n];
        }

        pid_t waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid) {
            uint8_t drainBuf[4096];
            ssize_t drainN;
            while ((drainN = read(stdoutPipe[0], drainBuf, sizeof(drainBuf))) > 0) {
                [stdoutData appendBytes:drainBuf length:(NSUInteger)drainN];
            }
            while ((drainN = read(stderrPipe[0], drainBuf, sizeof(drainBuf))) > 0) {
                [stderrData appendBytes:drainBuf length:(NSUInteger)drainN];
            }
            finished = YES;
        } else if (waited < 0 && errno != EINTR) {
            break;
        }
    }

    if (timedOut) {
        kill(pid, SIGTERM);
        usleep(100000);
        waitpid(pid, &status, WNOHANG);
    }

    close(stdoutPipe[0]);
    close(stderrPipe[0]);

    if (!finished && !timedOut) {
        waitpid(pid, &status, 0);
        finished = YES;
    }

    int exitCode = -1;
    int signalNum = 0;
    if (finished) {
        if (WIFEXITED(status)) exitCode = WEXITSTATUS(status);
        if (WIFSIGNALED(status)) signalNum = WTERMSIG(status);
    }

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    NSString *stdoutStr = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrStr = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";

    CommandResult *result = [[CommandResult alloc] initWithCommandPath:path
                                                               arguments:arguments
                                                                exitCode:exitCode
                                                            signalNumber:signalNum
                                                              spawnError:0
                                                              stdoutText:stdoutStr
                                                              stderrText:stderrStr
                                                              stdoutData:[stdoutData copy]
                                                              stderrData:[stderrData copy]
                                                                duration:duration
                                                                timedOut:timedOut];

    if (!result.success) {
        [[Logger sharedLogger] warning:[NSString stringWithFormat:@"ProcessRunner: %@ | category=%@ | stderr=%@",
                                        result, result.failureCategory,
                                        stderrStr.length > 200 ? [stderrStr substringToIndex:200] : stderrStr]];
    }

    return result;
}

- (void)runCommand:(NSString *)path
         arguments:(NSArray<NSString *> *)arguments
           timeout:(NSTimeInterval)timeout
        completion:(void (^)(CommandResult *result))completion {
    dispatch_async(self.runnerQueue, ^{
        CommandResult *result = [self runCommand:path arguments:arguments timeout:timeout];
        if (completion) completion(result);
    });
}

@end
