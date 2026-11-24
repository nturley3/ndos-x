#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "DPEmulatorViewController.h"
#import "DPSettings.h"
#import "NDOSXProfiles.h"
#include <math.h>

@interface NDOSXProfilePicker (LandscapeFillTesting)
- (void)start;
@end

@interface DPEmulatorViewController (LandscapeFillTesting)
- (void)createFloatingInput:(NSInteger)type;
- (BOOL)removeFloatingInput:(NSInteger)type;
- (UIView *)findInputView:(NSInteger)type;
@end

@interface LandscapeFillTests : XCTestCase
@end

@implementation LandscapeFillTests

- (BOOL)waitUntil:(BOOL (^)(void))predicate
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!predicate() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return predicate();
}

- (CGRect)guestFrame:(DPEmulatorViewController *)emulator
{
    UIView *screen = emulator.screenView;
    return [screen.superview convertRect:screen.frame toView:emulator.view];
}

- (void)assertGuestFrame:(CGRect)guest matchesRect:(CGRect)expected
{
    XCTAssertEqualWithAccuracy(CGRectGetMinX(guest), CGRectGetMinX(expected), 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(guest), CGRectGetMinY(expected), 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(guest), CGRectGetMaxX(expected), 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(guest), CGRectGetMaxY(expected), 0.01);
}

- (CGRect)scaledRect:(CGRect)rect by:(CGFloat)size
{
    return CGRectInset(rect, CGRectGetWidth(rect) * (1 - size) / 2, CGRectGetHeight(rect) * (1 - size) / 2);
}

- (void)assertSizesForPresetFrame:(CGRect)presetFrame emulator:(DPEmulatorViewController *)emulator bottomStrip:(CGPoint)bottomStrip
{
    for (NSNumber *size in @[@0.5, @0.75, @1.0]) {
        [DPSettings.shared setValue:size forPreferenceKey:@"screen_landscape_size"];
        CGRect expected = [self scaledRect:presetFrame by:size.doubleValue];
        [self assertGuestFrame:[self guestFrame:emulator] matchesRect:expected];
        UIView *hit = [emulator.view hitTest:bottomStrip withEvent:nil];
        XCTAssertEqual(hit == emulator.screenView, CGRectContainsPoint(expected, bottomStrip),
            @"Unexpected bottom-strip hit at size %@ and point %@", size, NSStringFromCGPoint(bottomStrip));
    }
}

- (void)assertCenteredFill:(DPEmulatorViewController *)emulator
{
    CGRect bounds = emulator.view.bounds;
    UIEdgeInsets insets = emulator.view.safeAreaInsets;
    CGRect safe = UIEdgeInsetsInsetRect(bounds, insets);
    CGRect guest = [self guestFrame:emulator];
    CGFloat margin = MAX(insets.top, insets.bottom);
    UIScreen *display = emulator.view.window.windowScene.screen;
    if (CGSizeEqualToSize(display.nativeBounds.size, CGSizeMake(1668, 2420))) {
        // The two-pixel-per-point iPad display mask starts 76 pixels from the edge.
        margin = MAX(margin, 38);
    }
    XCTAssertEqualWithAccuracy(CGRectGetMinY(guest), CGRectGetMinY(bounds) + margin, 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(guest), CGRectGetMaxY(bounds) - margin, 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(guest), CGRectGetMinX(safe), 0.01);
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(guest), CGRectGetMaxX(safe), 0.01);
}

- (void)requestOrientation:(UIInterfaceOrientation)orientation inScene:(UIWindowScene *)scene
{
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *geometry = [[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:1UL << orientation];
        [scene requestGeometryUpdateWithPreferences:geometry errorHandler:nil];
    }
}

- (void)testLandscapeFill
{
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    DPEmulatorViewController *emulator = [app valueForKey:@"emulatorController"];
    XCTAssertTrue([self waitUntil:^BOOL{ return emulator.presentedViewController != nil; }]);
    UINavigationController *navigation = (UINavigationController *)emulator.presentedViewController;
    NDOSXProfilePicker *picker = (NDOSXProfilePicker *)navigation.topViewController;
    XCTAssertTrue([picker isKindOfClass:NDOSXProfilePicker.class]);
    if (![picker isKindOfClass:NDOSXProfilePicker.class]) return;

    NSString *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path;
    NSString *profile = [documents stringByAppendingPathComponent:@"config/landscape-fill-ui.conf"];
    NSString *config = @"[sdl]\noutput=surface\nwaitonerror=false\nautolock=false\n[midi]\nmididevice=none\n";
    XCTAssertTrue([config writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    [picker refresh];
    [picker setValue:@"landscape-fill-ui.conf" forKey:@"selectedFilename"];
    [picker start];
    XCTAssertTrue([self waitUntil:^BOOL{
        return emulator.presentedViewController == nil && emulator.screenView.superview != nil;
    }]);

    DPSettings *settings = DPSettings.shared;
    NSString *scaleKey = @"screen_scale_mode";
    NSString *sizeKey = @"screen_landscape_size";
    NSString *shrinkKey = @"auto_shrink_screen_keyboard_enabled";
    id previousScale = [settings valueForPreferenceKey:scaleKey];
    id previousSize = [settings valueForPreferenceKey:sizeKey];
    id previousShrink = [settings valueForPreferenceKey:shrinkKey];
    UIEdgeInsets previousInsets = emulator.additionalSafeAreaInsets;
    const NSInteger keyboardType = 1001; // TAG_INPUT_KEYBOARD
    UIWindowScene *scene = emulator.view.window.windowScene;
    UIInterfaceOrientation previousOrientation = scene.interfaceOrientation;
    @try {
        [settings setValue:@(DPScreenScaleModeFill) forPreferenceKey:scaleKey];
        [settings setValue:@1 forPreferenceKey:sizeKey];
        [settings setValue:@YES forPreferenceKey:shrinkKey];
        for (NSNumber *direction in @[@(UIInterfaceOrientationLandscapeLeft), @(UIInterfaceOrientationLandscapeRight)]) {
            UIInterfaceOrientation orientation = direction.integerValue;
            [self requestOrientation:orientation inScene:scene];
            BOOL rotated = [self waitUntil:^BOOL{
                return scene.interfaceOrientation == orientation &&
                    CGRectGetWidth(emulator.view.bounds) > CGRectGetHeight(emulator.view.bounds) &&
                    emulator.transitionCoordinator == nil && emulator.view.layer.animationKeys.count == 0;
            }];
            XCTAssertTrue(rotated);
            if (!rotated) continue;
            emulator.additionalSafeAreaInsets = UIEdgeInsetsZero;
            [emulator.view setNeedsLayout];
            [emulator.view layoutIfNeeded];
            [self assertCenteredFill:emulator];
            CGRect nativeSafe = UIEdgeInsetsInsetRect(emulator.view.bounds, emulator.view.safeAreaInsets);
            [settings setValue:@(DPScreenScaleModeFillOriginal) forPreferenceKey:scaleKey];
            [self assertGuestFrame:[self guestFrame:emulator] matchesRect:nativeSafe];
            [settings setValue:@(DPScreenScaleModeFill) forPreferenceKey:scaleKey];

            // Exercise both offsets regardless of the simulator's native safe area.
            UIEdgeInsets extra = orientation == UIInterfaceOrientationLandscapeLeft
                ? UIEdgeInsetsMake(64, 8, 8, 0) : UIEdgeInsetsMake(0, 0, 48, 8);
            emulator.additionalSafeAreaInsets = extra;
            [emulator.view setNeedsLayout];
            [emulator.view layoutIfNeeded];
            UIEdgeInsets insets = emulator.view.safeAreaInsets;
            XCTAssertGreaterThan(fabs(insets.top - insets.bottom), 0.01);
            [self assertCenteredFill:emulator];

            CGRect safe = UIEdgeInsetsInsetRect(emulator.view.bounds, insets);
            CGRect throughBottom = safe;
            throughBottom.size.height += insets.bottom;
            XCTAssertGreaterThan(insets.bottom, 0);
            CGPoint bottomStrip = CGPointMake(CGRectGetMidX(safe), CGRectGetMaxY(safe) + insets.bottom / 2);
            NSDictionary<NSNumber *, NSNumber *> *fitRatios = @{
                @(DPScreenScaleModeAspectFit4x3): @(4.0 / 3.0),
                @(DPScreenScaleModeAspectFit16x10): @(16.0 / 10.0),
                @(DPScreenScaleModeAspectFit16x9): @(16.0 / 9.0)
            };
            for (NSNumber *mode in fitRatios) {
                [settings setValue:mode forPreferenceKey:scaleKey];
                CGRect fit = [self guestFrame:emulator];
                XCTAssertEqualWithAccuracy(CGRectGetWidth(fit) / CGRectGetHeight(fit), fitRatios[mode].doubleValue, 0.01);
                XCTAssertEqualWithAccuracy(CGRectGetMidY(fit), CGRectGetMidY(safe), 0.01);
                [self assertSizesForPresetFrame:fit emulator:emulator bottomStrip:bottomStrip];
            }
            for (NSNumber *mode in @[@(DPScreenScaleModeFillOriginal), @(DPScreenScaleModeFillToBottom), @(DPScreenScaleModeFill)]) {
                [settings setValue:mode forPreferenceKey:scaleKey];
                CGRect fullSize = [self guestFrame:emulator];
                BOOL fillsBottom = mode.integerValue == DPScreenScaleModeFillToBottom;
                if (mode.integerValue == DPScreenScaleModeFill) {
                    [self assertCenteredFill:emulator];
                } else {
                    [self assertGuestFrame:fullSize matchesRect:fillsBottom ? throughBottom : safe];
                }
                if (fillsBottom) XCTAssertFalse(emulator.screenView.superview.clipsToBounds);
                [self assertSizesForPresetFrame:fullSize emulator:emulator bottomStrip:bottomStrip];

                if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    [settings setValue:@0.75 forPreferenceKey:sizeKey];
                    [emulator createFloatingInput:keyboardType];
                    UIView *keyboard = [emulator findInputView:keyboardType];
                    XCTAssertNotNil(keyboard);
                    CGRect keyboardFrame = [keyboard.superview convertRect:keyboard.frame toView:emulator.view];
                    CGRect aboveKeyboard = safe;
                    aboveKeyboard.size.height = CGRectGetMinY(keyboardFrame) - CGRectGetMinY(safe);
                    [self assertGuestFrame:[self guestFrame:emulator] matchesRect:[self scaledRect:aboveKeyboard by:0.75]];
                    XCTAssertTrue([emulator removeFloatingInput:keyboardType]);
                    [self assertGuestFrame:[self guestFrame:emulator] matchesRect:[self scaledRect:fullSize by:0.75]];
                    [settings setValue:@1 forPreferenceKey:sizeKey];
                }
            }
        }

        emulator.additionalSafeAreaInsets = UIEdgeInsetsZero;
        [self requestOrientation:UIInterfaceOrientationPortrait inScene:scene];
        XCTAssertTrue([self waitUntil:^BOOL{
            return scene.interfaceOrientation == UIInterfaceOrientationPortrait &&
                CGRectGetHeight(emulator.view.bounds) > CGRectGetWidth(emulator.view.bounds) &&
                emulator.transitionCoordinator == nil && emulator.view.layer.animationKeys.count == 0;
        }]);
        [emulator.view setNeedsLayout];
        [emulator.view layoutIfNeeded];
        CGRect portraitFrame = [self guestFrame:emulator];
        [settings setValue:@0.5 forPreferenceKey:sizeKey];
        [self assertGuestFrame:[self guestFrame:emulator] matchesRect:portraitFrame];
    } @finally {
        [emulator removeFloatingInput:keyboardType];
        emulator.additionalSafeAreaInsets = previousInsets;
        [settings setValue:previousScale forPreferenceKey:scaleKey];
        [settings setValue:previousSize forPreferenceKey:sizeKey];
        [settings setValue:previousShrink forPreferenceKey:shrinkKey];
        if (previousOrientation != UIInterfaceOrientationUnknown) {
            [self requestOrientation:previousOrientation inScene:scene];
        }
        [NSFileManager.defaultManager removeItemAtPath:profile error:nil];
    }
}

@end
