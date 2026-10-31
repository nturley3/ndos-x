#pragma once
#import <UIKit/UIKit.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN
// Immutable copies of the upstream menu. No engine objects cross to UIKit.
@interface NDOSXMenuItem : NSObject
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, readonly) NSInteger type; // action=0, submenu=1, separator=2/3
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL checked;
@property(nonatomic, readonly) BOOL isoPicker;
@property(nonatomic, copy, readonly) NSString *unavailableReason;
@property(nonatomic, copy, readonly) NSArray<NDOSXMenuItem *> *children;
@end

typedef uint64_t NDOSXMenuSession;
typedef void (^NDOSXMenuCompletion)(NSArray<NDOSXMenuItem *> *items, NSError * _Nullable error);
// Call from the main thread; completion is always asynchronous on the main thread.
// Open pauses the guest and releases input; requests execute on the worker while paused.
#ifdef __cplusplus
extern "C" {
#endif
NDOSXMenuSession ndos_x_menu_open(NDOSXMenuCompletion completion);
void ndos_x_menu_refresh(NDOSXMenuSession session, NDOSXMenuCompletion completion);
void ndos_x_menu_invoke(NDOSXMenuSession session, NSString *name, NDOSXMenuCompletion completion);
// Replaces one existing CD drive's media with an ISO inside the app's Documents directory.
void ndos_x_menu_replace_iso(NDOSXMenuSession session, NSString *target, NSURL *url, NDOSXMenuCompletion completion);
void ndos_x_menu_close(NDOSXMenuSession session);
#ifdef __cplusplus
}
#endif

@interface NDOSXMenuViewController : UITableViewController
// Owns one menu session until Done, interactive dismissal, or engine stop.
@property(nonatomic, copy, nullable) void (^didFinish)(void);
- (void)finish;
@end
NS_ASSUME_NONNULL_END
