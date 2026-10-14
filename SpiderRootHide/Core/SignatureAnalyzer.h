#import <Foundation/Foundation.h>

@interface SignatureInfo : NSObject
@property (nonatomic, assign) BOOL isSigned;
@property (nonatomic, assign) BOOL isAdHocSigned;
@property (nonatomic, strong) NSString *teamID;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *authority;
@property (nonatomic, strong) NSString *signatureStatus;
@property (nonatomic, strong) NSString *source;
@property (nonatomic, strong) NSString *parseError;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface SignatureAnalyzer : NSObject
+ (instancetype)sharedAnalyzer;
- (SignatureInfo *)analyzeSignatureAtPath:(NSString *)path;
- (NSDictionary *)extractEntitlementsAtPath:(NSString *)path;
- (NSString *)runLdid:(NSString *)arg target:(NSString *)path;
@end
