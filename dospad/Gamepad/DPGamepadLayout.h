#import <UIKit/UIKit.h>

@class DPGamepad;

// A full-screen input shield while arranging the two gamepad groups.
@interface DPGamepadLayout : UIView
- (instancetype)initWithGamepad:(DPGamepad *)pad
                    editorHost:(UIView *)host
                 reservedViews:(NSArray<UIView *> *)reservedViews
                  prepareInput:(dispatch_block_t)prepareInput;
- (void)reloadPositions;
- (void)cancel;
@end
