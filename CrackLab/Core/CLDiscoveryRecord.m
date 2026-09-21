//
//  CLDiscoveryRecord.m
//

#import "CLDiscoveryRecord.h"

@implementation CLDiscoveryRecord

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"bundleID": self.bundleID ?: @"",
        @"name": self.name ?: @"",
        @"appType": self.appType ?: @"",
        @"path": self.bundlePath ?: @"",
        @"hasInfoPlist": @(self.hasInfoPlist),
        @"categoryType": self.categoryType ?: @"",
        @"genres": self.genres ?: @[],
        @"genreIDs": self.genreIDs ?: @[],
        @"engine": self.engineName ?: @"",
        @"signals": self.signals ?: @[],
        @"score": @(self.score),
        @"isGame": @(self.isGame)
    };
}

@end
