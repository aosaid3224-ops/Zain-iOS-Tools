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
@property (nonatomic, strong) NSString *dataContainerPath;
@property (nonatomic, assign) BOOL hasInfoPlist;
@property (nonatomic, strong) NSString *categoryType;   // LSApplicationCategoryType
@property (nonatomic, strong) NSArray<NSString *> *genres;
@property (nonatomic, strong) NSArray<NSNumber *> *genreIDs;
// iTunesMetadata probe — honest 3-state result
@property (nonatomic, strong) NSString *metadataState;      // ok / missing / unreadable / unparseable / no-container
@property (nonatomic, strong) NSString *metadataPath;
@property (nonatomic, assign) long long metadataSize;
@property (nonatomic, assign) BOOL metadataReadable;
@property (nonatomic, assign) BOOL metadataParseable;
@property (nonatomic, strong) NSArray<NSString *> *metadataKeys;
@property (nonatomic, strong) NSNumber *iTunesGenreId;
@property (nonatomic, strong) NSString *iTunesGenre;
@property (nonatomic, assign) BOOL receiptPresent;
@property (nonatomic, strong) NSDictionary *infoPlistStoreKeys;
@property (nonatomic, strong) NSString *engineName;
@property (nonatomic, strong) NSMutableArray<NSString *> *signals;  // why Game / why not
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, assign) BOOL isGame;
- (NSDictionary *)dictionaryRepresentation;
@end
