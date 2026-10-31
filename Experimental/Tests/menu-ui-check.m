#import <XCTest/XCTest.h>
#import "NDOSXMenu.h"
#import "NDOSXHost.h"
#import "NDOSXProfiles.h"
#import "DPEmulatorViewController.h"
#import "AppDelegate.h"

@interface NDOSXProfilePicker (MenuTesting)
- (void)start;
- (void)refresh;
@end
@interface DPEmulatorViewController (MenuTesting)
- (void)showEngineMenu:(id)sender;
- (void)registerButton:(UIButton *)button name:(NSString *)name;
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller;
@end
@interface NDOSXMenuViewController (MenuTesting)
- (void)done:(id)sender;
@end

@interface UITableViewController (ISOBrowserTesting)
- (void)cancel:(id)sender;
@end

@interface EngineMenuTests : XCTestCase
@end
@implementation EngineMenuTests
- (BOOL)waitUntil:(BOOL (^)(void))predicate {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
    while (!predicate() && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    return predicate();
}
- (NSIndexPath *)rowNamed:(NSString *)title inMenu:(UITableViewController *)menu {
    [menu loadViewIfNeeded];
    for (NSInteger section=0;section<[menu numberOfSectionsInTableView:menu.tableView];section++)
        for (NSInteger row=0;row<[menu tableView:menu.tableView numberOfRowsInSection:section];row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
            if ([[menu tableView:menu.tableView cellForRowAtIndexPath:path].textLabel.text isEqualToString:title]) return path;
        }
    return nil;
}
- (NSIndexPath *)rowWithEngineName:(NSString *)name inMenu:(NDOSXMenuViewController *)menu {
    [menu loadViewIfNeeded];
    NSArray<NSArray<NDOSXMenuItem *> *> *groups=[menu valueForKey:@"groups"];
    for (NSUInteger section=0;section<groups.count;section++)
        for (NSUInteger row=0;row<groups[section].count;row++)
            if ([groups[section][row].name isEqual:name])
                return [NSIndexPath indexPathForRow:row inSection:section];
    return nil;
}
- (void)writeISOAtPath:(NSString *)path {
    NSMutableData *image=[NSMutableData dataWithLength:24*2048];
    unsigned char *bytes=image.mutableBytes,*pvd=bytes+16*2048;
    pvd[0]=1;memcpy(pvd+1,"CD001",5);pvd[6]=1;
    memset(pvd+40,' ',32);memcpy(pvd+40,"UI_DISC",7);
    pvd[80]=24;pvd[87]=24;pvd[120]=1;pvd[123]=1;
    pvd[124]=1;pvd[127]=1;pvd[129]=8;pvd[130]=8;
    unsigned char *entry=pvd+156;
    entry[0]=34;entry[2]=18;entry[9]=18;entry[11]=8;entry[14]=8;
    entry[25]=2;entry[28]=1;entry[31]=1;entry[32]=1;
    memcpy(bytes+18*2048,entry,34);
    unsigned char *end=bytes+17*2048;end[0]=255;memcpy(end+1,"CD001",5);end[6]=1;
    XCTAssertTrue([image writeToFile:path atomically:YES]);
}
- (void)testNativeMenuLifecycleAndCommands {
    AppDelegate *app=(AppDelegate *)UIApplication.sharedApplication.delegate;
    DPEmulatorViewController *emulator=[app valueForKey:@"emulatorController"];
    XCTAssertNotNil(emulator);
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil;}]);
    UINavigationController *picker=(UINavigationController *)emulator.presentedViewController;
    XCTAssertTrue([picker.topViewController isKindOfClass:NDOSXProfilePicker.class]);
    XCTAssertTrue([self waitUntil:^BOOL{
        return [[picker.topViewController valueForKey:@"selectedFilename"] length]>0;
    }]);
    NSString *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path;
    NSString *profile=[documents stringByAppendingPathComponent:@"config/iso-ui.conf"];
    NSString *fixtures=[documents stringByAppendingPathComponent:@"ISOBrowserTest"];
    [NSFileManager.defaultManager removeItemAtPath:[fixtures stringByAppendingPathComponent:@"READY.TXT"] error:nil];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:fixtures withIntermediateDirectories:YES attributes:nil error:nil]);
    [self writeISOAtPath:[fixtures stringByAppendingPathComponent:@"Good.iso"]];
    XCTAssertTrue([@"broken" writeToFile:[fixtures stringByAppendingPathComponent:@"Bad.ISO"] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    XCTAssertTrue([@"ignored" writeToFile:[fixtures stringByAppendingPathComponent:@"Ignored.cue"] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    XCTAssertTrue([@"[sdl]\noutput=surface\nwaitonerror=false\nautolock=false\n[cpu]\ncore=normal\ncycles=fixed 20000\n[midi]\nmididevice=none\n[autoexec]\nmount c \"ISOBrowserTest\"\nc:\nimgmount d empty -t iso\necho ready>READY.TXT\n"
        writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    [(NDOSXProfilePicker *)picker.topViewController refresh];
    [picker.topViewController setValue:@"iso-ui.conf" forKey:@"selectedFilename"];
    [(NDOSXProfilePicker *)picker.topViewController start];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
    XCTAssertTrue([self waitUntil:^BOOL{return [NSFileManager.defaultManager fileExistsAtPath:[fixtures stringByAppendingPathComponent:@"READY.TXT"]];}]);
    // Verify the portrait control strip routes its former controller control to
    // the engine menu, while the shared non-X target retains its own controls.
    UIButton *portrait=[UIButton buttonWithType:UIButtonTypeSystem];
    [emulator registerButton:portrait name:@"gamepad-toggle"];
    XCTAssertEqualObjects(portrait.accessibilityLabel,@"Engine Menu");
    XCTAssertTrue([[portrait actionsForTarget:emulator forControlEvent:UIControlEventTouchUpInside]
        containsObject:@"showEngineMenu:"]);
    [emulator showEngineMenu:nil];
    UINavigationController *navigation=(UINavigationController *)emulator.presentedViewController;
    NDOSXMenuViewController *root=(NDOSXMenuViewController *)navigation.topViewController;
    XCTAssertTrue([root isKindOfClass:NDOSXMenuViewController.class]);
    if (![root isKindOfClass:NDOSXMenuViewController.class]) return;
    XCTAssertTrue([self waitUntil:^BOOL{return [self rowNamed:@"Sound" inMenu:root]!=nil;}]);
    XCTAssertTrue([self waitUntil:^BOOL{return !navigation.isBeingPresented && navigation.transitionCoordinator==nil;}]);
    // Navigate the upstream drive hierarchy to the native, app-local ISO browser.
    NSIndexPath *drives=[self rowWithEngineName:@"DriveMenu" inMenu:root];
    XCTAssertNotNil(drives);
    [root tableView:root.tableView didSelectRowAtIndexPath:drives];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=root && navigation.transitionCoordinator==nil;}]);
    NDOSXMenuViewController *driveMenu=(NDOSXMenuViewController *)navigation.topViewController;
    NSIndexPath *drive=[self rowWithEngineName:@"DriveD" inMenu:driveMenu];
    XCTAssertNotNil(drive);if (!drive) return;
    [driveMenu tableView:driveMenu.tableView didSelectRowAtIndexPath:drive];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=driveMenu && navigation.transitionCoordinator==nil;}]);
    NDOSXMenuViewController *cdMenu=(NDOSXMenuViewController *)navigation.topViewController;
    NSIndexPath *mount=[self rowWithEngineName:@"drive_D_mountimg" inMenu:cdMenu];
    XCTAssertNotNil(mount);if (!mount) return;
    XCTAssertFalse([cdMenu tableView:cdMenu.tableView cellForRowAtIndexPath:mount].accessibilityTraits&UIAccessibilityTraitNotEnabled);
    NSIndexPath *eject=[self rowWithEngineName:@"drive_D_unmount" inMenu:cdMenu];
    XCTAssertNotNil(eject);if (!eject) return;
    XCTAssertEqualObjects([cdMenu tableView:cdMenu.tableView cellForRowAtIndexPath:eject].textLabel.text,@"Eject disc");
    [cdMenu tableView:cdMenu.tableView didSelectRowAtIndexPath:eject];
    XCTAssertTrue([self waitUntil:^BOOL{return ![[root valueForKey:@"busy"] boolValue];}]);
    XCTAssertNil([root valueForKey:@"status"]);
    XCTAssertNil(navigation.presentedViewController);
    XCTAssertFalse(ndos_x_send_keyboard(0,1,SDL_SCANCODE_A));
    [cdMenu tableView:cdMenu.tableView didSelectRowAtIndexPath:mount];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=cdMenu && navigation.transitionCoordinator==nil;}]);
    UITableViewController *browser=(UITableViewController *)navigation.topViewController;
    XCTAssertEqualObjects(browser.title,@"Choose ISO");
    XCTAssertFalse(ndos_x_send_keyboard(0,1,SDL_SCANCODE_A));
    [browser cancel:nil];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController==cdMenu && navigation.transitionCoordinator==nil;}]);
    XCTAssertFalse(ndos_x_send_keyboard(0,1,SDL_SCANCODE_A));
    [cdMenu tableView:cdMenu.tableView didSelectRowAtIndexPath:mount];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=cdMenu && navigation.transitionCoordinator==nil;}]);
    browser=(UITableViewController *)navigation.topViewController;
    NSIndexPath *folder=[self rowNamed:@"ISOBrowserTest" inMenu:browser];
    XCTAssertNotNil(folder);
    [browser tableView:browser.tableView didSelectRowAtIndexPath:folder];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=browser && navigation.transitionCoordinator==nil;}]);
    browser=(UITableViewController *)navigation.topViewController;
    XCTAssertNil([self rowNamed:@"Ignored.cue" inMenu:browser]);
    NSIndexPath *goodISO=[self rowNamed:@"Good.iso" inMenu:browser];
    XCTAssertNotNil(goodISO);if (!goodISO) return;
    [browser tableView:browser.tableView didSelectRowAtIndexPath:goodISO];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController==cdMenu && navigation.transitionCoordinator==nil && ![[root valueForKey:@"busy"] boolValue];}]);
    XCTAssertNil([root valueForKey:@"status"]);
    XCTAssertNil(navigation.presentedViewController);
    [cdMenu tableView:cdMenu.tableView didSelectRowAtIndexPath:eject];
    XCTAssertTrue([self waitUntil:^BOOL{return ![[root valueForKey:@"busy"] boolValue];}]);
    XCTAssertNil([root valueForKey:@"status"]);
    XCTAssertFalse([cdMenu tableView:cdMenu.tableView cellForRowAtIndexPath:mount].accessibilityTraits&UIAccessibilityTraitNotEnabled);
    [cdMenu tableView:cdMenu.tableView didSelectRowAtIndexPath:mount];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=cdMenu && navigation.transitionCoordinator==nil;}]);
    browser=(UITableViewController *)navigation.topViewController;
    folder=[self rowNamed:@"ISOBrowserTest" inMenu:browser];
    [browser tableView:browser.tableView didSelectRowAtIndexPath:folder];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=browser && navigation.transitionCoordinator==nil;}]);
    browser=(UITableViewController *)navigation.topViewController;
    NSIndexPath *badISO=[self rowNamed:@"Bad.ISO" inMenu:browser];
    XCTAssertNotNil(badISO);
    [browser tableView:browser.tableView didSelectRowAtIndexPath:badISO];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController==cdMenu && cdMenu.presentedViewController!=nil;}]);
    XCTAssertEqualObjects(((UIAlertController *)cdMenu.presentedViewController).title,@"Could not change disc");
    if (!cdMenu.presentedViewController) return;
    XCTAssertTrue([self waitUntil:^BOOL{return !cdMenu.presentedViewController.isBeingPresented && cdMenu.presentedViewController.transitionCoordinator==nil;}]);
    __block BOOL alertDismissed=NO;
    [cdMenu dismissViewControllerAnimated:NO completion:^{alertDismissed=YES;}];
    XCTAssertTrue([self waitUntil:^BOOL{return alertDismissed;}]);
    XCTAssertFalse(ndos_x_send_keyboard(0,1,SDL_SCANCODE_A));
    [navigation popToRootViewControllerAnimated:NO];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController==root && navigation.transitionCoordinator==nil;}]);
    NSIndexPath *sound=[self rowNamed:@"Sound" inMenu:root];
    [root tableView:root.tableView didSelectRowAtIndexPath:sound];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=root && navigation.transitionCoordinator==nil;}]);
    NDOSXMenuViewController *submenu=(NDOSXMenuViewController *)navigation.topViewController;
    NSIndexPath *mute=[self rowNamed:@"Mute" inMenu:submenu];
    XCTAssertNotNil(mute);
    BOOL checked=[submenu tableView:submenu.tableView cellForRowAtIndexPath:mute].accessoryType==UITableViewCellAccessoryCheckmark;
    [submenu tableView:submenu.tableView didSelectRowAtIndexPath:mute];
    XCTAssertTrue([self waitUntil:^BOOL{
        UITableViewCell *cell=[submenu tableView:submenu.tableView cellForRowAtIndexPath:mute];
        return (cell.accessoryType==UITableViewCellAccessoryCheckmark)!=checked;
    }]);
    XCTAssertEqual(emulator.presentedViewController,navigation);
    [navigation popToRootViewControllerAnimated:NO];
    NSIndexPath *main=[self rowNamed:@"Main" inMenu:root];
    [root tableView:root.tableView didSelectRowAtIndexPath:main];
    XCTAssertTrue([self waitUntil:^BOOL{return navigation.topViewController!=root && navigation.transitionCoordinator==nil;}]);
    submenu=(NDOSXMenuViewController *)navigation.topViewController;
    [submenu loadViewIfNeeded];
    // Main contains unsupported desktop commands and still remains browsable.
    XCTAssertGreaterThan([submenu numberOfSectionsInTableView:submenu.tableView],0);
    BOOL unavailable=NO;
    for (NSInteger section=0;section<[submenu numberOfSectionsInTableView:submenu.tableView];section++)
        for (NSInteger row=0;row<[submenu tableView:submenu.tableView numberOfRowsInSection:section];row++) {
            UITableViewCell *cell=[submenu tableView:submenu.tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:row inSection:section]];
            if (cell.accessibilityTraits&UIAccessibilityTraitNotEnabled) {
                unavailable=YES;XCTAssertGreaterThan(cell.detailTextLabel.text.length,0);
            }
        }
    XCTAssertTrue(unavailable);
    XCTAttachment *image=[XCTAttachment attachmentWithImage:[self screenshot:navigation.view]];
    image.name=@"Native engine menu";image.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:image];
    if (@available(iOS 16.0, *)) {
        UIWindowScene *scene=emulator.view.window.windowScene;
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft] errorHandler:nil];
        XCTAssertTrue([self waitUntil:^BOOL{return emulator.view.bounds.size.width>emulator.view.bounds.size.height;}]);
        XCTAssertTrue([self containsEngineButton:emulator.view]);
        XCTAttachment *landscape=[XCTAttachment attachmentWithImage:[self screenshot:navigation.view]];
        landscape.name=@"Native engine menu landscape";
        landscape.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:landscape];
    }
    ndos_x_set_scene_paused(1);
    [submenu done:nil];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
    XCTAssertEqualObjects([emulator valueForKey:@"settingsPresented"],@NO);
    XCTAssertFalse(ndos_x_send_keyboard(0,1,SDL_SCANCODE_A));
    ndos_x_set_scene_paused(0);
    [emulator showEngineMenu:nil];
    navigation=(UINavigationController *)emulator.presentedViewController;
    root=(NDOSXMenuViewController *)navigation.topViewController;
    XCTAssertTrue([self waitUntil:^BOOL{return [self rowNamed:@"Sound" inMenu:root]!=nil;}]);
    // Exercise the same callback UIKit sends after an interactive dismissal.
    [navigation dismissViewControllerAnimated:NO completion:nil];
    [emulator presentationControllerDidDismiss:navigation.presentationController];
    XCTAssertEqualObjects([emulator valueForKey:@"settingsPresented"],@NO);
    [emulator showEngineMenu:nil];
    navigation=(UINavigationController *)emulator.presentedViewController;
    root=(NDOSXMenuViewController *)navigation.topViewController;
    XCTAssertTrue([self waitUntil:^BOOL{return [self rowNamed:@"Sound" inMenu:root]!=nil;}]);
    ndos_x_request_stop();
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
    XCTAssertEqualObjects([emulator valueForKey:@"settingsPresented"],@NO);
    [NSFileManager.defaultManager removeItemAtPath:fixtures error:nil];
    [NSFileManager.defaultManager removeItemAtPath:profile error:nil];
}
- (BOOL)containsEngineButton:(UIView *)view {
    if ([view isKindOfClass:UIButton.class] && [view.accessibilityLabel isEqualToString:@"Engine Menu"]) return YES;
    for (UIView *child in view.subviews) if ([self containsEngineButton:child]) return YES;
    return NO;
}
- (UIImage *)screenshot:(UIView *)view {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
}
@end
