#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

// Profiles live directly in Documents/config; relative guest paths use Documents.
@interface NDOSXProfiles : NSObject
@property (nonatomic, readonly) NSString *documentsDirectory;
- (instancetype)initWithDocumentsDirectory:(NSString *)directory;
- (NSArray<NSString *> *)filenamesWithError:(NSError **)error;
- (NSString *)pathForFilename:(NSString *)filename error:(NSError **)error;
- (NSString *)preferredFilename:(NSString *)remembered among:(NSArray<NSString *> *)filenames;
- (NSArray<NSString *> *)argumentsForPath:(NSString *)path;
@end

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
@interface NDOSXProfilePicker : UITableViewController
- (instancetype)initWithProfiles:(NDOSXProfiles *)profiles;
@property (nonatomic, copy) void (^didChoosePath)(NSString *path);
- (void)refresh;
@end
#endif
