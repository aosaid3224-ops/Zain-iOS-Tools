//
//  CLDiscoveryRecord.h
//  Crack Lab — per-app discovery diagnosis (why included / excluded).
//

#import <Foundation/Foundation.h>

@interface CLDiscoveryRecord : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *appType;      // مستخدم / نظام / أخرى
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, assign) BOOL hasInfoPlist;
@property (nonatomic, strong) NSString *categoryType; // LSApplicationCategoryType
@property (nonatomic, strong) NSArray<NSString *> *genres;
@property (nonatomic, strong) NSArray<NSNumber *> *genreIDs;
@property (nonatomic, strong) NSString *engineName;
@property (nonatomic, strong) NSMutableArray<NSString *> *signals;  // why Game / why not
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, assign) BOOL isGame;
- (NSDictionary *)dictionaryRepresentation;
@end
