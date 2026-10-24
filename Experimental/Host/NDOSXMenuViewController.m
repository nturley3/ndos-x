#import "NDOSXMenu.h"

@interface NDOSXMenuViewController ()
@property(nonatomic, weak) NDOSXMenuViewController *menuRoot;
@property(nonatomic, copy) NSString *submenuName;
@property(nonatomic, copy) NSArray<NDOSXMenuItem *> *menuItems;
@property(nonatomic, copy) NSArray<NSArray<NDOSXMenuItem *> *> *groups;
@property(nonatomic) NDOSXMenuSession session;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL finished;
@property(nonatomic, copy) NSString *status;
@end

@implementation NDOSXMenuViewController
- (instancetype)init {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _menuItems=@[];_groups=@[];
    }
    return self;
}
- (NDOSXMenuViewController *)root { return self.menuRoot ?: self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.menuRoot ? self.title : @"Engine Menu";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=60;
    if (!self.menuRoot) {
        self.busy=YES;self.status=@"Pausing engine…";
        __weak NDOSXMenuViewController *weakSelf=self;
        self.session=ndos_x_menu_open(^(NSArray<NDOSXMenuItem *> *items, NSError *error) {
            [weakSelf receivedItems:items error:error];
        });
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(engineStopped:)
            name:@"NDOSXEngineStopped" object:nil];
    }
    [self reloadMenu];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_session) ndos_x_menu_close(_session);
}
- (NDOSXMenuItem *)findItem:(NSString *)name inItems:(NSArray<NDOSXMenuItem *> *)items {
    for (NDOSXMenuItem *item in items) {
        if ([item.name isEqualToString:name]) return item;
        NDOSXMenuItem *child=[self findItem:name inItems:item.children];
        if (child) return child;
    }
    return nil;
}
- (void)reloadMenu {
    NDOSXMenuViewController *root=self.root;
    NSArray *items=self.menuRoot ? [self findItem:self.submenuName inItems:root.menuItems].children : root.menuItems;
    NSMutableArray *groups=[NSMutableArray array];
    NSMutableArray *group=[NSMutableArray array];
    for (NDOSXMenuItem *item in items) {
        if (item.type>=2) {
            if (group.count) { [groups addObject:[group copy]];[group removeAllObjects]; }
        } else [group addObject:item];
    }
    if (group.count) [groups addObject:[group copy]];
    self.groups=[groups copy];
    UILabel *message=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,64)];
    message.text=root.status ?: @"Guest paused. Changes apply to this session.";
    message.textAlignment=NSTextAlignmentCenter;message.numberOfLines=0;
    message.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    message.textColor=UIColor.secondaryLabelColor;
    message.adjustsFontForContentSizeCategory=YES;
    self.tableView.tableHeaderView=message;
    [self.tableView reloadData];
}
- (void)reloadControllers {
    for (UIViewController *controller in self.navigationController.viewControllers)
        if ([controller isKindOfClass:NDOSXMenuViewController.class])
            [(NDOSXMenuViewController *)controller reloadMenu];
}
- (void)receivedItems:(NSArray<NDOSXMenuItem *> *)items error:(NSError *)error {
    if (self.finished) return;
    self.busy=NO;
    if (!error) self.menuItems=items;
    self.status=error.localizedDescription;
    [self reloadControllers];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.groups[section].count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"menu"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"menu"];
    NDOSXMenuItem *item=self.groups[indexPath.section][indexPath.row];
    BOOL submenu=item.type==1;
    BOOL enabled=submenu || item.enabled;
    cell.textLabel.text=item.title;
    cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.textColor=enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
    cell.detailTextLabel.text=item.unavailableReason;
    cell.accessoryType=submenu ? UITableViewCellAccessoryDisclosureIndicator :
        item.checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle=enabled && !self.root.busy ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessibilityTraits=UIAccessibilityTraitButton;
    if (!enabled || self.root.busy) cell.accessibilityTraits|=UIAccessibilityTraitNotEnabled;
    cell.accessibilityValue=item.checked ? @"Selected" : nil;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NDOSXMenuViewController *root=self.root;
    if (root.busy || root.finished) return;
    NDOSXMenuItem *item=self.groups[indexPath.section][indexPath.row];
    if (item.type==1) {
        NDOSXMenuViewController *child=[NDOSXMenuViewController new];
        child.menuRoot=root;child.submenuName=item.name;child.title=item.title;
        [self.navigationController pushViewController:child animated:YES];
    } else if (item.enabled) {
        root.busy=YES;root.status=@"Applying change…";[root reloadControllers];
        __weak NDOSXMenuViewController *weakRoot=root;
        ndos_x_menu_invoke(root.session,item.name,^(NSArray<NDOSXMenuItem *> *items, NSError *error) {
            [weakRoot receivedItems:items error:error];
        });
    }
}
- (void)done:(id)sender {
    NDOSXMenuViewController *root=self.root;
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ [root finish]; }];
}
- (void)finish {
    NDOSXMenuViewController *root=self.root;
    if (root.finished) return;
    root.finished=YES;
    ndos_x_menu_close(root.session);root.session=0;
    void (^completion)(void)=root.didFinish;root.didFinish=nil;
    if (completion) completion();
}
- (void)engineStopped:(NSNotification *)notification {
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ [self finish]; }];
}
@end
