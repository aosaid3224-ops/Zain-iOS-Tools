//
//  CLDiscoveryRecord.h
//  Crack Lab — per-app discovery diagnosis (why included / excluded).
//

#import <Foundation/Foundation.h>

@interface CLDiscoveryRecord : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *appType;        // مستخدم / نظام / أخرى / غير معروف
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, assign) BOOL hasInfoPlist;
@property (nonatomic, strong) NSString *categoryType;   // LSApplicationCategoryType
@property (nonatomic, strong) NSArray<NSString *> *genres;
@property (nonatomic, strong) NSArray<NSNumber *> *genreIDs;
@property (nonatomic, strong) NSNumber *iTunesGenreId;  // من iTunesMetadata.plist داخل الحزمة
@property (nonatomic, strong) NSString *iTunesGenre;
@property (nonatomic, strong) NSString *engineName;
@property (nonatomic, strong) NSArray<NSString *> *signals;
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, assign) BOOL isGame;
- (NSDictionary *)dictionaryRepresentation;
@end
