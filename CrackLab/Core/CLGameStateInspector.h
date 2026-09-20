//
//  CLGameStateInspector.h
//  Crack Lab — fingerprints game state, compares against stored baseline.
//
//  Phase 1: executable SHA-256 only (fast, decisive for "was the binary touched").
//  Later phases extend to full file-set fingerprints.
//

#import <Foundation/Foundation.h>
#import "CLGame.h"

@interface CLGameStateInspector : NSObject

/// Computes the current executable hash and resolves modState (loads baseline).
- (void)inspectGame:(CLGame *)game completion:(void (^)(CLGame *game, NSString *error))completion;

/// Stores the CURRENT executable hash as the trusted "original" baseline.
- (void)establishBaselineForGame:(CLGame *)game completion:(void (^)(BOOL ok, NSString *error))completion;

/// SHA-256 of a file, hex lowercase. nil on failure.
+ (NSString *)sha256OfFile:(NSString *)path;
@end
