#import "DPGamepadLayout.h"
#import "DPGamepad.h"

@interface DPGamepadLayout ()
@property (nonatomic, weak) DPGamepad *pad;
@property (nonatomic, weak) UIView *editorHost;
@property (nonatomic, weak) DPButton *editButton;
@property (nonatomic, copy) dispatch_block_t prepareInput;
@property (nonatomic, copy) NSArray<NSArray<UIView *> *> *groups;
@property (nonatomic, copy) NSArray<UIView *> *reservedViews;
@property (nonatomic, copy) NSString *defaultsKey;
@end

@implementation DPGamepadLayout {
    CGPoint _stockOrigins[2];
    NSInteger _dragGroup;
    CGPoint _dragStart;
    CGPoint _originAtPickup;
    BOOL _previewingDefaults;
}

- (instancetype)initWithGamepad:(DPGamepad *)pad editorHost:(UIView *)host
                 reservedViews:(NSArray<UIView *> *)reservedViews prepareInput:(dispatch_block_t)prepareInput
{
    if (!(self = [super initWithFrame:host.bounds])) return nil;
    _pad = pad;
    _editorHost = host;
    _prepareInput = [prepareInput copy];
    _dragGroup = NSNotFound;
    self.accessibilityViewIsModal = YES;
    NSMutableArray *left = [NSMutableArray arrayWithObjects:pad.dpad, pad.stick, nil];
    NSMutableArray *right = [NSMutableArray array];
    for (DPGamepadButton *button in pad.buttons) {
        BOOL isLeft = button.buttonIndex == DP_GAMEPAD_BUTTON_L1 || button.buttonIndex == DP_GAMEPAD_BUTTON_L2;
        [(isLeft ? left : right) addObject:button];
    }
    _groups = @[left, right];
    NSMutableArray *reserved = [reservedViews mutableCopy];
    for (UIView *view in pad.subviews) {
        if (![view isKindOfClass:DPButton.class]) continue;
        [reserved addObject:view];
        DPButton *button = (DPButton *)view;
        if ([button.name isEqual:@"edit-toggle"]) _editButton = button;
    }
    _reservedViews = reserved;
    _defaultsKey = pad.bounds.size.width > pad.bounds.size.height ?
        @"TouchControlLayout.Landscape" : @"TouchControlLayout.Portrait";
    for (NSInteger group = 0; group < 2; group++)
        _stockOrigins[group] = [self boundsForGroup:group].origin;
    [self installEditMenu];
    [self reloadPositions];
    return self;
}

- (CGRect)boundsForGroup:(NSInteger)group
{
    CGRect bounds = CGRectNull;
    for (UIView *member in self.groups[group]) bounds = CGRectUnion(bounds, member.frame);
    return bounds;
}

- (void)placeGroup:(NSInteger)group at:(CGPoint)origin
{
    CGPoint old = [self boundsForGroup:group].origin;
    for (UIView *member in self.groups[group])
        member.frame = CGRectOffset(member.frame, origin.x - old.x, origin.y - old.y);
}

- (NSArray<UIView *> *)obstaclesForGroup:(NSInteger)group
{
    NSMutableArray *obstacles = [NSMutableArray arrayWithArray:self.groups[1 - group]];
    for (UIView *fixed in self.reservedViews) {
        if (!fixed.hidden && fixed.userInteractionEnabled) [obstacles addObject:fixed];
    }
    return obstacles;
}

static BOOL IsRoundButton(UIView *view)
{
    return [view isKindOfClass:DPGamepadButton.class] &&
           ((DPGamepadButton *)view).style == DPGamePadButtonStyleCircle;
}

static BOOL TouchTargetsOverlap(UIView *member, CGRect frame, UIView *other, CGRect otherFrame)
{
    if (CGRectIsEmpty(CGRectIntersection(frame, otherFrame))) return NO;
    BOOL round = IsRoundButton(member);
    BOOL otherRound = IsRoundButton(other);
    if (!round && !otherRound) return YES;
    CGFloat dx = fabs(CGRectGetMidX(frame) - CGRectGetMidX(otherFrame));
    CGFloat dy = fabs(CGRectGetMidY(frame) - CGRectGetMidY(otherFrame));
    if (round && otherRound) return hypot(dx, dy) < (frame.size.width + otherFrame.size.width) / 2;
    CGRect box = round ? otherFrame : frame;
    CGFloat radius = (round ? frame.size.width : otherFrame.size.width) / 2;
    return hypot(MAX(0, dx - box.size.width / 2), MAX(0, dy - box.size.height / 2)) < radius;
}

- (BOOL)canPlaceGroup:(NSInteger)group at:(CGPoint)origin obstacles:(NSArray<UIView *> *)obstacles
{
    CGRect bounds = [self boundsForGroup:group];
    CGRect target = (CGRect){origin, bounds.size};
    if (!CGRectContainsRect(self.pad.bounds, target)) return NO;
    for (UIView *member in self.groups[group]) {
        CGRect frame = CGRectOffset(member.frame, origin.x - bounds.origin.x, origin.y - bounds.origin.y);
        for (UIView *other in obstacles) {
            CGRect otherFrame = [other convertRect:other.bounds toView:self.pad];
            if (TouchTargetsOverlap(member, frame, other, otherFrame)) return NO;
        }
    }
    return YES;
}

// Try nearby screen and obstacle edges when the preferred starting position is occupied.
- (void)placeDefaultGroup:(NSInteger)group at:(CGPoint)preferred
{
    CGRect bounds = [self boundsForGroup:group];
    NSArray *obstacles = [self obstaclesForGroup:group];
    if ([self canPlaceGroup:group at:preferred obstacles:obstacles]) {
        [self placeGroup:group at:preferred];
        return;
    }
    NSMutableSet *xs = [NSMutableSet setWithArray:@[@(preferred.x), @0, @(self.pad.bounds.size.width - bounds.size.width)]];
    NSMutableSet *ys = [NSMutableSet setWithArray:@[@(preferred.y), @0, @(self.pad.bounds.size.height - bounds.size.height)]];
    for (UIView *member in self.groups[group]) {
        CGRect local = CGRectOffset(member.frame, -bounds.origin.x, -bounds.origin.y);
        for (UIView *other in obstacles) {
            CGRect obstacle = [other convertRect:other.bounds toView:self.pad];
            [xs addObject:@(floor(CGRectGetMinX(obstacle) - CGRectGetMaxX(local)))];
            [xs addObject:@(ceil(CGRectGetMaxX(obstacle) - CGRectGetMinX(local)))];
            [ys addObject:@(floor(CGRectGetMinY(obstacle) - CGRectGetMaxY(local)))];
            [ys addObject:@(ceil(CGRectGetMaxY(obstacle) - CGRectGetMinY(local)))];
        }
    }
    CGFloat bestDistance = CGFLOAT_MAX;
    CGPoint best = bounds.origin;
    for (NSNumber *x in xs) for (NSNumber *y in ys) {
        CGPoint point = CGPointMake(x.doubleValue, y.doubleValue);
        CGFloat distance = hypot(point.x - preferred.x, point.y - preferred.y);
        if (distance < bestDistance && [self canPlaceGroup:group at:point obstacles:obstacles]) {
            bestDistance = distance;
            best = point;
        }
    }
    [self placeGroup:group at:best];
}

- (void)restoreDefaults
{
    for (NSInteger group = 0; group < 2; group++)
        [self placeGroup:group at:_stockOrigins[group]];
    [self placeDefaultGroup:1 at:_stockOrigins[1]];
    CGPoint left = _stockOrigins[0];
    const CGFloat thumbInset = 24;
    left.x += thumbInset;
    left.y -= thumbInset;
    [self placeDefaultGroup:0 at:left];
    _previewingDefaults = YES;
}

- (void)reloadPositions
{
    NSArray *positions = [NSUserDefaults.standardUserDefaults arrayForKey:self.defaultsKey];
    if (positions.count == 4) {
        for (NSInteger group = 0; group < 2; group++) {
            CGSize size = [self boundsForGroup:group].size;
            [self placeGroup:group at:CGPointMake([positions[group*2] doubleValue] * (self.pad.bounds.size.width - size.width),
                                                  [positions[group*2+1] doubleValue] * (self.pad.bounds.size.height - size.height))];
        }
        if ([self canPlaceGroup:0 at:[self boundsForGroup:0].origin obstacles:[self obstaclesForGroup:0]] &&
            [self canPlaceGroup:1 at:[self boundsForGroup:1].origin obstacles:[self obstaclesForGroup:1]]) {
            _previewingDefaults = NO;
            return;
        }
    }
    [self restoreDefaults];
}

- (void)save
{
    [self cancelDrag];
    if (_previewingDefaults) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:self.defaultsKey];
    } else {
        NSMutableArray *positions = [NSMutableArray array];
        for (NSInteger group = 0; group < 2; group++) {
            CGRect bounds = [self boundsForGroup:group];
            [positions addObject:@(bounds.origin.x / MAX(1, self.pad.bounds.size.width - bounds.size.width))];
            [positions addObject:@(bounds.origin.y / MAX(1, self.pad.bounds.size.height - bounds.size.height))];
        }
        [NSUserDefaults.standardUserDefaults setObject:positions forKey:self.defaultsKey];
    }
    [self cancel];
}

- (void)installEditMenu
{
    DPButton *button = self.editButton;
    [button removeTarget:self.pad action:@selector(didButtonPress:) forControlEvents:UIControlEventTouchUpInside];
    __weak DPGamepadLayout *weakSelf = self;
    UIAction *move = [UIAction actionWithTitle:@"Move Controls" image:nil identifier:nil handler:^(UIAction *action) {
        [weakSelf beginEditingLayout];
    }];
    UIAction *bindings = [UIAction actionWithTitle:@"Edit Gamepad Bindings" image:nil identifier:nil handler:^(UIAction *action) {
        [weakSelf beginEditingBindings];
    }];
    button.accessibilityLabel = @"Edit touch controls";
    button.menu = [UIMenu menuWithChildren:@[move, bindings]];
    button.showsMenuAsPrimaryAction = YES;
}

- (void)beginEditingBindings
{
    self.pad.editing = YES;
    DPButton *button = self.editButton;
    button.showsMenuAsPrimaryAction = NO;
    button.menu = nil;
    button.accessibilityLabel = @"Finish editing bindings";
    [button setImage:[self.pad.scene getImage:@"assets/edit-toggle-on.png"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(finishEditingBindings) forControlEvents:UIControlEventTouchUpInside];
}

- (void)finishEditingBindings
{
    self.pad.editing = NO;
    [self.editButton removeTarget:self action:_cmd forControlEvents:UIControlEventTouchUpInside];
    [self.editButton setImage:[self.pad.scene getImage:@"assets/edit-toggle-off.png"] forState:UIControlStateNormal];
    [self installEditMenu];
}

- (void)beginEditingLayout
{
    if (self.superview || !self.pad.window || self.pad.hidden) return;
    self.prepareInput();
    self.pad.userInteractionEnabled = NO;
    self.pad.editing = YES;
    self.frame = self.editorHost.bounds;
    self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:.10];
    [self.editorHost addSubview:self];
    UIButton *finish = [UIButton buttonWithType:UIButtonTypeSystem];
    finish.frame = [self.editButton convertRect:self.editButton.bounds toView:self];
    finish.backgroundColor = UIColor.systemBackgroundColor;
    finish.layer.cornerRadius = 5;
    [finish setImage:[UIImage systemImageNamed:@"checkmark.circle"] forState:UIControlStateNormal];
    finish.accessibilityLabel = @"Layout options";
    __weak DPGamepadLayout *weakSelf = self;
    finish.menu = [UIMenu menuWithTitle:@"Move Controls" children:@[
        [UIAction actionWithTitle:@"Done" image:nil identifier:nil handler:^(UIAction *action){ [weakSelf save]; }],
        [UIAction actionWithTitle:@"Restore Defaults" image:nil identifier:nil handler:^(UIAction *action){ [weakSelf restoreDefaults]; }],
        [UIAction actionWithTitle:@"Cancel" image:nil identifier:nil handler:^(UIAction *action){ [weakSelf cancel]; }]
    ]];
    finish.exclusiveTouch = YES;
    finish.showsMenuAsPrimaryAction = YES;
    [self addSubview:finish];
}

- (void)cancel
{
    if (!self.superview) return;
    _dragGroup = NSNotFound;
    for (UIView *button in self.subviews) [button removeFromSuperview];
    [self removeFromSuperview];
    self.pad.userInteractionEnabled = YES;
    self.pad.editing = NO;
    [self reloadPositions];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    _dragStart = [touches.anyObject locationInView:self.pad];
    for (NSInteger group = 0; group < 2; group++) {
        for (UIView *member in self.groups[group]) {
            if (!member.hidden && [member pointInside:[self.pad convertPoint:_dragStart toView:member] withEvent:event]) {
                _dragGroup = group;
                _originAtPickup = [self boundsForGroup:group].origin;
                return;
            }
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (_dragGroup == NSNotFound) return;
    CGPoint point = [touches.anyObject locationInView:self.pad];
    [self placeGroup:_dragGroup at:CGPointMake(_originAtPickup.x + point.x - _dragStart.x,
                                               _originAtPickup.y + point.y - _dragStart.y)];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (_dragGroup == NSNotFound) return;
    [self touchesMoved:touches withEvent:event];
    CGPoint origin = [self boundsForGroup:_dragGroup].origin;
    if ([self canPlaceGroup:_dragGroup at:origin obstacles:[self obstaclesForGroup:_dragGroup]]) {
        if (!CGPointEqualToPoint(origin, _originAtPickup)) _previewingDefaults = NO;
    } else {
        [self placeGroup:_dragGroup at:_originAtPickup];
    }
    _dragGroup = NSNotFound;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self cancelDrag];
}

- (void)cancelDrag
{
    if (_dragGroup != NSNotFound) [self placeGroup:_dragGroup at:_originAtPickup];
    _dragGroup = NSNotFound;
}
@end
