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

#import <UIKit/UIKit.h>


// Background-free landscape controls. Visibility is independent of auto-hide policy.
@interface FloatPanel : UIView
@property (nonatomic, readonly) UIView *contentView;
@property (nonatomic, readonly) UIButton *collapseButton;
@property (nonatomic, readonly, getter=isCollapsed) BOOL collapsed;
@property (nonatomic, assign) BOOL autoHide;
@property (nonatomic, assign) float autoHideInterval;
@property (nonatomic, copy) void (^visibilityChanged)(BOOL collapsed);

- (void)applyAutoHideDelay:(NSTimeInterval)delay;
- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated;
- (void)hideContent;
- (void)showContent;
- (void)setItems:(NSArray<UIView *> *)items;
@end
