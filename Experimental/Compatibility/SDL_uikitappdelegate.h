#pragma once
#import "SDL_uikitopenglview.h"
#define SDLUIKitDelegate NDOSXUIKitDelegate
@interface NDOSXUIKitDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *uiwindow;
- (void)applicationDidFinishLaunching:(UIApplication *)application;
@end
