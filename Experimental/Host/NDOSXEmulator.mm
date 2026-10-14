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

//
// DOSPadEmulator
//
// Set up environment for the dosbox emulation.
// - disk c
//   By default, Documents folder is set up as diskc.
//   However, if a `*.ndos` folder is imported,
//   that folder will be mounted as diskc instead.
//
#import "DOSPadEmulator.h"
extern "C" {
#import "Common.h"
}
#import "keys.h"
#include "SDL.h"
#include <stdatomic.h>
#include <stdbool.h>
#import "SDL_keyboard_c.h"
#import "SDL_mouse_c.h"
#import "keyinfotable.h"
#import "NDOSXHost.h"
#import "NDOSXProfiles.h"




char dospad_error_msg[1000];
char diskc[256];
char diskd[256];
cmd_entry *cmd_list = 0;
int cmd_count = 0;
int dospad_pause_flag = 0;

int dospad_should_launch_game = 0;
int dospad_command_line_ready = 0;
char dospad_command_buffer[1024];


static DOSPadEmulator* _sharedInstance;
static BOOL engineAttempted;

#define MAX_PENDING_KEY_EVENTS 1000

@interface DOSPadEmulator ()
{
    SDL_Joystick *_joystick[4];
}

- (void)didCommandDone;

@end

@implementation DOSPadEmulator
@synthesize started;

//MARK: - Instance

+ (DOSPadEmulator*)sharedInstance
{
    if (!_sharedInstance)
    {
        _sharedInstance = [[DOSPadEmulator alloc] init];
    }
    return _sharedInstance;
}

+ (void)setSharedInstance:(DOSPadEmulator*)instance
{
    _sharedInstance = instance;
}

//MARK: - DOSBox Initilization
// Use config file 'name' under <diskc>/config.
// If not present, duplicate bundled ones.
// The bundled one will be copied into <diskc>/config
// so user can have a copy ready to work on.
- (NSString*)ensureConfigFile:(NSString*)name
{
    NSFileManager *fm = [NSFileManager defaultManager];

    // Make sure config directory exists under the disk c
    NSString *configDir = [self.diskcDirectory stringByAppendingPathComponent:@"config"];
    if (![fm fileExistsAtPath:configDir])
    {
        [fm createDirectoryAtPath:configDir withIntermediateDirectories:YES attributes:@{} error:nil];
    }

    NSString *path = [configDir stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:path])
        return path;

    // Try uppercase, as it could be saved by a DOS program
    path = [configDir stringByAppendingPathComponent:name.uppercaseString];
    if ([fm fileExistsAtPath:path])
        return path;

    path=[configDir stringByAppendingPathComponent:name];
    NSString *bundleConfigs = [[[NSBundle mainBundle] resourceURL]
        URLByAppendingPathComponent:@"configs"].path;

    NSError *err = nil;
    if (![fm copyItemAtPath:([name isEqualToString:@"ndos-x.conf"] ? [[NSBundle mainBundle] pathForResource:@"ndos-x" ofType:@"conf"] : [bundleConfigs stringByAppendingPathComponent:name])
            toPath:path error:&err])
    {
        NSLog(@"Copy configuration failed: %@",err);
        return nil;
    }
    return path;
}


- (id)init
{
    self = [super init];

    // By default, use Documents folder in app sandbox as the
    // disk C. It can be changed later to other location,
    // but it must be done before the emulation starts.
    self.diskcDirectory = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) lastObject];

    return self;
}

- (void)start
{
    NSAssert([NSThread isMainThread], @"Not in main thread");

    if (started || engineAttempted)
    {
        NSLog(@"Emulator %p already started", self);
        return;
    }

    _dospadConfigFile  = [self ensureConfigFile:@"dospad.cfg"];
    _uiConfigFile      = [self ensureConfigFile:@"ui.cfg"];
    _mfiConfigFile     = [self ensureConfigFile:@"mfi.cfg"];
    _gamepadConfigFile = [self ensureConfigFile:@"gamepad.cfg"];

    strcpy(diskc, self.diskcDirectory.UTF8String);
    //strcpy(diskd, "/var/mobile/Documents");


    chdir(diskc);
    // Initalize command history
    dospad_init_history();

    if (_delegate)
    {
        [_delegate emulatorWillStart:self];
    }

    //NSLog(@"Start dosbox in new thread");
    BOOL foreground=NO;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if(scene.activationState==UISceneActivationStateForegroundActive) foreground=YES;
    ndos_x_set_scene_paused(!foreground);
    engineAttempted = YES;
    started = YES;
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}

- (void) run {
    @autoreleasepool {
        NSString *dosDirectory=[self.diskcDirectory stringByAppendingPathComponent:@"dos"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dosDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NDOSXProfiles *profiles = [[NDOSXProfiles alloc] initWithDocumentsDirectory:self.diskcDirectory];
        NSArray<NSString *> *arguments = [profiles argumentsForPath:self.ndosXConfigPath];
        char **argv = (char **)calloc(arguments.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < arguments.count; ++i) argv[i] = (char *)arguments[i].UTF8String;
        SDL_SetMainReady();
        SDL_setenv("SDL_VIDEODRIVER","dummy",1);
        int exitStatus = ndos_x_engine_main((int)arguments.count,argv);
        free(argv);
        ndos_x_request_stop();
        dispatch_async(dispatch_get_main_queue(), ^{
            // Serialize the final history save with scene lifecycle saves.
            dospad_save_history();
            self->started = NO;
            NSLog(@"nDOS-X engine stopped with status %d",exitStatus);
            // Relaunching the engine in-process is deferred; preserve UIKit.
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NDOSXEngineStopped" object:@(exitStatus)];
        });
    }
}

//MARK: - View Controller Delegates
// Function takes a screenshot of the current dosbox window
- (void)takeScreenshot
{
    if (self.delegate)
    {
        [self.delegate emulator:self saveScreenshot:[self.diskcDirectory stringByAppendingPathComponent:@"dosbox-screenshot.png"]];
    }
}

- (void)open:(NSString*)path
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate)
        {
            [self.delegate emulator:self open:path];
        }
    });
}

//MARK: - SDL Input/Output
- (BOOL)canMountImage
{
    return NO; // Media is attached before boot in this experiment.
}

- (void)sendImageMountCommand:(NSString *)cmd completion:(void (^)(BOOL))completion
{
    completion(NO);
}

- (void)sendCommand:(NSString *)cmd
{
    NSLog(@"nDOS-X shell launch commands are deferred; use the guest keyboard");
}

- (void)sendText:(NSString *)text
{
    for (int i = 0; i < text.length; i++)
        [self sendChar:[text characterAtIndex:i]];
}

- (void)sendChar:(unichar)c
{
    if (dospad_settings_open()) return;
    Uint16 mod = 0;
    SDL_scancode code;

    if (c < 127) {
        /* figure out the SDL_scancode and SDL_keymod for this unichar */
        code = unicharToUIKeyInfoTable[c].code;
        mod  = unicharToUIKeyInfoTable[c].mod;
    }
    else {
        /* we only deal with ASCII right now */
        code = SDL_SCANCODE_UNKNOWN;
        mod = 0;
    }

    if (mod & KMOD_SHIFT) {
        /* If character uses shift, press shift down */
        SDL_SendKeyboardKey( 0, SDL_PRESSED, SDL_SCANCODE_LSHIFT);
    }
    /* send a keydown and keyup even for the character */
    [self sendKey:code];
    if (mod & KMOD_SHIFT) {
        /* If character uses shift, press shift back up */
        SDL_SendKeyboardKey( 0, SDL_RELEASED, SDL_SCANCODE_LSHIFT);
    }
}

- (void)sendKey:(int)scancode pressed:(BOOL)pressed
{
    if (dospad_settings_open()) return;
    SDL_SendKeyboardKey( 0, pressed?SDL_PRESSED:SDL_RELEASED, static_cast<SDL_scancode>(scancode));
}

- (void)sendKey:(int)scancode
{
    if (dospad_settings_open()) return;
    SDL_SendKeyboardKey( 0, SDL_PRESSED, static_cast<SDL_scancode>(scancode));
    SDL_SendKeyboardKey(0,SDL_RELEASED,static_cast<SDL_scancode>(scancode));
}

- (void)didCommandDone
{
    NSLog(@"Command done");
}

- (void)releaseJoystickInput
{
    ndos_x_release_inputs();
}

//MARK: - SDL Joystick
- (BOOL)ensureJoystick:(NSInteger)index
{
    return NO;
}


- (void)updateJoystick:(NSInteger)index x:(float)x y:(float)y
{
    // Controller parity is deferred.
}

- (void)joystickButton:(NSInteger)buttonIndex pressed:(BOOL)pressed joystickIndex:(NSInteger)index
{
    // Controller parity is deferred.
}

- (void)dealloc
{
    for (int i = 0;  i < sizeof(_joystick)/sizeof(_joystick[0]); i++)
    {
        SDL_JoystickClose(_joystick[i]);
    }
}

//MARK: - SDL Keyboard
- (void)disableSDLKeyboardInput
{
    // UIKit owns input; guest events remain enabled.
}

- (void)enableSDLKeyboardInput
{
    // UIKit owns input; guest events remain enabled.
}

@end

//MARK: - DOSBox Interface

const char *dospad_config_dir(void)
{
    //NSLog(@"nDOS config directory: %s", [_sharedInstance dospadConfigFile].stringByDeletingLastPathComponent.UTF8String);
    return [_sharedInstance dospadConfigFile].stringByDeletingLastPathComponent.UTF8String;
}

void dospad_pause(void) {ndos_x_set_view_paused(1);}
void dospad_resume(void) {ndos_x_set_view_paused(0);}
BOOL dospad_settings_open(void) {return ndos_x_settings_paused();}
void dospad_set_settings_open(BOOL open) {ndos_x_set_settings_paused(open);}

void dospad_command_done(void)
{

    [_sharedInstance performSelectorOnMainThread:@selector(didCommandDone) withObject:nil waitUntilDone:NO];
}

//TODO: Necessary function? Can we use SDK instead?
static int strcmp_case_insensitive(const char *cs, const char *ct)
{
    while (*cs && *ct) {
        if (toupper(*cs) < toupper(*ct)) {
            return -1;
        } else if (toupper(*cs) > toupper(*ct)) {
            return 1;
        }
        (void)(cs++), ct++;
    }
    if (*cs == 0 && *ct == 0) return 0;
    else if (*cs) return 1;
    else return -1;
}

#define ISBLANK(c) (c==' '||c=='\t'||c=='\n'||c=='\r')

void dospad_add_history(const char* cmd)
{
    int i;
    if (strlen(cmd) < 2) {
        return;
    }
    cmd_entry *entry = static_cast<cmd_entry *>(malloc(sizeof(cmd_entry)));
    memset(entry, 0, sizeof(cmd_entry));
    for (i = 0; cmd[i]; i++) {
        entry->cmd[i] = cmd[i];
        if (i > 250) {
            entry->cmd[i]=0;
            break;
        }
    }
    while (--i>=0) {
        if (!ISBLANK(entry->cmd[i]))
            break;
        else
            entry->cmd[i]=0;
    }
    if (cmd_list==0) {
        cmd_list=entry;
        cmd_count++;
    } else {
        cmd_entry *p;
        entry->next=cmd_list;
        cmd_list=entry;
        cmd_count++;
        for (p = cmd_list; p && p->next; p=p->next) {
            if (strcmp_case_insensitive(cmd, p->next->cmd)==0) {
                cmd_entry *tmp = p->next;
                p->next = tmp->next;
                free(tmp);
                cmd_count--;
            }
        }
    }
}

void dospad_save_history()
{
    NSString *path=[[NSString stringWithUTF8String:diskc] stringByAppendingPathComponent:@"HISTORY"];
    FILE *fp = fopen([path UTF8String], "w");
    if (fp == NULL) {
        return;
    }
    cmd_entry *p = cmd_list;
    int cnt=MAX_HISTORY_ITEMS;
    while (p && cnt-- > 0) {
        fprintf(fp, "%s\n", p->cmd);
        p = p->next;
    }
    fclose(fp);
}

void dospad_init_history()
{
    char buf[256];

    NSString *path=[[NSString stringWithUTF8String:diskc] stringByAppendingPathComponent:@"HISTORY"];
    FILE *fp = fopen([path UTF8String], "r");
    if (fp == NULL) {
        return;
    }

    while (fgets(buf, 256, fp)) {
        dospad_add_history(buf);
    }

    fclose(fp);
}

void dospad_should_pause(void)
{
    // The host polls and waits on its condition variable on the worker.
}

// Open file or disk image function
int dospad_open(const char *args)
{
    //[NSThread detachNewThreadSelector:@selector(open:) toTarget:_sharedInstance withObject:nil];

    // The shell runs on a worker without an NSRunLoop. Schedule the UI on main.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [_sharedInstance open:nil]; });

    // Args not used yet, but keep code active
    // NSString *s = [NSString stringWithUTF8String:args];
    // s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

   /* Taking screenshots with the "open" command doesn't make sense if the option is available in the landbar.
      Comment out this dospad code but keeping for reference

    if ([s isEqualToString:@"screenshot"]) // is this necessary?
    {
        [_sharedInstance performSelectorOnMainThread:@selector(takeScreenshot) withObject:nil waitUntilDone:NO];
    }
    else if (args[0] == 0)
    {
        [_sharedInstance performSelector:@selector(open:) withObject:nil afterDelay:0.5];
//      [_sharedInstance performSelectorOnMainThread:@selector(open:) withObject:nil waitUntilDone:NO];
    }
    else // I have no idea what this condition is for
    {
        [_sharedInstance performSelector:@selector(open:) withObject:s afterDelay:0.5];
    } */

    return 0;
}
