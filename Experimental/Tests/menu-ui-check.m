#import <XCTest/XCTest.h>
#import "NDOSXMenu.h"
#import "NDOSXHost.h"
#import "NDOSXProfiles.h"
#import "DPEmulatorViewController.h"
#import "AppDelegate.h"

@interface NDOSXProfilePicker (MenuTesting)
- (void)start;
@end
@interface DPEmulatorViewController (MenuTesting)
- (void)showEngineMenu:(id)sender;
- (void)registerButton:(UIButton *)button name:(NSString *)name;
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller;
@end
@interface NDOSXMenuViewController (MenuTesting)
- (void)done:(id)sender;
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
- (NSIndexPath *)rowNamed:(NSString *)title inMenu:(NDOSXMenuViewController *)menu {
    [menu loadViewIfNeeded];
    for (NSInteger section=0;section<[menu numberOfSectionsInTableView:menu.tableView];section++)
        for (NSInteger row=0;row<[menu tableView:menu.tableView numberOfRowsInSection:section];row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
            if ([[menu tableView:menu.tableView cellForRowAtIndexPath:path].textLabel.text isEqualToString:title]) return path;
        }
    return nil;
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
    [(NDOSXProfilePicker *)picker.topViewController start];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
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
