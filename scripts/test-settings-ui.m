#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "DPSettingsViewController.h"
#import "DPEmulatorViewController.h"
#import "AppDelegate.h"
#import "FloatPanel.h"
#import "DPThemeScene.h"

extern BOOL dospad_settings_open(void);
extern int dospad_pause_flag;
extern void dospad_resume(void);

@interface DPEmulatorViewController (Testing)
- (void)showOption:(id)sender;
- (void)finishSettings;
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller;
- (UIView *)createSceneView:(DPThemeScene *)scene frame:(CGRect)frame;
- (void)didSettingsChanged:(NSNotification *)note;
- (void)refreshFullscreenPanel;
@end

@interface TestFloatPanel : FloatPanel
@property (nonatomic) BOOL reduceMotion;
@property (nonatomic) NSUInteger hideCalls;
@end
@implementation TestFloatPanel
- (BOOL)reduceMotionEnabled { return self.reduceMotion; }
- (void)hideContent
{
    self.hideCalls++;
    [super hideContent];
}
@end

@interface SettingsTests : XCTestCase
@end
@implementation SettingsTests
- (void)waitSeconds:(NSTimeInterval)seconds
{
    XCTestExpectation *delay = [self expectationWithDescription:@"Toolbar countdown"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [delay fulfill]; });
    [self waitForExpectations:@[delay] timeout:seconds + 3];
}
- (void)testToolbarTimers
{
    BOOL animations = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 700, 47)];
    TestFloatPanel *panel = [[TestFloatPanel alloc] initWithFrame:container.bounds];
    [container addSubview:panel];
    @try {
        [panel applyAutoHideDelay:0.3];
        XCTAssertFalse(panel.isCollapsed);
        [panel showContent];
        [panel applyAutoHideDelay:0];
        [self waitSeconds:0.5];
        XCTAssertEqual(panel.hideCalls, 0u);
        XCTAssertFalse(panel.isCollapsed);

        [panel applyAutoHideDelay:0.3];
        [self waitSeconds:0.1];
        [panel applyAutoHideDelay:0.8];
        [self waitSeconds:0.4];
        XCTAssertEqual(panel.hideCalls, 0u); // Old short timer was cancelled.
        [self waitSeconds:0.6];
        XCTAssertEqual(panel.hideCalls, 1u);
        XCTAssertTrue(panel.isCollapsed);
        [panel applyAutoHideDelay:0.1];
        [self waitSeconds:0.3];
        XCTAssertEqual(panel.hideCalls, 1u); // Hidden content has no countdown.

        [panel applyAutoHideDelay:0];
        XCTAssertTrue(panel.isCollapsed); // Never does not undo manual/timed collapse.
        [panel showContent];
        UIButton *item = [UIButton buttonWithType:UIButtonTypeSystem];
        [panel setItems:@[item]];
        [panel applyAutoHideDelay:0.6];
        [self waitSeconds:0.3];
        [item sendActionsForControlEvents:UIControlEventTouchUpInside];
        [self waitSeconds:0.4];
        XCTAssertEqual(panel.hideCalls, 1u); // Toolbar action restarted timer.
        [self waitSeconds:0.4];
        XCTAssertEqual(panel.hideCalls, 2u);

        [panel showContent];
        [panel applyAutoHideDelay:0.6];
        [self waitSeconds:0.3];
        // Input actions replace their controls; the replacement must restart the timer.
        [panel setItems:@[[UIButton buttonWithType:UIButtonTypeSystem]]];
        [self waitSeconds:0.4];
        XCTAssertEqual(panel.hideCalls, 2u);
        [self waitSeconds:0.3];
        XCTAssertEqual(panel.hideCalls, 3u);
        [panel showContent];
        [panel removeFromSuperview];
        [self waitSeconds:0.8];
        XCTAssertEqual(panel.hideCalls, 3u); // Removed panel has no pending hide.
    } @finally {
        [panel removeFromSuperview];
        [UIView setAnimationsEnabled:animations];
    }
}
- (void)testToolbarHitTargetsAndNarrowLayout
{
    for (NSNumber *width in @[@700, @480, @250]) {
        FloatPanel *panel = [[FloatPanel alloc] initWithFrame:CGRectMake(0, 0, width.doubleValue, 44)];
        [panel applyAutoHideDelay:0];
        NSMutableArray *buttons = [NSMutableArray array];
        for (int i = 0; i < 7; i++) [buttons addObject:[UIButton buttonWithType:UIButtonTypeSystem]];
        [panel setItems:buttons];
        [panel layoutIfNeeded];
        UIScrollView *row = (UIScrollView *)panel.contentView;
        for (UIButton *button in buttons) {
            XCTAssertGreaterThanOrEqual(button.bounds.size.width, 44);
            XCTAssertGreaterThanOrEqual(button.bounds.size.height, 44);
        }
        XCTAssertEqual(row.scrollEnabled, width.doubleValue - 44 < 7 * 44);
        XCTAssertTrue(CGRectContainsRect(panel.bounds, panel.collapseButton.frame));
        CGPoint arrow = panel.collapseButton.center;
        XCTAssertEqual([panel hitTest:arrow withEvent:nil], panel.collapseButton);
        UIButton *first = buttons.firstObject;
        CGPoint target = [first convertPoint:CGPointMake(22, 22) toView:panel];
        XCTAssertEqual([panel hitTest:target withEvent:nil], first);
        if (!row.scrollEnabled) {
            CGPoint gap = CGPointMake(CGRectGetMaxX(first.frame) + 1, 22);
            XCTAssertNil([panel hitTest:gap withEvent:nil]);
        }
        [panel setCollapsed:YES animated:NO];
        XCTAssertTrue(panel.contentView.accessibilityElementsHidden);
        XCTAssertNil([panel hitTest:target withEvent:nil]);
        XCTAssertEqual([panel hitTest:arrow withEvent:nil], panel.collapseButton);
        [panel setCollapsed:NO animated:NO];
        XCTAssertFalse(panel.contentView.accessibilityElementsHidden);
        XCTAssertEqual([panel hitTest:target withEvent:nil], first);
    }
}

- (void)testToolbarInterruptedAnimation
{
    FloatPanel *panel = [[FloatPanel alloc] initWithFrame:CGRectMake(0, 0, 700, 44)];
    [panel applyAutoHideDelay:0];
    [panel setItems:@[[UIButton buttonWithType:UIButtonTypeSystem]]];
    [panel hideContent];
    [self waitSeconds:0.1];
    [panel showContent];
    [self waitSeconds:0.4];
    XCTAssertFalse(panel.isCollapsed);
    XCTAssertEqualWithAccuracy(panel.contentView.alpha, 1, 0.01);
    XCTAssertTrue(CGAffineTransformIsIdentity(panel.contentView.transform));
    [panel hideContent];
    [self waitSeconds:0.4];
    XCTAssertTrue(panel.isCollapsed);
    XCTAssertEqualWithAccuracy(panel.contentView.alpha, 0, 0.01);
    XCTAssertEqualWithAccuracy(panel.collapseButton.alpha, 1, 0.01);
}

- (void)testToolbarReduceMotion
{
    TestFloatPanel *panel = [[TestFloatPanel alloc] initWithFrame:CGRectMake(0, 0, 700, 44)];
    panel.reduceMotion = YES;
    [panel applyAutoHideDelay:0];
    [panel hideContent];
    [self waitSeconds:0.4];
    XCTAssertTrue(CGAffineTransformIsIdentity(panel.contentView.transform));
    XCTAssertEqualWithAccuracy(panel.contentView.alpha, 0, 0.01);
    [panel showContent];
    [self waitSeconds:0.4];
    XCTAssertTrue(CGAffineTransformIsIdentity(panel.contentView.transform));
    XCTAssertEqualWithAccuracy(panel.contentView.alpha, 1, 0.01);
}

- (void)testToolbarActiveControlAppearance
{
    DPEmulatorViewController *controller = [[DPEmulatorViewController alloc] init];
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 700, 320)];
    root.tintColor = UIColor.systemPurpleColor;
    controller.view = root;
    [controller setValue:root forKey:@"rootContainer"];
    DPThemeScene *scene = [[DPThemeScene alloc] initWithAttributes:@{@"width":@700, @"height":@320, @"nodes":@[@{@"type":@"landbar"}]} theme:nil];
    UIView *sceneView = [controller createSceneView:scene frame:root.bounds];
    [root addSubview:sceneView];
    FloatPanel *panel = [controller valueForKey:@"fullscreenPanel"];
    [panel applyAutoHideDelay:0];
    UIView *keyboard = [[UIView alloc] init];
    keyboard.tag = 1001; // TAG_INPUT_KEYBOARD
    [root addSubview:keyboard];
    [controller refreshFullscreenPanel];
    [panel layoutIfNeeded];
    UIButton *button = [panel.contentView viewWithTag:1001];
    XCTAssertEqualObjects(button.tintColor, root.tintColor);
    XCTAssertTrue((button.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
    [keyboard removeFromSuperview];
    [controller refreshFullscreenPanel];
    [panel layoutIfNeeded];
    button = [panel.contentView viewWithTag:1001];
    XCTAssertEqualObjects(button.tintColor, UIColor.lightGrayColor);
    XCTAssertFalse((button.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
    [panel removeFromSuperview];
}

- (void)testToolbarAppearance
{
    DPSettings *preferences = DPSettings.shared;
    id oldBottom = [preferences valueForPreferenceKey:@"landbar_toggle_bottom_screen"];
    DPEmulatorViewController *controller = [[DPEmulatorViewController alloc] init];
    @try {
        for (NSNumber *width in @[@700, @480, @320]) {
            for (NSNumber *bottom in @[@NO, @YES]) {
                [preferences setValue:bottom forPreferenceKey:@"landbar_toggle_bottom_screen"];
                DPThemeScene *scene = [[DPThemeScene alloc] initWithAttributes:@{@"width":width, @"height":@160, @"nodes":@[@{@"type":@"landbar"}]} theme:nil];
                UIView *view = [controller createSceneView:scene frame:CGRectMake(0, 0, width.doubleValue, 160)];
                FloatPanel *panel = [controller valueForKey:@"fullscreenPanel"];
                [panel applyAutoHideDelay:0];
                XCTAssertTrue(CGRectContainsRect(view.bounds, panel.frame));
                for (UIColor *background in @[UIColor.blackColor, UIColor.whiteColor]) {
                    view.backgroundColor = background;
                    [panel setCollapsed:NO animated:NO];
                    [view layoutIfNeeded];
                    for (UIView *item in panel.contentView.subviews) {
                        if ([item isKindOfClass:UIButton.class]) XCTAssertNotNil([(UIButton *)item imageForState:UIControlStateNormal]);
                    }
                    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
                    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                        [view.layer renderInContext:context.CGContext];
                    }];
                    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
                    attachment.name = [NSString stringWithFormat:@"Toolbar-%@-%@-%@", width, bottom, background == UIColor.blackColor ? @"dark" : @"light"];
                    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
                    [self addAttachment:attachment];
                }
                [panel removeFromSuperview];
            }
        }
    } @finally {
        [preferences setValue:oldBottom forPreferenceKey:@"landbar_toggle_bottom_screen"];
    }
}

- (void)testToolbarPreferenceAndCollapse
{
    [self settle];
    DPSettings *preferences = [DPSettings shared];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    NSArray *keys = @[@"toolbar_auto_hide_delay", @"toolbar_last_auto_hide_delay"];
    DPEmulatorViewController *emulator = [self emulator];
    DPEmulatorViewController *toolbarController = [[DPEmulatorViewController alloc] init];
    [NSNotificationCenter.defaultCenter addObserver:toolbarController selector:@selector(didSettingsChanged:) name:DPFSettingsChangedNotification object:preferences];
    UIView *sceneView;
    @try {
        [preferences setValue:@3 forPreferenceKey:keys[0]];
        [emulator showOption:nil];
        [self settle];
        UINavigationController *navigation = (id)emulator.presentedViewController;
        DPSettingsViewController *settings = (id)navigation.topViewController;
        NSIndexPath *path = [NSIndexPath indexPathForRow:2 inSection:1];
        UITableViewCell *cell = [settings tableView:settings.tableView cellForRowAtIndexPath:path];
        XCTAssertEqualObjects(cell.textLabel.text, @"Toolbar auto-hide");
        XCTAssertEqualObjects(cell.detailTextLabel.text, @"3 seconds");
        [settings tableView:settings.tableView didSelectRowAtIndexPath:path];
        [self settle];
        UITableViewController *choice = (id)navigation.topViewController;
        NSArray *titles = @[@"Never", @"1 second", @"3 seconds", @"5 seconds", @"10 seconds"];
        XCTAssertEqual([choice tableView:choice.tableView numberOfRowsInSection:0], titles.count);
        for (NSUInteger i = 0; i < titles.count; i++) {
            UITableViewCell *option = [choice tableView:choice.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
            XCTAssertEqualObjects(option.textLabel.text, titles[i]);
            XCTAssertEqual(option.accessoryType, i == 2 ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone);
        }
        [choice tableView:choice.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        [self settle];
        XCTAssertEqual(preferences.toolbarAutoHideDelay, 5);

        // Manual collapse must preserve the preference and survive scene recreation.
        for (NSNumber *width in @[@700, @480, @320]) {
            DPThemeScene *scene = [[DPThemeScene alloc] initWithAttributes:@{@"width":width, @"height":@320, @"nodes":@[@{@"type":@"landbar"}]} theme:nil];
            sceneView = [toolbarController createSceneView:scene frame:CGRectMake(0, 0, width.doubleValue, 320)];
            FloatPanel *panel = [toolbarController valueForKey:@"fullscreenPanel"];
            [panel showContent];
            XCTAssertTrue(panel.autoHide);
            XCTAssertEqual(panel.autoHideInterval, 5);
            [panel.collapseButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            XCTAssertTrue(panel.isCollapsed);
            XCTAssertEqual(preferences.toolbarAutoHideDelay, 5);
            XCTAssertEqualObjects(panel.collapseButton.accessibilityLabel, @"Expand toolbar");
            [panel removeFromSuperview];
            sceneView = [toolbarController createSceneView:scene frame:sceneView.bounds];
            panel = [toolbarController valueForKey:@"fullscreenPanel"];
            XCTAssertTrue(panel.isCollapsed);
            [panel.collapseButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            XCTAssertFalse(panel.isCollapsed);
            XCTAssertEqual(preferences.toolbarAutoHideDelay, 5);
            XCTAssertEqualObjects(panel.collapseButton.accessibilityLabel, @"Collapse toolbar");
            [toolbarController setValue:scene forKey:@"currentScene"];
            [panel hideContent];
            [toolbarController updateCpuCycles:@"12345"];
            XCTAssertFalse(panel.isCollapsed);
            [panel hideContent];
            [toolbarController updateFrameskip:@2];
            XCTAssertFalse(panel.isCollapsed);
            [panel removeFromSuperview];
        }
    } @finally {
        [[toolbarController valueForKey:@"fullscreenPanel"] removeFromSuperview];
        [NSNotificationCenter.defaultCenter removeObserver:toolbarController];
        if (emulator.presentedViewController) {
            [emulator dismissViewControllerAnimated:NO completion:nil];
            [emulator finishSettings];
            [self settle];
        }
        for (NSString *key in keys) {
            if (saved[key]) [defaults setObject:saved[key] forKey:key];
            else [defaults removeObjectForKey:key];
        }
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
    }
}
- (void)settle
{
    XCTestExpectation *delay = [self expectationWithDescription:@"UI transition completes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [delay fulfill]; });
    [self waitForExpectations:@[delay] timeout:3];
}
- (DPEmulatorViewController *)emulator
{
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in scene.windows) {
            if ([window.rootViewController isKindOfClass:DPEmulatorViewController.class])
                return (DPEmulatorViewController *)window.rootViewController;
        }
    }
    return nil;
}
- (void)testKeepScreenAwake
{
    [self settle];
    UIApplication *application = UIApplication.sharedApplication;
    AppDelegate *delegate = (id)application.delegate;
    DPSettings *preferences = [DPSettings shared];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id savedValue = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier][@"keep_screen_awake"];
    DPEmulatorViewController *emulator = [self emulator];
    XCTAssertNotNil(emulator);
    @try {
        [preferences setValue:@NO forPreferenceKey:@"keep_screen_awake"];
        XCTAssertFalse(application.idleTimerDisabled);
        [emulator showOption:nil];
        [self settle];
        UINavigationController *navigation = (id)emulator.presentedViewController;
        DPSettingsViewController *settings = (id)navigation.topViewController;
        NSIndexPath *path = [NSIndexPath indexPathForRow:5 inSection:0];
        UITableViewCell *cell = [settings tableView:settings.tableView cellForRowAtIndexPath:path];
        XCTAssertEqualObjects(cell.textLabel.text, @"Keep screen awake");
        UISwitch *control = (id)cell.accessoryView;
        XCTAssertTrue([control isKindOfClass:UISwitch.class]);
        XCTAssertFalse(control.on);
        control.on = YES;
        [control sendActionsForControlEvents:UIControlEventValueChanged];
        XCTAssertTrue(preferences.keepScreenAwake);
        XCTAssertTrue(application.idleTimerDisabled);
        XCTAssertEqual(dospad_pause_flag, 1);

        [delegate emulatorWillResignActive];
        XCTAssertFalse(application.idleTimerDisabled);
        [delegate emulatorDidBecomeActive];
        XCTAssertTrue(application.idleTimerDisabled);
        XCTAssertEqual(dospad_pause_flag, 1);

        control.on = NO;
        [control sendActionsForControlEvents:UIControlEventValueChanged];
        XCTAssertFalse(application.idleTimerDisabled);
        [preferences setValue:@YES forPreferenceKey:@"keep_screen_awake"];
        [delegate emulatorWillResignActive];
        [preferences setValue:@NO forPreferenceKey:@"keep_screen_awake"];
        XCTAssertFalse(application.idleTimerDisabled);
        [delegate emulatorDidBecomeActive];
        XCTAssertFalse(application.idleTimerDisabled);

        [delegate emulatorWillResignActive];
        [preferences setValue:@YES forPreferenceKey:@"keep_screen_awake"];
        XCTAssertFalse(application.idleTimerDisabled);
        // A fresh policy owner must apply an already-saved choice on first activation.
        AppDelegate *freshDelegate = [[AppDelegate alloc] init];
        [freshDelegate emulatorDidBecomeActive];
        XCTAssertTrue(application.idleTimerDisabled);
        [freshDelegate emulatorWillResignActive];
        XCTAssertFalse(application.idleTimerDisabled);
        [delegate emulatorDidBecomeActive];
        XCTAssertTrue(application.idleTimerDisabled);
        XCTAssertEqual(dospad_pause_flag, 1);
        [navigation dismissViewControllerAnimated:NO completion:nil];
        [emulator presentationControllerDidDismiss:navigation.presentationController];
        [self settle];
        XCTAssertNil(emulator.presentedViewController);
        XCTAssertTrue(application.idleTimerDisabled);
        XCTAssertEqual(dospad_pause_flag, 0);
    } @finally {
        if (emulator.presentedViewController) {
            [emulator dismissViewControllerAnimated:NO completion:nil];
            [emulator finishSettings];
            [self settle];
        }
        if (savedValue) [preferences setValue:savedValue forPreferenceKey:@"keep_screen_awake"];
        else {
            [defaults removeObjectForKey:@"keep_screen_awake"];
            [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
        }
        [delegate emulatorDidBecomeActive];
    }
}
- (void)testSettingsPresentationAndPause
{
    [self settle];
    DPEmulatorViewController *emulator = [self emulator];
    XCTAssertNotNil(emulator);
    [emulator showOption:nil];
    [self settle];
    UINavigationController *navigation = (id)emulator.presentedViewController;
    XCTAssertTrue([navigation isKindOfClass:UINavigationController.class]);
    XCTAssertEqual(navigation.presentationController.delegate, emulator);
    DPSettingsViewController *settings = (id)navigation.topViewController;
    XCTAssertTrue([settings isKindOfClass:DPSettingsViewController.class]);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:emulator.view.window.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [emulator.view.window drawViewHierarchyInRect:emulator.view.window.bounds afterScreenUpdates:YES];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = @"Settings modal";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    XCTAssertTrue(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 1);
    XCTAssertFalse(emulator.view.userInteractionEnabled);
    dospad_resume();
    [emulator willResignActive];
    [emulator didBecomeActive];
    XCTAssertEqual(dospad_pause_flag, 1);
    NSInteger rows = 0;
    for (NSInteger section = 0; section < [settings numberOfSectionsInTableView:settings.tableView]; section++)
        rows += [settings tableView:settings.tableView numberOfRowsInSection:section];
    XCTAssertEqual(rows, 20);
    NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
    UITableViewCell *cell = [settings tableView:settings.tableView cellForRowAtIndexPath:path];
    UISwitch *control = (id)cell.accessoryView;
    XCTAssertTrue([control isKindOfClass:UISwitch.class]);
    BOOL previous = control.on;
    control.on = !previous;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertEqual([DPSettings shared].autoOpenLastPackage, !previous);
    control.on = previous;
    [control sendActionsForControlEvents:UIControlEventValueChanged];
    // Slider edits save and convert transparency to overlay opacity.
    float previousTransparency = [[[DPSettings shared] valueForPreferenceKey:@"transparency"] floatValue];
    UITableViewCell *sliderCell = [settings tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
    UIStackView *stack = nil;
    for (UIView *view in sliderCell.contentView.subviews)
        if ([view isKindOfClass:UIStackView.class]) stack = (id)view;
    UISlider *slider = (id)stack.arrangedSubviews.lastObject;
    XCTAssertTrue([slider isKindOfClass:UISlider.class]);
    slider.value = 0.6;
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
    XCTAssertEqualWithAccuracy([DPSettings shared].floatAlpha, 0.4, 0.001);
    slider.value = previousTransparency;
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
    // Select a scale, return to settings, and preserve the original value.
    id previousScale = [[DPSettings shared] valueForPreferenceKey:@"screen_scale_mode"];
    [settings tableView:settings.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    [self settle];
    UITableViewController *choice = (id)navigation.topViewController;
    XCTAssertNotEqual(choice, settings);
    XCTAssertNotNil(choice.navigationItem.rightBarButtonItem);
    [choice tableView:choice.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    [self settle];
    XCTAssertEqual([DPSettings shared].screenScaleMode, DPScreenScaleModeAspectFit16x9);
    [[DPSettings shared] setValue:previousScale forPreferenceKey:@"screen_scale_mode"];
    // Opening a second sheet is ignored.
    [emulator showOption:nil];
    XCTAssertEqual(emulator.presentedViewController, navigation);
    // Done uses an explicit completion; interactive dismissal uses the delegate.
    UIBarButtonItem *done = settings.navigationItem.rightBarButtonItem;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [done.target performSelector:done.action];
#pragma clang diagnostic pop
    [self settle];
    XCTAssertNil(emulator.presentedViewController);
    XCTAssertFalse(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 0);
    XCTAssertTrue(emulator.view.userInteractionEnabled);
    [emulator showOption:nil];
    [self settle];
    navigation = (id)emulator.presentedViewController;
    [navigation dismissViewControllerAnimated:NO completion:nil];
    [emulator presentationControllerDidDismiss:navigation.presentationController];
    XCTAssertFalse(dospad_settings_open());
    XCTAssertEqual(dospad_pause_flag, 0);
}
@end
