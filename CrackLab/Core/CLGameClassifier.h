//
//  CLGameClassifier.h
//  Crack Lab — Game Classification Engine (confidence-based, evidence only).
//
//  Design rules (hard constraints):
//   - Engine/Metal/Framework names are NEVER a game proof on their own.
//   - Official metadata (genreId/category) when present = Confident.
//   - Developer-declared evidence inside the binary (Game Center entitlement,
//     GameKit linkage) is the primary on-device proof on iOS 17/18 where
//     store metadata and LaunchServices genre fields are absent.
//   - Every decision is a list of named evidence items — no hidden heuristics.
//

#import <Foundation/Foundation.h>
#import "CLMetadataProbe.h"

typedef NS_ENUM(NSInteger, CLGameConfidence) {
    CLGameConfidenceUnlikely = 0,   // < 40      → not a game
    CLGameConfidencePossible,       // 40–69     → game, shown as "محتمل"
    CLGameConfidenceConfident       // >= 70 or official/entitlement proof
};

@interface CLClassificationResult : NSObject
@property (nonatomic, assign) BOOL isGame;
@property (nonatomic, assign) CLGameConfidence confidence;
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, strong) NSMutableArray<NSString *> *signals;
@property (nonatomic, strong) NSString *confidenceName;   // عربي
@end

@interface CLGameClassifier : NSObject

/// Classify one application. `info` = parsed Info.plist, `probe` = metadata
/// probe result, `executablePath` = main binary (for entitlement scan).
+ (CLClassificationResult *)classifyProxy:(id)proxy
                                     info:(NSDictionary *)info
                                    probe:(CLMetadataProbeResult *)probe
                           executablePath:(NSString *)executablePath;
@end
