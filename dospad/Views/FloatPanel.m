/*
 *  Copyright (C) 2010  Chaoji Li
 *
 *  DOSPAD is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "FloatPanel.h"

// Empty space belongs to the emulator, even when the row can scroll.
@interface ToolbarScrollView : UIScrollView
@end
@implementation ToolbarScrollView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface FloatPanel () <UIScrollViewDelegate>
@property (nonatomic, strong) ToolbarScrollView *controls;
@property (nonatomic, strong) NSArray<UIView *> *items;
@property (nonatomic, readwrite) UIButton *collapseButton;
@property (nonatomic, readwrite, getter=isCollapsed) BOOL collapsed;
@property (nonatomic, strong) NSMutableSet<UIControl *> *pressedControls;
@property (nonatomic) BOOL scrolling;
@property (nonatomic) BOOL pointerHovering;
@end

@implementation FloatPanel
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        _autoHide = YES;
        _autoHideInterval = 3;
        _controls = [[ToolbarScrollView alloc] initWithFrame:CGRectZero];
        _controls.showsHorizontalScrollIndicator = NO;
        _controls.delaysContentTouches = NO;
        _controls.delegate = self;
        _pressedControls = [NSMutableSet set];
        [self addSubview:_controls];
        _collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _collapseButton.tintColor = UIColor.lightGrayColor;
        _collapseButton.layer.shadowColor = UIColor.blackColor.CGColor;
        _collapseButton.layer.shadowOpacity = 0.65;
        _collapseButton.layer.shadowRadius = 1.5;
        _collapseButton.layer.shadowOffset = CGSizeMake(0, 1);
        [_collapseButton addTarget:self action:@selector(toggleCollapsed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_collapseButton];
        [self observeControl:_collapseButton];
        UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(pointerHoverChanged:)];
        hover.cancelsTouchesInView = NO;
        [self addGestureRecognizer:hover];
        [self updateArrow];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reduceMotionChanged:)
            name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(voiceOverStatusChanged:)
            name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)reduceMotionEnabled { return UIAccessibilityIsReduceMotionEnabled(); }
- (void)reduceMotionChanged:(NSNotification *)notification
{
    [self setCollapsed:self.collapsed animated:NO];
}
- (UIView *)contentView { return self.controls; }

- (void)updateArrow
{
    NSString *symbol = self.collapsed ? @"chevron.left.circle" : @"chevron.right.circle";
    [self.collapseButton setImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightRegular]]
                        forState:UIControlStateNormal];
    self.collapseButton.accessibilityLabel = self.collapsed ? @"Expand toolbar" : @"Collapse toolbar";
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat available = MAX(0, self.bounds.size.width - 44);
    self.collapseButton.frame = CGRectMake(available, 0, 44, 44);
    // Set bounds/center rather than frame: the controls may be transformed during animation.
    self.controls.bounds = (CGRect){self.controls.bounds.origin, CGSizeMake(available, 44)};
    self.controls.center = CGPointMake(available / 2, 22);
    CGFloat minimum = 0;
    for (UIView *item in self.items) minimum += MAX(44, item.bounds.size.width);
    CGFloat gap = self.items.count ? MAX(0, (available - minimum) / self.items.count) : 0;
    CGFloat x = 0;
    for (UIView *item in self.items) {
        CGFloat width = MAX(44, item.bounds.size.width);
        item.frame = CGRectMake(x, 0, width, 44);
        x += width + gap;
    }
    self.controls.contentSize = CGSizeMake(MAX(available, x), 44);
    self.controls.scrollEnabled = minimum > available;
    if (self.collapsed && ![self reduceMotionEnabled])
        self.controls.transform = CGAffineTransformMakeTranslation(available / 2 + 22, 0);
}

- (void)observeControl:(UIControl *)control
{
    [control addTarget:self action:@selector(controlPressed:) forControlEvents:UIControlEventTouchDown];
    [control addTarget:self action:@selector(controlReleased:)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

- (void)setItems:(NSArray<UIView *> *)items
{
    // Retained controls stay attached so selection changes preserve accessibility
    // focus, pointer hover, and a press that is still in progress.
    for (UIView *item in self.items) {
        if ([items containsObject:item]) continue;
        if ([item isKindOfClass:UIControl.class]) {
            UIControl *control = (UIControl *)item;
            [control removeTarget:self action:@selector(controlPressed:) forControlEvents:UIControlEventTouchDown];
            [control removeTarget:self action:@selector(controlReleased:)
                forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [self.pressedControls removeObject:control];
        }
        [item removeFromSuperview];
    }
    NSUInteger index = 0;
    for (UIView *item in items) {
        if (![self.items containsObject:item] && [item isKindOfClass:UIControl.class])
            [self observeControl:(UIControl *)item];
        if (item.superview != self.controls || [self.controls.subviews indexOfObject:item] != index)
            [self.controls insertSubview:item atIndex:index];
        index++;
    }
    _items = [items copy];
    [self setNeedsLayout];
    [self resetAutoHideTimer];
}

- (void)controlPressed:(UIControl *)control
{
    [self.pressedControls addObject:control];
    [self resetAutoHideTimer];
}

- (void)controlReleased:(UIControl *)control
{
    [self.pressedControls removeObject:control];
    [self resetAutoHideTimer];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.scrolling = YES;
    [self resetAutoHideTimer];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    self.scrolling = decelerate;
    [self resetAutoHideTimer];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    self.scrolling = NO;
    [self resetAutoHideTimer];
}

- (void)pointerHoverChanged:(UIHoverGestureRecognizer *)gesture
{
    self.pointerHovering = gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged;
    [self resetAutoHideTimer];
}

- (BOOL)voiceOverRunning { return UIAccessibilityIsVoiceOverRunning(); }
- (void)voiceOverStatusChanged:(NSNotification *)notification { [self resetAutoHideTimer]; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (void)toggleCollapsed { [self setCollapsed:!self.collapsed animated:YES]; }
- (void)hideContent { [self setCollapsed:YES animated:YES]; }
- (void)showContent { [self setCollapsed:NO animated:YES]; }

- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated
{
    [self layoutIfNeeded];
    BOOL changed = _collapsed != collapsed;
    _collapsed = collapsed;
    [self updateArrow];
    self.controls.userInteractionEnabled = !collapsed;
    self.controls.accessibilityElementsHidden = collapsed;
    CGAffineTransform transform = collapsed && ![self reduceMotionEnabled]
        ? CGAffineTransformMakeTranslation(self.controls.bounds.size.width / 2 + 22, 0) : CGAffineTransformIdentity;
    void (^changes)(void) = ^{
        self.controls.alpha = collapsed ? 0 : 1;
        self.controls.transform = transform;
    };
    if (animated && changed) {
        [UIView animateWithDuration:0.3 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
            animations:changes completion:nil];
    } else if (!animated) {
        [self.controls.layer removeAllAnimations];
        changes();
    }
    [self resetAutoHideTimer];
    if (changed && self.visibilityChanged) self.visibilityChanged(collapsed);
}

- (void)resetAutoHideTimer
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
    if (self.autoHide && !self.collapsed && self.superview &&
        !self.pressedControls.count && !self.scrolling && !self.pointerHovering && ![self voiceOverRunning])
        [self performSelector:@selector(hideContent) withObject:nil afterDelay:self.autoHideInterval];
}
- (void)applyAutoHideDelay:(NSTimeInterval)delay
{
    if (delay > 0) _autoHideInterval = delay;
    self.autoHide = delay > 0;
}
- (void)setAutoHide:(BOOL)autoHide
{
    _autoHide = autoHide;
    [self resetAutoHideTimer];
}
- (void)setAutoHideInterval:(float)interval
{
    _autoHideInterval = interval;
    [self resetAutoHideTimer];
}
- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    if (!newSuperview) {
        [self clearInteraction];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
    }
}
- (void)clearInteraction
{
    [self.pressedControls removeAllObjects];
    self.scrolling = NO;
    self.pointerHovering = NO;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) [self resetAutoHideTimer];
    else {
        [self clearInteraction];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideContent) object:nil];
    }
}
@end
