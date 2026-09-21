//
//  CLMetadataProbe.h
//  Crack Lab — direct, evidence-only App Store metadata probe.
//
//  iTunesMetadata.plist is NOT inside the .app bundle on modern iOS; it lives
//  in the app's DATA CONTAINER. This probe checks every candidate path,
//  reports the three distinct states (missing / unreadable / no-genre), and
//  never guesses.
//

#import <Foundation/Foundation.h>

@interface CLMetadataProbeResult : NSObject
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, assign) BOOL bundleExists;
@property (nonatomic, strong) NSString *dataContainerPath;
@property (nonatomic, strong) NSString *metadataPath;      // winning candidate path (nil = none)
@property (nonatomic, strong) NSString *metadataState;     // ok / missing / unreadable / unparseable / no-container
@property (nonatomic, assign) long long metadataSize;
@property (nonatomic, assign) BOOL metadataReadable;       // NSData contentsOfFile succeeded
@property (nonatomic, assign) BOOL metadataParseable;      // NSPropertyListSerialization succeeded
@property (nonatomic, strong) NSArray<NSString *> *metadataKeys;
@property (nonatomic, strong) NSNumber *genreId;
@property (nonatomic, strong) NSString *genre;
@property (nonatomic, assign) BOOL receiptPresent;         // StoreKit/sapreceipt (diagnostic only)
@property (nonatomic, strong) NSDictionary *infoPlistStoreKeys; // Info.plist store/genre/category keys
@property (nonatomic, strong) NSArray<NSString *> *candidatesChecked; // every path probed + existence
@end

@interface CLMetadataProbe : NSObject
+ (CLMetadataProbeResult *)probeProxy:(id)proxy bundlePath:(NSString *)bundlePath;
@end
