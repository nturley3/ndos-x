#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "DPEmulatorViewController.h"
#import "DPSettingsViewController.h"
#import "NDOSXHost.h"
#import "NDOSXMenu.h"
#import "NDOSXProfiles.h"

@interface DPEmulatorViewController (TurboSettingsTesting)
- (void)showOption:(id)sender;
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller;
@end
@interface DPSettingsViewController (TurboSettingsTesting)
- (void)done;
@end
@interface NDOSXProfilePicker (TurboSettingsTesting)
- (void)refresh;
- (void)start;
@end

@interface TurboSettingsTests : XCTestCase
@end

@implementation TurboSettingsTests
- (BOOL)waitUntil:(BOOL (^)(void))predicate
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!predicate() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return predicate();
}

- (UISwitch *)openSettings:(DPEmulatorViewController *)emulator
{
    [emulator showOption:nil];
    UINavigationController *navigation = (id)emulator.presentedViewController;
    DPSettingsViewController *sheet = (id)navigation.topViewController;
    [sheet loadViewIfNeeded];
    NSIndexPath *first = [NSIndexPath indexPathForRow:0 inSection:0];
    XCTAssertTrue([self waitUntil:^BOOL{
        return !navigation.isBeingPresented && [sheet.tableView cellForRowAtIndexPath:first] != nil;
    }]);
    UITableViewCell *cell = [sheet.tableView cellForRowAtIndexPath:first];
    XCTAssertEqualObjects(cell.textLabel.text, @"Turbo (fast-forward)");
    XCTAssertEqualObjects(cell.detailTextLabel.text, @"Your machine profile can end Turbo on a keypress or after a timeout.");
    UISwitch *control = (id)cell.accessoryView;
    XCTAssertTrue([self waitUntil:^BOOL{ return control.enabled; }]);
    XCTAssertFalse(ndos_x_send_keyboard(0, 1, SDL_SCANCODE_A));
    return control;
}

- (void)closeSettings:(DPEmulatorViewController *)emulator
{
    UINavigationController *navigation = (id)emulator.presentedViewController;
    [(DPSettingsViewController *)navigation.topViewController done];
    XCTAssertTrue([self waitUntil:^BOOL{ return !emulator.presentedViewController && !ndos_x_settings_paused(); }]);
}

- (void)toggle:(UISwitch *)control
{
    control.on = !control.on;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertFalse(control.enabled);
    XCTAssertTrue([self waitUntil:^BOOL{ return control.enabled; }]);
}

- (void)testTurboAcrossSettingsAndEngineMenu
{
    AppDelegate *app = (id)UIApplication.sharedApplication.delegate;
    DPEmulatorViewController *emulator = [app valueForKey:@"emulatorController"];
    XCTAssertTrue([self waitUntil:^BOOL{ return emulator.presentedViewController != nil; }]);
    UINavigationController *pickerNavigation = (id)emulator.presentedViewController;
    NDOSXProfilePicker *picker = (id)pickerNavigation.topViewController;
    XCTAssertTrue([self waitUntil:^BOOL{ return [[picker valueForKey:@"selectedFilename"] length] > 0; }]);
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *filename = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"conf"];
    NSURL *profile = [[documents URLByAppendingPathComponent:@"config"] URLByAppendingPathComponent:filename];
    NSString *marker = [[filename substringToIndex:8].uppercaseString stringByAppendingString:@".TXT"];
    NSURL *ready = [documents URLByAppendingPathComponent:marker];
    NSString *config = [NSString stringWithFormat:@"[sdl]\nwaitonerror=false\n[cpu]\ncore=normal\ncycles=fixed 20000\nstop turbo after second=5\n[midi]\nmididevice=none\n[autoexec]\nmount c .\nc:\necho ready>%@\n", marker];
    XCTAssertTrue([config writeToURL:profile atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSString *lastProfile = [NSUserDefaults.standardUserDefaults stringForKey:@"NDOSXLastProfile"];
    [self addTeardownBlock:^{
        [NSUserDefaults.standardUserDefaults setObject:lastProfile forKey:@"NDOSXLastProfile"];
        NSURL *mapping = [[profile URLByDeletingPathExtension] URLByAppendingPathExtension:@"gamepad.json"];
        [NSFileManager.defaultManager removeItemAtURL:mapping error:nil];
        [NSFileManager.defaultManager removeItemAtURL:ready error:nil];
        [NSFileManager.defaultManager removeItemAtURL:profile error:nil];
    }];
    [picker refresh];
    [picker setValue:filename forKey:@"selectedFilename"];
    [picker start];
    XCTAssertTrue([self waitUntil:^BOOL{ return !emulator.presentedViewController && [ready checkResourceIsReachableAndReturnError:nil]; }]);

    __block NSArray *snapshot;
    NDOSXMenuCompletion reply = ^(NSArray *items, NSError *error) {
        XCTAssertNil(error);
        snapshot = items;
    };
    NDOSXMenuSession session = ndos_x_menu_open(reply);
    XCTAssertTrue([self waitUntil:^BOOL{ return snapshot != nil; }]);
    snapshot = nil;
    ndos_x_menu_invoke(session, @"mapper_speedup", reply);
    XCTAssertTrue([self waitUntil:^BOOL{ return snapshot != nil; }]);
    ndos_x_menu_close(session);

    UISwitch *control = [self openSettings:emulator];
    XCTAssertFalse(control.on);
    [self toggle:control];
    XCTAssertTrue(control.on);
    [self closeSettings:emulator];
    snapshot = nil;
    session = ndos_x_menu_open(reply);
    XCTAssertTrue([self waitUntil:^BOOL{ return snapshot != nil; }]);
    XCTAssertTrue([NDOSXMenuItem findItem:@"mapper_speedlock2" inItems:snapshot].checked);
    XCTAssertEqualObjects([NDOSXMenuItem findItem:@"mapper_speedup" inItems:snapshot].subtitle, @"After Turbo: 105%");
    snapshot = nil;
    ndos_x_menu_invoke(session, @"mapper_speedlock2", reply);
    XCTAssertTrue([self waitUntil:^BOOL{ return snapshot != nil; }]);
    XCTAssertEqualObjects([NDOSXMenuItem findItem:@"mapper_speedup" inItems:snapshot].subtitle, @"Timing speed: 105%");
    ndos_x_menu_close(session);
    control = [self openSettings:emulator];
    XCTAssertFalse(control.on);

    [self toggle:control];
    [self closeSettings:emulator];
    XCTAssertTrue(ndos_x_send_keyboard(0, 1, SDL_SCANCODE_A));
    XCTAssertTrue(ndos_x_send_keyboard(0, 0, SDL_SCANCODE_A));
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    control = [self openSettings:emulator];
    XCTAssertFalse(control.on);

    [self toggle:control];
    [self closeSettings:emulator];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5.5]];
    control = [self openSettings:emulator];
    XCTAssertFalse(control.on);

    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    XCTAssertFalse(control.enabled);
    XCTAssertTrue([self waitUntil:^BOOL{ return control.enabled; }]);
    control.on = YES;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertFalse(control.enabled);
    UINavigationController *navigation = (id)emulator.presentedViewController;
    UIPresentationController *presentation = navigation.presentationController;
    __block BOOL dismissed = NO;
    [navigation dismissViewControllerAnimated:NO completion:^{ dismissed = YES; }];
    [emulator presentationControllerDidDismiss:presentation];
    XCTAssertFalse(ndos_x_settings_paused());
    XCTAssertTrue([self waitUntil:^BOOL{ return dismissed && !emulator.presentedViewController; }]);
    control = [self openSettings:emulator];
    ndos_x_request_stop();
    XCTAssertTrue([self waitUntil:^BOOL{ return !control.enabled; }]);
    [self closeSettings:emulator];
}
@end
