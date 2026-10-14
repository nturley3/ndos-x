#import "NDOSXProfiles.h"

@implementation NDOSXProfiles
- (instancetype)initWithDocumentsDirectory:(NSString *)directory
{
    if ((self = [super init])) _documentsDirectory = [directory copy];
    return self;
}
- (NSString *)configDirectory
{
    return [self.documentsDirectory stringByAppendingPathComponent:@"config"];
}
- (NSArray<NSString *> *)filenamesWithError:(NSError **)error
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:self.configDirectory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *lower = [self.configDirectory stringByAppendingPathComponent:@"ndos-x.conf"];
    NSString *upper = [self.configDirectory stringByAppendingPathComponent:@"NDOS-X.CONF"];
    if (![fm fileExistsAtPath:lower] && ![fm fileExistsAtPath:upper]) {
        NSString *bundled = [NSBundle.mainBundle pathForResource:@"ndos-x" ofType:@"conf"];
        if (!bundled) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{NSLocalizedDescriptionKey:@"The bundled default configuration is missing."}];
            return nil;
        }
        if (![fm copyItemAtPath:bundled toPath:lower error:error]) return nil;
    }
    NSArray *entries = [fm contentsOfDirectoryAtPath:self.configDirectory error:error];
    if (!entries) return nil;
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in entries) {
        if ([name.pathExtension caseInsensitiveCompare:@"conf"] != NSOrderedSame) continue;
        NSDictionary *attributes = [fm attributesOfItemAtPath:[self.configDirectory stringByAppendingPathComponent:name] error:nil];
        if ([attributes[NSFileType] isEqual:NSFileTypeRegular]) [names addObject:name];
    }
    // The legacy uppercase spelling is an alias, not a second default profile.
    if ([names containsObject:@"ndos-x.conf"]) [names removeObject:@"NDOS-X.CONF"];
    return [names sortedArrayUsingSelector:@selector(compare:)];
}
- (NSString *)pathForFilename:(NSString *)filename error:(NSError **)error
{
    NSString *path = [self.configDirectory stringByAppendingPathComponent:filename ?: @""];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
    if (!filename.length || ![filename isEqual:filename.lastPathComponent] ||
        [filename.pathExtension caseInsensitiveCompare:@"conf"] != NSOrderedSame ||
        ![attributes[NSFileType] isEqual:NSFileTypeRegular] || ![fm isReadableFileAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{NSLocalizedDescriptionKey:@"The selected configuration is missing or cannot be read. Refresh the list and select another file."}];
        return nil;
    }
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!file) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{NSLocalizedDescriptionKey:@"The selected configuration cannot be opened."}];
        return nil;
    }
    [file closeFile];
    return path;
}
- (NSString *)preferredFilename:(NSString *)remembered among:(NSArray<NSString *> *)filenames
{
    if (remembered && [filenames containsObject:remembered]) return remembered;
    if ([filenames containsObject:@"ndos-x.conf"]) return @"ndos-x.conf";
    if ([filenames containsObject:@"NDOS-X.CONF"]) return @"NDOS-X.CONF";
    return filenames.firstObject;
}
- (NSArray<NSString *> *)argumentsForPath:(NSString *)path
{
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"ndos-x", @"-conf", path]];
    if ([path.lastPathComponent isEqual:@"ndos-x.conf"] || [path.lastPathComponent isEqual:@"NDOS-X.CONF"]) {
        NSString *dos = [self.documentsDirectory stringByAppendingPathComponent:@"dos"];
        [arguments addObjectsFromArray:@[@"-c", [NSString stringWithFormat:@"mount c \"%@\"", dos], @"-c", @"c:"]];
    }
    return arguments;
}
@end
