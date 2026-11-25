#import "DPSettingsViewController.h"
#import "DPSettings.h"
#include <math.h>
#ifdef NDOS_X_HOST
#import "NDOSXMenu.h"

static NSString *const TurboAction = @"mapper_speedlock2";
static NSString *const TurboHint = @"Your machine profile can end Turbo on a keypress or after a timeout.";
#endif

@interface DPSettingsSlider : UISlider
@property (nonatomic) float step;
@end

@implementation DPSettingsSlider
- (void)accessibilityIncrement
{
    if (self.step <= 0) {
        [super accessibilityIncrement];
        return;
    }
    self.value = MIN(self.maximumValue, self.value + self.step);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)accessibilityDecrement
{
    if (self.step <= 0) {
        [super accessibilityDecrement];
        return;
    }
    self.value = MAX(self.minimumValue, self.value - self.step);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

@interface DPSettingsChoiceController : UITableViewController
@property (nonatomic, copy) NSDictionary *specifier;
@end

@implementation DPSettingsChoiceController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.specifier[@"Title"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.specifier[@"Values"] count];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.specifier[@"Titles"][indexPath.row];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    id value = [[DPSettings shared] valueForPreferenceKey:self.specifier[@"Key"]];
    cell.accessoryType = [value isEqual:self.specifier[@"Values"][indexPath.row]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [[DPSettings shared] setValue:self.specifier[@"Values"][indexPath.row] forPreferenceKey:self.specifier[@"Key"]];
    [self.tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface DPSettingsViewController ()
#ifdef NDOS_X_HOST
@property (nonatomic) NDOSXMenuSession turboSession;
@property (nonatomic) NSUInteger turboRequest;
@property (nonatomic, strong) UISwitch *turboSwitch;
#endif
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMapTable<UIControl *, NSDictionary *> *controls;
@end

@implementation DPSettingsViewController
- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.controls = [NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *rows = nil;
    for (NSDictionary *item in [DPSettings shared].preferenceSpecifiers) {
        if ([item[@"Type"] isEqual:@"PSGroupSpecifier"]) {
            rows = [NSMutableArray array];
            [sections addObject:@{@"group":item, @"rows":rows}];
#ifdef NDOS_X_HOST
            if ([item[@"Title"] isEqual:@"General"]) {
                [rows addObject:@{@"Type":TurboAction, @"Title":@"Turbo (fast-forward)"}];
            }
#endif
        } else if (rows) {
            [rows addObject:item];
        }
    }
    self.sections = sections;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
#ifdef NDOS_X_HOST
    self.turboSwitch = [[UISwitch alloc] init];
    self.turboSwitch.enabled = NO;
    [self.turboSwitch addTarget:self action:@selector(changeTurbo:) forControlEvents:UIControlEventValueChanged];
    self.turboSession = ndos_x_menu_open([self turboCompletion]);
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(refreshTurbo:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [notifications addObserver:self selector:@selector(engineStopped:) name:@"NDOSXEngineStopped" object:nil];
#endif
}
#ifdef NDOS_X_HOST
- (NDOSXMenuCompletion)turboCompletion
{
    self.turboSwitch.enabled = NO;
    NSUInteger request = ++_turboRequest;
    __weak DPSettingsViewController *weakSelf = self;
    return ^(NSArray<NDOSXMenuItem *> *items, NSError *error) {
        DPSettingsViewController *sheet = weakSelf;
        if (!sheet || sheet.turboRequest != request) return;
        NDOSXMenuItem *item = error ? nil : [NDOSXMenuItem findItem:TurboAction inItems:items];
        sheet.turboSwitch.on = item.checked;
        sheet.turboSwitch.enabled = item.enabled;
    };
}

- (void)changeTurbo:(UISwitch *)sender
{
    if (!sender.enabled) return;
    ndos_x_menu_invoke(self.turboSession, TurboAction, [self turboCompletion]);
}

- (void)refreshTurbo:(NSNotification *)notification
{
    if (self.turboSession) ndos_x_menu_refresh(self.turboSession, [self turboCompletion]);
}

- (void)engineStopped:(NSNotification *)notification
{
    [self closeTurboSession];
}

- (void)closeTurboSession
{
    ++_turboRequest;
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:@"NDOSXEngineStopped" object:nil];
    self.turboSwitch.enabled = NO;
    self.turboSwitch.on = NO;
    ndos_x_menu_close(self.turboSession);
    self.turboSession = 0;
}

- (void)dealloc
{
    if (_turboSession) ndos_x_menu_close(_turboSession);
}
#endif

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}
- (void)done
{
    [self dismissViewControllerAnimated:YES completion:self.didFinish];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sections.count;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.sections[section][@"rows"] count];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.sections[section][@"group"][@"Title"];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return self.sections[section][@"group"][@"FooterText"];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *item = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *type = item[@"Type"];
#ifdef NDOS_X_HOST
    if ([type isEqual:TurboAction]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = item[@"Title"];
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.text = TurboHint;
        cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
        self.turboSwitch.accessibilityLabel = item[@"Title"];
        self.turboSwitch.accessibilityHint = TurboHint;
        cell.accessoryView = self.turboSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
#endif
    id value = [[DPSettings shared] valueForPreferenceKey:item[@"Key"]];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = item[@"Title"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if ([type isEqual:@"PSToggleSwitchSpecifier"]) {
        UISwitch *control = [[UISwitch alloc] init];
        control.on = [value boolValue];
        control.accessibilityLabel = item[@"Title"];
        [self.controls setObject:item forKey:control];
        [control addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
    } else if ([type isEqual:@"PSSliderSpecifier"]) {
        cell.textLabel.text = nil;
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.numberOfLines = 0;
        label.text = [NSString stringWithFormat:@"%@: %.0f%%", item[@"Title"], [value floatValue] * 100];
        label.isAccessibilityElement = NO;
        DPSettingsSlider *control = [[DPSettingsSlider alloc] init];
        control.step = [item[@"StepValue"] floatValue];
        control.minimumValue = [item[@"MinimumValue"] floatValue];
        control.maximumValue = [item[@"MaximumValue"] floatValue];
        control.value = [value floatValue];
        control.accessibilityLabel = item[@"Title"];
        control.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", control.value * 100];
        [self.controls setObject:item forKey:control];
        [control addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:stack];
        UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
        ]];
    } else if ([type isEqual:@"PSMultiValueSpecifier"]) {
        NSUInteger selected = [item[@"Values"] indexOfObject:value];
        if (selected != NSNotFound) cell.detailTextLabel.text = item[@"ShortTitles"][selected];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}
- (void)toggleChanged:(UISwitch *)control
{
    [[DPSettings shared] setValue:@(control.on) forPreferenceKey:[self.controls objectForKey:control][@"Key"]];
}
- (void)sliderChanged:(DPSettingsSlider *)control
{
    if (control.step > 0) {
        float steps = roundf((control.value - control.minimumValue) / control.step);
        control.value = control.minimumValue + steps * control.step;
    }
    NSDictionary *item = [self.controls objectForKey:control];
    [[DPSettings shared] setValue:@(control.value) forPreferenceKey:item[@"Key"]];
    UIStackView *stack = (UIStackView *)control.superview;
    UILabel *label = (UILabel *)stack.arrangedSubviews.firstObject;
    label.text = [NSString stringWithFormat:@"%@: %.0f%%", item[@"Title"], control.value * 100];
    control.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", control.value * 100];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *item = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (![item[@"Type"] isEqual:@"PSMultiValueSpecifier"]) return;
    DPSettingsChoiceController *choice = [[DPSettingsChoiceController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    choice.specifier = item;
    choice.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    [self.navigationController pushViewController:choice animated:YES];
}
@end
