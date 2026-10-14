/*
 *  Copyright (C) 2010  Chaoji Li
 *
 *  DOSPAD is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "AppDelegate.h"
#import "DPEmulatorViewController.h"
#import "Common.h"
#import <AVFoundation/AVFoundation.h>
#import "ColorTheme.h"
#import "UIViewController+Alert.h"
#import "DPSettings.h"
#ifdef NDOS_X_HOST
#import "NDOSXProfiles.h"
#endif

#define kLastURL @"LastPackageURL"

@interface AppDelegate ()
{
	DPEmulatorViewController *_emulatorController;
	BOOL _startupRequested;
	BOOL _startupCompleted;
	BOOL _sceneActive;
#ifdef NDOS_X_HOST
    NDOSXProfilePicker *_profilePicker;
#endif
}
@end


@implementation AppDelegate
@synthesize frameskip;
@synthesize cycles;
@synthesize maxPercent;

- (void)rememberURL:(NSURL*)url
{
    NSData *bookmark = [url bookmarkDataWithOptions:0
        includingResourceValuesForKeys:nil
        relativeToURL:nil
        error:nil];
    if (bookmark)
    {
        [[NSUserDefaults standardUserDefaults] setObject:bookmark
            forKey:kLastURL];
    }
}

- (NSURL*)openLastURL
{
	NSData *bookmark = [[NSUserDefaults standardUserDefaults] objectForKey:kLastURL];
	if (bookmark)
	{
		NSError *err = nil;
		BOOL isStale = NO;
		NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&isStale error:&err];
		if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path] && !isStale)
		{
			return url;
		}
	}
	return nil;
}

- (BOOL)openPackageURL:(NSURL *)url
{
#ifdef NDOS_X_HOST
    return NO;
#endif
	NSLog(@"openURL: %@", url);
	if (url.isFileURL)
	{
		if ([DOSPadEmulator sharedInstance].started)
		{
			// TODO: show alert can not open while it's running
			// quick first.
			[_emulatorController alert:@"Busy"
				message:@"Can not launch the nDOS package while emulator is running. Please terminate the app first."];
			return NO;
		}
		[url startAccessingSecurityScopedResource];
		[self rememberURL:url];
		[DOSPadEmulator sharedInstance].diskcDirectory = url.path;
	}
	return YES;
}

-(SDL_uikitopenglview*)screen
{
    return screenView;
}


- (void)updateIdleTimer
{
    NSAssert([NSThread isMainThread], @"Idle timer policy must run on main");
    [UIApplication sharedApplication].idleTimerDisabled = _sceneActive && [DPSettings shared].keepScreenAwake;
}

- (void)emulatorWillResignActive
{
    _sceneActive = NO;
    [self updateIdleTimer];
#ifdef NDOS_X_HOST
    ndos_x_set_scene_paused(1);
#else
    dospad_pause();
#endif
    [_emulatorController willResignActive];
}

- (void)emulatorDidBecomeActive
{
    _sceneActive = YES;
#ifdef NDOS_X_HOST
    ndos_x_set_scene_paused(0);
#endif
    [self updateIdleTimer];
    [_emulatorController didBecomeActive];
#ifdef NDOS_X_HOST
    if (!_startupCompleted && _profilePicker.isViewLoaded) [_profilePicker refresh];
#endif
}

- (void)saveHistory
{
    dospad_save_history();
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [self saveHistory];
}

- (void)startDOS 
{
	_startupRequested = NO;
	if (_startupCompleted || !self.uiwindow.windowScene)
		return;
#ifdef NDOS_X_HOST
    DOSPadEmulator *emulator = [DOSPadEmulator sharedInstance];
    NDOSXProfiles *profiles = [[NDOSXProfiles alloc] initWithDocumentsDirectory:emulator.diskcDirectory];
    NSError *error = nil;
    NSString *path = [profiles pathForFilename:emulator.ndosXConfigPath.lastPathComponent error:&error];
    if (!path) {
        [_profilePicker refresh];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Configuration unavailable" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        if (!_profilePicker.presentedViewController) [_profilePicker presentViewController:alert animated:YES completion:nil];
        return;
    }
    emulator.ndosXConfigPath = path;
#endif
	_startupCompleted = YES;
	[super applicationDidFinishLaunching:[UIApplication sharedApplication]];
#ifdef THREADED
	[[DOSPadEmulator sharedInstance] start];
#endif
}

#ifdef NDOS_X_HOST
- (void)showProfilePicker
{
    _startupRequested = NO;
    if (_startupCompleted || !self.uiwindow.windowScene || _profilePicker) return;
    NDOSXProfiles *profiles = [[NDOSXProfiles alloc] initWithDocumentsDirectory:[DOSPadEmulator sharedInstance].diskcDirectory];
    _profilePicker = [[NDOSXProfilePicker alloc] initWithProfiles:profiles];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:_profilePicker];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    navigation.modalInPresentation = YES;
    __weak AppDelegate *weakSelf = self;
    _profilePicker.didChoosePath = ^(NSString *path) {
        AppDelegate *self = weakSelf;
        if (!self) return;
        [DOSPadEmulator sharedInstance].ndosXConfigPath = path;
        [self startDOS];
        if (self->_startupCompleted) {
            [self->_profilePicker dismissViewControllerAnimated:YES completion:nil];
            self->_profilePicker = nil;
        }
    };
    [_emulatorController presentViewController:navigation animated:YES completion:nil];
}
#endif

- (void)initColorTheme
{
	NSString *path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"configs/colortheme.json"];
	ColorTheme *theme = [[ColorTheme alloc] initWithPath:path];
	[ColorTheme setDefaultTheme:theme];
}


// Reference: https://developer.apple.com/library/ios/qa/qa1719/_index.html
- (BOOL)setBackupAttributeToItemAtPath:(NSString *)filePathString skip:(BOOL)skip
{
    NSURL* URL = [NSURL fileURLWithPath: filePathString];
    assert([[NSFileManager defaultManager] fileExistsAtPath: [URL path]]);
 
    NSError *error = nil;
    BOOL success = [URL setResourceValue:[NSNumber numberWithBool:skip]
                                  forKey:NSURLIsExcludedFromBackupKey error:&error];
    if (!success)
	{
        NSLog(
			@"Error %@ `%@' from backup: %@",
			(skip?@"excluding":@"including"),
			[URL lastPathComponent], error
		);
    }
    return success;
}

/*
 * Apply app-wide policies when their preferences change.
 */
- (void)settingsDidChange:(NSNotification *)notification
{
    if ([notification.userInfo[@"keys"] containsObject:kiCloudBackupEnabled]) [self initBackup];
    if ([notification.userInfo[@"keys"] containsObject:@"keep_screen_awake"]) [self updateIdleTimer];
}

- (void)initBackup
{
	if (DEFS_GET_BOOL(kiCloudBackupEnabled)) {
		[self setBackupAttributeToItemAtPath:DOCUMENTS_DIR skip:NO];
	} else {
		[self setBackupAttributeToItemAtPath:DOCUMENTS_DIR skip:YES];
	}
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions 
{
	NSLog(@"didFinishLaunchingWithOptions %@", launchOptions);
	[DPSettings shared];
	[self initBackup];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:DPFSettingsChangedNotification object:nil];
	[self initColorTheme];
	
	// Make sure we are allowed to play in lock screen
	NSError *setCategoryErr = nil;
	NSError *activationErr  = nil;
	[[AVAudioSession sharedInstance]
		setCategory: AVAudioSessionCategoryPlayback
		error: &setCategoryErr];
	[[AVAudioSession sharedInstance]
		setActive: YES
		error: &activationErr];

    return YES;
}

- (UIWindow *)connectToWindowScene:(UIWindowScene *)scene URLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
	BOOL firstConnection = (_emulatorController == nil);
	if (firstConnection)
	{
		screenView = [[SDL_uikitopenglview alloc] initWithFrame:CGRectMake(0, 0, 640, 400)];
		_emulatorController = [[DPEmulatorViewController alloc] init];
		_emulatorController.screenView = screenView;
		self.uiwindow = [[UIWindow alloc] initWithWindowScene:scene];
		self.uiwindow.rootViewController = _emulatorController;
	}
	else
	{
		// SDL retains this window in its driver data. Reattach it rather than replacing it.
		self.uiwindow.windowScene = scene;
	}
	[self.uiwindow makeKeyAndVisible];

	NSURL *packageURL = nil;
	for (UIOpenURLContext *context in URLContexts)
	{
		if (context.URL.isFileURL)
		{
			packageURL = context.URL;
			break;
		}
	}
	#ifndef NDOS_X_HOST
	if (!packageURL && firstConnection && [DPSettings shared].autoOpenLastPackage)
		packageURL = [self openLastURL];
#endif
	if (packageURL)
		[self openPackageURL:packageURL];

	if (!_startupRequested && !_startupCompleted)
	{
		_startupRequested = YES;
		// Preserve the delay needed for the rendering view to be ready before emulation.
#ifdef NDOS_X_HOST
        [self performSelector:@selector(showProfilePicker) withObject:nil afterDelay:1];
#else
        [self performSelector:@selector(startDOS) withObject:nil afterDelay:1];
#endif
	}
	return self.uiwindow;
}


-(void)setWindowTitle:(char *)title
{
    char buf[8];
    NSAssert([NSThread isMainThread], @"Should work in main thread");
    if (strstr(title, "max"))
    {
        sscanf(title, "CPU speed: max %d%% cycles, Frameskip %d", &maxPercent, &frameskip);
        sprintf(buf, "%3d%%", maxPercent);
        cycles = 0;
    } 
    else
    {
        sscanf(title, "CPU speed: %d cycles, Frameskip %d", &cycles, &frameskip);
        sprintf(buf, "%4d", cycles);
        maxPercent = 0;
    }
    
    [_emulatorController updateCpuCycles:@(buf)];
	[_emulatorController updateFrameskip:@(frameskip)];
}

@end
