//
//  CLEngineDetector.h
//  Crack Lab — detects the engine powering a game bundle.
//
//  Strategy (layered, conservative — never guesses without evidence):
//   1. Bundle markers: UnityFramework.framework, .uproject/.uasset counts,
//      Godot/Cocos file signatures.
//   2. Mach-O load commands: scans LC_LOAD_DYLIB for engine frameworks.
//

#import <Foundation/Foundation.h>
#import "CLGame.h"

@interface CLEngineDetector : NSObject
/// Returns engine constant; fills linkedFrameworks (cap applied) via out param.
+ (CLGameEngine)detectEngineForBundle:(NSString *)bundlePath
                       linkedFrameworks:(NSArray<NSString *> **)outFrameworks;
+ (NSString *)localizedNameForEngine:(CLGameEngine)engine;
@end
