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
        @"dataContainer": self.dataContainerPath ?: @"",
        @"hasInfoPlist": @(self.hasInfoPlist),
        @"categoryType": self.categoryType ?: @"",
        @"genres": self.genres ?: @[],
        @"genreIDs": self.genreIDs ?: @[],
        @"metadataState": self.metadataState ?: @"",
        @"metadataPath": self.metadataPath ?: @"",
        @"metadataSize": @(self.metadataSize),
        @"metadataReadable": @(self.metadataReadable),
        @"metadataParseable": @(self.metadataParseable),
        @"metadataKeys": self.metadataKeys ?: @[],
        @"iTunesGenreId": self.iTunesGenreId ?: @"",
        @"iTunesGenre": self.iTunesGenre ?: @"",
        @"receiptPresent": @(self.receiptPresent),
        @"infoPlistStoreKeys": self.infoPlistStoreKeys ?: @{},
        @"engine": self.engineName ?: @"",
        @"confidence": self.confidence ?: @"",
        @"signals": self.signals ?: @[],
        @"score": @(self.score),
        @"isGame": @(self.isGame)
    };
}

@end
