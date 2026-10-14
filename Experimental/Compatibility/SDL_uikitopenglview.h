#pragma once
#import <UIKit/UIKit.h>
@protocol MouseHoldDelegate
- (void)onHold:(CGPoint)point;
- (void)cancelHold:(CGPoint)point;
- (void)onHoldMoved:(CGPoint)point;
@end
@protocol SDL_uikitopenglview_delegate
- (void)onResize:(CGSize)size;
- (BOOL)onDoubleTap:(CGPoint)point;
@end
// Target-only source compatibility: the host owns a plain UIKit view.
#define SDL_uikitopenglview NDOSXScreenView
@interface NDOSXScreenView : UIView
@property(nonatomic, weak) id<SDL_uikitopenglview_delegate> delegate;
@property(nonatomic, weak) id<MouseHoldDelegate> mouseHoldDelegate;
- (void)cancelEmulatorTouches;
- (void)sendMouseEvent:(int)index left:(BOOL)left down:(BOOL)down;
- (void)sendMouseMotion:(int)index x:(CGFloat)x y:(CGFloat)y;
- (void)sendMouseCoordinate:(int)index x:(CGFloat)x y:(CGFloat)y;
- (UIImage *)capture;
- (BOOL)resize:(CGSize)size;
@end
