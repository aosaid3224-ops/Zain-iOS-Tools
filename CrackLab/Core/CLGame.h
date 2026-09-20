//
//  CLGame.h
//  Crack Lab — game model.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CLGameEngine) {
    CLGameEngineUnknown = 0,
    CLGameEngineUnity,
    CLGameEngineUnreal,
    CLGameEngineGodot,
    CLGameEngineCocos2D,
    CLGameEngineNativeMetal,
    CLGameEngineSpriteKit,
    CLGameEngineSceneKit
};

typedef NS_ENUM(NSInteger, CLGameModState) {
    CLGameModStateUnknown = 0,
    CLGameModStateOriginal,     // matches stored baseline fingerprint
    CLGameModStateModified,     // differs from baseline
    CLGameModStateNoBaseline    // never fingerprinted
};

@interface CLGame : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *bundlePath;
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, assign) CLGameEngine engine;
@property (nonatomic, strong) NSString *engineName;   // localized display
@property (nonatomic, assign) long long bundleSize;   // bytes
@property (nonatomic, strong) NSArray<NSString *> *frameworks; // linked frameworks (cap)
@property (nonatomic, assign) CLGameModState modState;
@property (nonatomic, strong) NSString *executableSHA256;
@property (nonatomic, strong) NSDate *lastModified;
@end
