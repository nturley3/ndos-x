#import "NDOSXProfiles.h"

static NSString * const NDOSXLastProfile = @"NDOSXLastProfile";

@interface NDOSXProfilePicker ()
@property (nonatomic, strong) NDOSXProfiles *profiles;
@property (nonatomic, copy) NSArray<NSString *> *filenames;
@property (nonatomic, copy) NSString *selectedFilename;
@end

@implementation NDOSXProfilePicker
- (instancetype)initWithProfiles:(NDOSXProfiles *)profiles
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _profiles = profiles;
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Choose configuration";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStyleDone target:self action:@selector(start)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self refresh];
}
- (void)refresh
{
    NSError *error = nil;
    self.filenames = [self.profiles filenamesWithError:&error] ?: @[];
    NSString *previous = self.selectedFilename ?: [NSUserDefaults.standardUserDefaults stringForKey:NDOSXLastProfile];
    self.selectedFilename = [self.profiles preferredFilename:previous among:self.filenames];
    self.navigationItem.rightBarButtonItem.enabled = self.selectedFilename != nil;
    [self.tableView reloadData];
    if (error) [self showError:error];
}
- (void)showError:(NSError *)error
{
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Configuration unavailable" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)start
{
    NSError *error = nil;
    NSString *path = [self.profiles pathForFilename:self.selectedFilename error:&error];
    if (!path) {
        [self refresh];
        [self showError:error];
        return;
    }
    [NSUserDefaults.standardUserDefaults setObject:self.selectedFilename forKey:NDOSXLastProfile];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    if (self.didChoosePath) self.didChoosePath(path);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.filenames.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSString *name = self.filenames[indexPath.row];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    if ([name isEqual:@"ndos-x.conf"] || [name isEqual:@"NDOS-X.CONF"]) cell.detailTextLabel.text = @"Automatically mounts dos as C:";
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = [name isEqual:self.selectedFilename] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.selectedFilename = self.filenames[indexPath.row];
    [self.tableView reloadData];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"Add or edit .conf files in Files → nDOS-X → config. Other configurations control their own disks and startup commands. Switching configurations requires a full app relaunch.";
}
@end
