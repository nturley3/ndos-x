#import "NDOSXProfiles.h"

static void require(BOOL passed, NSString *message)
{
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NDOSXProfiles *profiles = [[NDOSXProfiles alloc] initWithDocumentsDirectory:root];
        NSError *error = nil;
        NSArray *names = [profiles filenamesWithError:&error];
        require([names isEqual:@[@"ndos-x.conf"]], @"first launch creates default");
        NSString *config = [root stringByAppendingPathComponent:@"config"];
        NSString *lower = [config stringByAppendingPathComponent:@"ndos-x.conf"];
        NSString *upper = [config stringByAppendingPathComponent:@"NDOS-X.CONF"];
        [@"user edits" writeToFile:lower atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [profiles filenamesWithError:&error];
        require([[NSString stringWithContentsOfFile:lower encoding:NSUTF8StringEncoding error:nil] isEqual:@"user edits"], @"preserve edited default");
        [fm moveItemAtPath:lower toPath:upper error:nil];
        require([[profiles filenamesWithError:&error] isEqual:@[@"NDOS-X.CONF"]], @"uppercase default preserved");
        require(![[fm contentsOfDirectoryAtPath:config error:nil] containsObject:@"ndos-x.conf"], @"uppercase default does not create lowercase copy");
        [fm moveItemAtPath:upper toPath:lower error:nil];
        [@"upper alias" writeToFile:upper atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"lower wins" writeToFile:lower atomically:YES encoding:NSUTF8StringEncoding error:nil];
        require([[profiles filenamesWithError:&error] isEqual:@[@"ndos-x.conf"]], @"lowercase default wins over uppercase alias");
        [@"[autoexec]\n" writeToFile:[config stringByAppendingPathComponent:@"Windows.CONF"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"not a profile" writeToFile:[config stringByAppendingPathComponent:@"ui.cfg"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm createDirectoryAtPath:[config stringByAppendingPathComponent:@"folder.conf"] withIntermediateDirectories:NO attributes:nil error:nil];
        names = [profiles filenamesWithError:&error];
        require([names isEqual:@[@"Windows.CONF", @"ndos-x.conf"]], @"refresh finds added uppercase extension, sorts and excludes directories and cfg files");
        require([[profiles preferredFilename:@"Windows.CONF" among:names] isEqual:@"Windows.CONF"], @"remember available selection");
        require([[profiles preferredFilename:@"deleted.conf" among:names] isEqual:@"ndos-x.conf"], @"missing remembered selection falls back to default");
        NSString *custom = [profiles pathForFilename:@"Windows.CONF" error:&error];
        require(custom != nil, @"resolve custom config");
        require([[profiles argumentsForPath:custom] isEqual:@[@"ndos-x", @"-conf", custom]], @"custom config has no injected mounts");
        NSArray *arguments = [profiles argumentsForPath:lower];
        require(arguments.count == 7 && [arguments[4] containsString:[root stringByAppendingPathComponent:@"dos"]], @"default retains automatic C mount");
        require([profiles argumentsForPath:upper].count == 7, @"uppercase default retains C mount");
        [fm removeItemAtPath:custom error:nil];
        require([profiles pathForFilename:@"Windows.CONF" error:&error] == nil && error != nil, @"deleted selected file rejected before launch");
        require([profiles pathForFilename:@"../outside.conf" error:&error] == nil, @"reject filenames outside config folder");
        require([profiles pathForFilename:@"folder.conf" error:&error] == nil, @"reject directories at launch");
        require([profiles pathForFilename:@"ui.cfg" error:&error] == nil, @"reject non-conf launch");
        [fm setAttributes:@{NSFilePosixPermissions:@0000} ofItemAtPath:lower error:nil];
        require([profiles pathForFilename:@"ndos-x.conf" error:&error] == nil, @"reject unreadable selected file");
        [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:lower error:nil];
        [fm removeItemAtPath:root error:nil];
        puts("PASS: profile discovery, preservation, selection, validation and launch arguments");
    }
    return 0;
}
