#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "DPEmulatorViewController.h"
#import "DPGamepad.h"
#import "DPTheme.h"
#import "DPGamepadConfiguration.h"
#import "DPGamepadButtonEditor.h"
#import "NDOSXProfiles.h"
#import "NDOSXHost.h"

@interface NDOSXProfilePicker (TouchTesting)
- (void)start;
@end
@interface DPEmulatorViewController (TouchTesting)
- (void)createFloatingInput:(NSInteger)type;
- (BOOL)removeFloatingInput:(NSInteger)type;
- (DPGamepad *)findGamepad;
- (void)gamepad:(DPGamepad *)gamepad buttonIndex:(DPGamepadButtonIndex)index pressed:(BOOL)pressed;
- (void)showEngineMenu:(id)sender;
@end
@interface DPGamepadJoystick (TouchTesting)
- (void)updateJoystickAxis:(CGPoint)offset;
@end
@interface DPGamepadButtonEditor (TouchTesting)
- (void)cancel;
@end
// Exercise the real multitouch handlers with independent touch identities.
@interface ControlTestTouch : UITouch
@property CGPoint position;
@property UIView *referenceView;
@end
@implementation ControlTestTouch
- (CGPoint)locationInView:(UIView *)view {return [self.referenceView convertPoint:self.position toView:view];}
@end

@interface TouchControlsTests : XCTestCase
@end
@implementation TouchControlsTests
- (BOOL)waitUntil:(BOOL (^)(void))predicate {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:20];
    while (!predicate() && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return predicate();
}
- (DPGamepad *)visibleGamepad:(UIView *)view {
    if ([view isKindOfClass:DPGamepad.class] && !view.hidden) return (DPGamepad *)view;
    for (UIView *child in view.subviews) {DPGamepad *found=[self visibleGamepad:child];if (found) return found;}
    return nil;
}
- (BOOL)containsButton:(NSString *)label inView:(UIView *)view {
    if ([view isKindOfClass:UIButton.class] && [view.accessibilityLabel isEqual:label]) return YES;
    for (UIView *child in view.subviews) if ([self containsButton:label inView:child]) return YES;
    return NO;
}
- (void)attachScreenshot:(NSString *)name view:(UIView *)view {
    // Let rotation, frame presentation, and the toolbar's deferred layout settle.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
    [view layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){[view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];}];
    XCTAttachment *attachment=[XCTAttachment attachmentWithImage:image];
    attachment.name=name;attachment.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:attachment];
}
- (void)testTouchControlsInPortraitAndLandscape {
    AppDelegate *app=(AppDelegate *)UIApplication.sharedApplication.delegate;
    DPEmulatorViewController *emulator=[app valueForKey:@"emulatorController"];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil;}]);
    UINavigationController *picker=(UINavigationController *)emulator.presentedViewController;
    XCTAssertTrue([picker.topViewController isKindOfClass:NDOSXProfilePicker.class]);
    NSString *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path;
    NSString *profile=[documents stringByAppendingPathComponent:@"config/touch-ui.conf"];
    XCTAssertTrue([@"[sdl]\noutput=surface\nwaitonerror=false\nautolock=false\n[cpu]\ncore=normal\ncycles=fixed 20000\n[midi]\nmididevice=none\n[joystick]\njoysticktype=2axis\nautofire=false\n" writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    [(NDOSXProfilePicker *)picker.topViewController refresh];
    [picker.topViewController setValue:@"touch-ui.conf" forKey:@"selectedFilename"];
    [(NDOSXProfilePicker *)picker.topViewController start];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil && ndos_x_joystick_status()==2;}]);
    XCTAssertTrue([[DOSPadEmulator sharedInstance].gamepadConfigFile hasSuffix:@"touch-ui.gamepad.json"]);
    UIWindowScene *scene=emulator.view.window.windowScene;
    if (@available(iOS 16.0,*)) {
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait] errorHandler:nil];
    }
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.view.bounds.size.height>emulator.view.bounds.size.width;}]);
    XCTAssertNil([self visibleGamepad:emulator.view]);
    XCTAssertTrue([self containsButton:@"Engine Menu" inView:emulator.view]);
    XCTAssertTrue([self containsButton:@"Touch controls" inView:emulator.view]);
    // Input enum is private; locate actual Gamepad/Joystick toolbar tags through their stable order.
    const NSInteger gamepadType=1003,joystickType=1004;
    [emulator createFloatingInput:joystickType];
    DPGamepad *pad=[self visibleGamepad:emulator.view];
    XCTAssertNotNil(pad);XCTAssertTrue(pad.stickMode);
    XCTAssertTrue([pad.scene.theme.baseURL.lastPathComponent isEqual:@"ndos-x-controls.idostheme"]);
    CGRect guest=[emulator.screenView.superview convertRect:emulator.screenView.frame toView:emulator.view];
    CGRect controls=[pad.superview convertRect:pad.frame toView:emulator.view];
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(controls),CGRectGetMaxY(guest));
    XCTAssertNotNil(pad.stick.backgroundImage);XCTAssertNotNil(pad.stick.hatImage);
    [self attachScreenshot:@"iPad portrait joystick" view:emulator.view];
    [pad.stick updateJoystickAxis:CGPointMake(40,-30)];
    [pad.stick touchesCancelled:[NSSet set] withEvent:nil];
    XCTAssertTrue(CGPointEqualToPoint(pad.stick.axisPosition,CGPointZero));
    [emulator createFloatingInput:gamepadType];
    XCTAssertFalse(pad.stickMode);
    pad.dpad.currentDirection=DPGamepadDPadDirectionRightUp;
    [pad.dpad touchesCancelled:[NSSet set] withEvent:nil];
    XCTAssertEqual(pad.dpad.currentDirection,DPGamepadDPadDirectionNone);
    DPGamepadButton *first=pad.buttons[0],*second=pad.buttons[1];
    ControlTestTouch *one=[ControlTestTouch new],*two=[ControlTestTouch new];
    one.referenceView=pad;two.referenceView=pad;one.position=first.center;two.position=second.center;
    [pad touchesMoved:[NSSet setWithObjects:one,two,nil] withEvent:nil];
    XCTAssertTrue(first.pressed && second.pressed);
    [pad touchesEnded:[NSSet setWithObject:one] withEvent:nil];
    XCTAssertFalse(first.pressed);XCTAssertTrue(second.pressed);
    [pad touchesCancelled:[NSSet setWithObject:two] withEvent:nil];
    XCTAssertFalse(second.pressed);
    first.hidden=YES;
    XCTAssertFalse([pad pointInside:first.center withEvent:nil]);
    first.hidden=NO;
    pad.editing=YES;
    [emulator gamepad:pad buttonIndex:DP_GAMEPAD_BUTTON_A pressed:NO];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil && !emulator.presentedViewController.isBeingPresented;}]);
    UINavigationController *editor=(UINavigationController *)emulator.presentedViewController;
    XCTAssertTrue([editor.topViewController isKindOfClass:DPGamepadButtonEditor.class]);
    [(DPGamepadButtonEditor *)editor.topViewController cancel];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
    pad.editing=NO;
    XCTAssertTrue([emulator removeFloatingInput:gamepadType]);
    XCTAssertNil([self visibleGamepad:emulator.view]);
    [emulator createFloatingInput:joystickType];
    if (@available(iOS 16.0,*)) {
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft] errorHandler:nil];
    }
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.view.bounds.size.width>emulator.view.bounds.size.height;}]);
    [emulator createFloatingInput:joystickType];
    pad=[self visibleGamepad:emulator.view];XCTAssertTrue(pad.stickMode);
    XCTAssertTrue([self containsButton:@"Engine Menu" inView:emulator.view]);
    [self attachScreenshot:@"iPad landscape joystick" view:emulator.view];
    [pad.stick updateJoystickAxis:CGPointMake(25,25)];
    [emulator showEngineMenu:nil];
    XCTAssertTrue(CGPointEqualToPoint(pad.stick.axisPosition,CGPointZero));
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil;}]);
    [NSFileManager.defaultManager removeItemAtPath:profile error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[DOSPadEmulator sharedInstance].gamepadConfigFile error:nil];
}
@end
