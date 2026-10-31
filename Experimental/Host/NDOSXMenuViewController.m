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
- (void)replaceISO:(NSURL *)url target:(NSString *)target;
@end

// A local browser keeps mounted media in the app sandbox for the whole session.
@interface NDOSXISOBrowser : UITableViewController
@property(nonatomic, weak) NDOSXMenuViewController *menu;
@property(nonatomic, weak) UIViewController *origin;
@property(nonatomic, copy) NSString *target;
@property(nonatomic, copy) NSURL *directory;
@property(nonatomic, copy) NSURL *documents;
@property(nonatomic, copy) NSArray<NSURL *> *entries;
@end

@implementation NDOSXISOBrowser
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=[self.directory isEqual:self.documents] ? @"Choose ISO" : self.directory.lastPathComponent;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
}
- (BOOL)isLocal:(NSURL *)url {
    NSString *path=url.URLByResolvingSymlinksInPath.path;
    NSString *root=self.documents.URLByResolvingSymlinksInPath.path;
    return [path hasPrefix:[root stringByAppendingString:@"/"]];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSError *error=nil;
    NSArray<NSURL *> *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory
        includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsRegularFileKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    NSMutableArray *entries=[NSMutableArray array];
    for (NSURL *url in urls) {
        if (![self isLocal:url]) continue;
        NSNumber *folder=nil,*regular=nil;
        [url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        if (folder.boolValue || (regular.boolValue && [url.pathExtension.lowercaseString isEqualToString:@"iso"]))
            [entries addObject:url];
    }
    self.entries=[entries sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];
    UILabel *message=[[UILabel alloc] initWithFrame:CGRectMake(0,0,320,80)];
    message.text=error ? @"This folder could not be read. Go back and choose another folder." :
        @"Choose one ISO. Copy images into the nDOS-X folder using Files. The guest stays paused until you close Engine Menu.";
    message.numberOfLines=0;message.textAlignment=NSTextAlignmentCenter;
    message.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    message.adjustsFontForContentSizeCategory=YES;message.textColor=UIColor.secondaryLabelColor;
    self.tableView.tableHeaderView=message;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"iso"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"iso"];
    NSURL *url=self.entries[indexPath.row];NSNumber *folder=nil;
    [url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
    cell.textLabel.text=url.lastPathComponent;cell.textLabel.numberOfLines=0;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.accessoryType=folder.boolValue ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.menu.busy || self.menu.finished) return;
    NSURL *url=self.entries[indexPath.row];NSNumber *folder=nil;
    if (![self isLocal:url]) return;
    [url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
    if (folder.boolValue) {
        NDOSXISOBrowser *child=[[NDOSXISOBrowser alloc] initWithStyle:UITableViewStyleInsetGrouped];
        child.menu=self.menu;child.origin=self.origin;child.target=self.target;
        child.documents=self.documents;child.directory=url;
        [self.navigationController pushViewController:child animated:YES];
    } else {
        NDOSXMenuViewController *menu=self.menu;
        NSString *target=self.target;
        UINavigationController *navigation=self.navigationController;
        [navigation popToViewController:self.origin animated:YES];
        // An immediate worker error must not present an alert from a menu whose
        // view is still detached during the browser's navigation transition.
        id<UIViewControllerTransitionCoordinator> transition=navigation.transitionCoordinator;
        if (transition) {
            [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                [menu replaceISO:url target:target];
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [menu replaceISO:url target:target]; });
        }
    }
}
- (void)cancel:(id)sender {
    [self.navigationController popToViewController:self.origin animated:YES];
}
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
        if (item.isoPicker) {
            NDOSXISOBrowser *browser=[[NDOSXISOBrowser alloc] initWithStyle:UITableViewStyleInsetGrouped];
            browser.menu=root;browser.origin=self;browser.target=item.name;
            browser.documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                inDomains:NSUserDomainMask].firstObject.URLByResolvingSymlinksInPath;
            browser.directory=browser.documents;
            [self.navigationController pushViewController:browser animated:YES];
            return;
        }
        root.busy=YES;root.status=@"Applying change…";[root reloadControllers];
        __weak NDOSXMenuViewController *weakRoot=root;
        ndos_x_menu_invoke(root.session,item.name,^(NSArray<NDOSXMenuItem *> *items, NSError *error) {
            [weakRoot receivedItems:items error:error];
        });
    }
}
- (void)replaceISO:(NSURL *)url target:(NSString *)target {
    NDOSXMenuViewController *root=self.root;
    if (root.busy || root.finished) return;
    root.busy=YES;root.status=@"Changing disc…";[root reloadControllers];
    __weak NDOSXMenuViewController *weakRoot=root;
    ndos_x_menu_replace_iso(root.session,target,url,^(NSArray<NDOSXMenuItem *> *items, NSError *error) {
        NDOSXMenuViewController *owner=weakRoot;
        if (!owner || owner.finished) return;
        [owner receivedItems:items error:error];
        if (error) {
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Could not change disc"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [owner.navigationController.topViewController presentViewController:alert animated:YES completion:nil];
        }
    });
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
