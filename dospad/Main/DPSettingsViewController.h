#import <UIKit/UIKit.h>

@interface DPSettingsViewController : UITableViewController
@property (nonatomic, copy) void (^didFinish)(void);
#ifdef NDOS_X_HOST
- (void)closeTurboSession;
#endif
@end
