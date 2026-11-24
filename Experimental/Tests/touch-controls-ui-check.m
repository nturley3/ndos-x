#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "DPEmulatorViewController.h"
#import "DPGamepad.h"
#import "DPGamepadLayout.h"
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
@interface DPGamepadLayout (TouchTesting)
- (void)beginEditingLayout;
- (void)beginEditingBindings;
- (void)finishEditingBindings;
- (void)restoreDefaults;
- (void)save;
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
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TouchControlLayout.Portrait"];
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
    [pad.controlLayout reloadPositions];
    XCTAssertTrue([pad.scene.theme.baseURL.lastPathComponent isEqual:@"ndos-x-controls.idostheme"]);
    CGRect guest=[emulator.screenView.superview convertRect:emulator.screenView.frame toView:emulator.view];
    CGRect controls=[pad convertRect:pad.stick.frame toView:emulator.view];
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(controls),CGRectGetMaxY(guest));
    XCTAssertNotNil(pad.stick.backgroundImage);XCTAssertNotNil(pad.stick.hatImage);
    [self attachScreenshot:@"Portrait joystick" view:emulator.view];
    CGPoint initial = pad.stick.center;
    DPGamepadButton *shoulderButton = nil;
    DPGamepadButton *actionButton = nil;
    for (DPGamepadButton *button in pad.buttons) {
        if (button.buttonIndex == DP_GAMEPAD_BUTTON_L1) shoulderButton = button;
        if (button.buttonIndex == DP_GAMEPAD_BUTTON_A) actionButton = button;
    }
    XCTAssertNotNil(shoulderButton);
    XCTAssertNotNil(actionButton);
    CGPoint shoulder = shoulderButton.center;
    CGFloat travel = CGRectGetWidth(pad.stick.bounds) * .4;
    XCTAssertGreaterThan(initial.x - travel, 20);
    XCTAssertGreaterThan(CGRectGetHeight(pad.bounds) - initial.y - travel, 20);
    [pad.stick updateJoystickAxis:CGPointMake(-travel, travel)];
    XCTAssertEqualWithAccuracy(pad.stick.axisPosition.x, -1, .001);
    XCTAssertEqualWithAccuracy(pad.stick.axisPosition.y, 1, .001);
    [pad.controlLayout beginEditingLayout];
    XCTAssertEqual([emulator.view hitTest:[pad convertPoint:initial toView:emulator.view] withEvent:nil], pad.controlLayout);
    for (UIView *button in pad.buttons) XCTAssertFalse(button.hidden);
    ControlTestTouch *drag = [ControlTestTouch new];
    drag.referenceView = pad;
    NSSet *finger = [NSSet setWithObject:drag];
    drag.position = initial;
    [pad.controlLayout touchesBegan:finger withEvent:nil];
    drag.position = [emulator.view convertPoint:CGPointMake(CGRectGetMaxX(guest) - initial.x, CGRectGetMidY(guest)) toView:pad];
    [pad.controlLayout touchesEnded:finger withEvent:nil];
    CGPoint moved = pad.stick.center;
    XCTAssertLessThan(moved.y, initial.y - 20);
    XCTAssertEqualWithAccuracy(shoulderButton.center.y - shoulder.y, moved.y - initial.y, .01);
    XCTAssertTrue(CGPointEqualToPoint(pad.stick.axisPosition, CGPointZero));
    drag.position = moved;
    [pad.controlLayout touchesBegan:finger withEvent:nil];
    drag.position = CGPointMake(-100, -100);
    [pad.controlLayout touchesEnded:finger withEvent:nil];
    XCTAssertEqualWithAccuracy(pad.stick.center.y, moved.y, .01);
    drag.position = actionButton.center;
    [pad.controlLayout touchesBegan:finger withEvent:nil];
    drag.position = moved;
    [pad.controlLayout touchesEnded:finger withEvent:nil];
    XCTAssertGreaterThan(actionButton.center.y, moved.y);
    drag.position = actionButton.center;
    [pad.controlLayout touchesBegan:finger withEvent:nil];
    drag.position = CGPointMake(initial.x, moved.y + actionButton.center.y - initial.y);
    [pad.controlLayout touchesEnded:finger withEvent:nil];
    XCTAssertEqualWithAccuracy(actionButton.center.x, initial.x, .01);
    XCTAssertLessThan(actionButton.center.x, moved.x);
    [pad.controlLayout save];
    XCTAssertEqual([pad hitTest:moved withEvent:nil], pad.stick);
    CGPoint guestGap = CGPointMake(CGRectGetMidX(guest), CGRectGetMinY(guest) + 5);
    UIView *gapHit = [emulator.view hitTest:guestGap withEvent:nil];
    XCTAssertTrue([gapHit isDescendantOfView:emulator.screenView]);
    [pad.controlLayout beginEditingLayout];
    [pad.controlLayout restoreDefaults];
    XCTAssertEqualWithAccuracy(pad.stick.center.y, initial.y, .01);
    [pad.controlLayout cancel];
    XCTAssertEqualWithAccuracy(pad.stick.center.y, moved.y, .01);
    [pad.stick updateJoystickAxis:CGPointMake(40,-30)];
    [pad.stick touchesCancelled:[NSSet set] withEvent:nil];
    XCTAssertTrue(CGPointEqualToPoint(pad.stick.axisPosition,CGPointZero));
    [emulator createFloatingInput:gamepadType];
    XCTAssertFalse(pad.stickMode);
    XCTAssertEqualWithAccuracy(pad.dpad.center.y, moved.y, .01);
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
    [pad.controlLayout beginEditingBindings];
    [emulator gamepad:pad buttonIndex:DP_GAMEPAD_BUTTON_A pressed:NO];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil && !emulator.presentedViewController.isBeingPresented;}]);
    UINavigationController *editor=(UINavigationController *)emulator.presentedViewController;
    XCTAssertTrue([editor.topViewController isKindOfClass:DPGamepadButtonEditor.class]);
    [(DPGamepadButtonEditor *)editor.topViewController cancel];
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController==nil;}]);
    [pad.controlLayout finishEditingBindings];
    XCTAssertTrue([emulator removeFloatingInput:gamepadType]);
    XCTAssertNil([self visibleGamepad:emulator.view]);
    [emulator createFloatingInput:joystickType];
    DPGamepad *portraitPad = [self visibleGamepad:emulator.view];
    XCTAssertTrue(portraitPad.stickMode);
    [portraitPad.stick updateJoystickAxis:CGPointMake(25,25)];
    [portraitPad.controlLayout beginEditingLayout];
    [portraitPad.controlLayout restoreDefaults];
    if (@available(iOS 16.0,*)) {
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft] errorHandler:nil];
    }
    XCTAssertTrue([self waitUntil:^BOOL{
        DPGamepad *landscapePad = [self visibleGamepad:emulator.view];
        return emulator.view.bounds.size.width > emulator.view.bounds.size.height &&
            landscapePad == nil && portraitPad.controlLayout.superview == nil;
    }]);
    [emulator createFloatingInput:joystickType];
    pad = [self visibleGamepad:emulator.view];
    XCTAssertTrue(pad.stickMode);
    CGFloat landscapeTravel = CGRectGetWidth(pad.stick.bounds) * .4;
    XCTAssertGreaterThan(pad.stick.center.x - landscapeTravel, 20);
    XCTAssertGreaterThan(CGRectGetHeight(pad.bounds) - pad.stick.center.y - landscapeTravel, 20);
    NSLog(@"Stick clearance at full left/down (points): portrait %.1f/%.1f, landscape %.1f/%.1f",
          initial.x - travel, CGRectGetHeight(portraitPad.bounds) - initial.y - travel,
          pad.stick.center.x - landscapeTravel, CGRectGetHeight(pad.bounds) - pad.stick.center.y - landscapeTravel);
    XCTAssertTrue(CGPointEqualToPoint(portraitPad.stick.axisPosition,CGPointZero));
    XCTAssertTrue(CGPointEqualToPoint(pad.stick.axisPosition,CGPointZero));
    XCTAssertTrue([self containsButton:@"Engine Menu" inView:emulator.view]);
    [self attachScreenshot:@"Landscape joystick" view:emulator.view];
    if (@available(iOS 16.0,*)) {
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait] errorHandler:nil];
    }
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.view.bounds.size.height > emulator.view.bounds.size.width && ![self visibleGamepad:emulator.view];}]);
    [emulator createFloatingInput:gamepadType];
    DPGamepad *reopened = [self visibleGamepad:emulator.view];
    XCTAssertEqualWithAccuracy(reopened.dpad.center.x, moved.x, .01);
    XCTAssertEqualWithAccuracy(reopened.dpad.center.y, moved.y, .01);
    [reopened.controlLayout beginEditingLayout];
    [reopened.controlLayout restoreDefaults];
    [reopened.controlLayout save];
    XCTAssertNil([NSUserDefaults.standardUserDefaults objectForKey:@"TouchControlLayout.Portrait"]);
    [emulator createFloatingInput:joystickType];
    [reopened.stick updateJoystickAxis:CGPointMake(25,25)];
    [emulator showEngineMenu:nil];
    XCTAssertTrue(CGPointEqualToPoint(reopened.stick.axisPosition,CGPointZero));
    XCTAssertTrue([self waitUntil:^BOOL{return emulator.presentedViewController!=nil;}]);
    [NSFileManager.defaultManager removeItemAtPath:profile error:nil];
    [NSFileManager.defaultManager removeItemAtPath:[DOSPadEmulator sharedInstance].gamepadConfigFile error:nil];
}
@end
