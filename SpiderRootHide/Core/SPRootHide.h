#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SPIsRootHide(void);

NSString *SPJBRootPath(void);

NSString *SPJBPath(NSString *jailbreakPath);

BOOL SPIsInsideJBRoot(NSString *realPath);

NSString *_Nullable SPJBRelativePath(NSString *realPath);

BOOL SPToolUsesJBRootPaths(NSString *executable);

NSString *SPToolPathForTool(NSString *executable, NSString *realPath);

NSArray<NSString *> *SPToolArguments(NSString *executable, NSArray<NSString *> *_Nullable arguments);

NSString *SPPathFromTool(NSString *toolPath);

extern NSString *const SPRootHelperName;

NS_ASSUME_NONNULL_END
