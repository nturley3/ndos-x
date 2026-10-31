#import "NDOSXHost.h"
#import "NDOSXMenu.h"
#include "../../vendor/dosbox-x/include/ndos_x_menu.h"
#include <functional>
#include <cstring>
#include "../../vendor/SDL2/include/SDL.h"
#include <condition_variable>
#include <deque>
#include <mutex>
#include <array>
#include <vector>
#include <chrono>

namespace {
struct Input { enum Kind { Key, Motion, Button } kind; int code; bool down; float x, y; unsigned int mod = 0; std::chrono::steady_clock::time_point ready{}; };
std::mutex stateMutex;
std::condition_variable stateChanged;
std::deque<Input> input;
std::array<bool, SDL_NUM_SCANCODES> heldKeys{};
std::array<bool, 9> heldButtons{};
std::array<bool, SDL_NUM_SCANCODES> deliveredKeys{};
std::array<bool, 9> deliveredButtons{};
std::chrono::steady_clock::time_point nextKeyTime{};
constexpr unsigned int menuPause = 8;
std::deque<std::function<void(bool)>> controls;
NDOSXMenuSession menuSession = 0, nextMenuSession = 0;
unsigned int pauseReasons = 1; // A scene must become active before execution.
bool stopping = false;
bool releaseBeforePause = false;
SDL_Keymod modifiers = KMOD_NONE;
std::mutex frameMutex;
NSData *latestPixels;
int latestWidth, latestHeight;

SDL_Keymod modifiersForKeys() {
    unsigned int result = modifiers & (KMOD_CAPS | KMOD_NUM);
    const int codes[] = {SDL_SCANCODE_LSHIFT, SDL_SCANCODE_RSHIFT,
        SDL_SCANCODE_LCTRL, SDL_SCANCODE_RCTRL, SDL_SCANCODE_LALT,
        SDL_SCANCODE_RALT, SDL_SCANCODE_LGUI, SDL_SCANCODE_RGUI};
    const unsigned int bits[] = {KMOD_LSHIFT,KMOD_RSHIFT,KMOD_LCTRL,KMOD_RCTRL,
        KMOD_LALT,KMOD_RALT,KMOD_LGUI,KMOD_RGUI};
    for (int i=0;i<8;i++) if (heldKeys[codes[i]]) result |= bits[i];
    return static_cast<SDL_Keymod>(result);
}
void releaseLocked() {
    // Cancel pending input while releasing both producer-held and already
    // delivered states. A queued keyup may have cleared only the producer.
    input.clear();nextKeyTime=std::chrono::steady_clock::now();
    for (int code=0;code<SDL_NUM_SCANCODES;code++) if (heldKeys[code] || deliveredKeys[code]) {
        input.push_back({Input::Key,code,false,0,0}); heldKeys[code]=false;
    }
    for (int button=1;button<9;button++) if (heldButtons[button] || deliveredButtons[button]) {
        input.push_back({Input::Button,button,false,0,0}); heldButtons[button]=false;
    }
    modifiers = static_cast<SDL_Keymod>(modifiers & (KMOD_CAPS|KMOD_NUM));
    releaseBeforePause = true;
}
void setPause(unsigned int reason, bool paused) {
    { std::lock_guard<std::mutex> lock(stateMutex);
      if (paused && !(pauseReasons & reason)) releaseLocked();
      if (paused) pauseReasons |= reason; else pauseReasons &= ~reason; }
    stateChanged.notify_all();
}
}

extern "C" int ndos_x_send_keyboard(int, uint8_t state, SDL_Scancode scancode) {
    if (scancode <= SDL_SCANCODE_UNKNOWN || scancode >= SDL_NUM_SCANCODES) return 0;
    std::lock_guard<std::mutex> lock(stateMutex);
    bool down = state == SDL_PRESSED;
    if (pauseReasons || stopping || input.size()>=4096) return 0;
    heldKeys[scancode] = down;
    if (down && scancode==SDL_SCANCODE_CAPSLOCK) modifiers=static_cast<SDL_Keymod>(modifiers^KMOD_CAPS);
    if (down && scancode==SDL_SCANCODE_NUMLOCKCLEAR) modifiers=static_cast<SDL_Keymod>(modifiers^KMOD_NUM);
    modifiers = modifiersForKeys();
    auto ready=std::max(std::chrono::steady_clock::now(),nextKeyTime);
    nextKeyTime=ready+std::chrono::milliseconds(20);
    input.push_back({Input::Key,scancode,down,0,0,static_cast<unsigned int>(modifiers),ready});
    return 1;
}
extern "C" void ndos_x_send_mouse_motion(float x, float y) {
    std::lock_guard<std::mutex> lock(stateMutex);
    if (!pauseReasons && !stopping) {
        if (!input.empty() && input.back().kind==Input::Motion) {input.back().x+=x;input.back().y+=y;}
        else input.push_back({Input::Motion,0,false,x,y});
    }
}
extern "C" void ndos_x_send_mouse_button(int button, int pressed) {
    if (button<1 || button>8) return;
    std::lock_guard<std::mutex> lock(stateMutex);
    if (pauseReasons || stopping || heldButtons[button]==!!pressed) return;
    heldButtons[button]=!!pressed;
    input.push_back({Input::Button,button,!!pressed,0,0});
}
extern "C" void ndos_x_release_inputs(void) {
    {std::lock_guard<std::mutex> lock(stateMutex); releaseLocked();}
    stateChanged.notify_all();
}
extern "C" unsigned int ndos_x_get_mod_state(void) {std::lock_guard<std::mutex> lock(stateMutex);return modifiers;}
extern "C" void ndos_x_set_scene_paused(int paused) {setPause(1,paused);}
extern "C" void ndos_x_set_view_paused(int paused) {setPause(4,paused);}
extern "C" void ndos_x_set_settings_paused(int paused) {setPause(2,paused);}
extern "C" int ndos_x_settings_paused(void) {std::lock_guard<std::mutex> lock(stateMutex);return !!(pauseReasons&2);}
extern "C" void ndos_x_request_stop(void) {
    std::deque<std::function<void(bool)>> cancelled;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        stopping=true;menuSession=0;
        cancelled.swap(controls);
    }
    stateChanged.notify_all();
    for (auto &request : cancelled) request(false);
}

extern "C" int ndos_x_host_poll(void) {
    std::deque<Input> pending;
    SDL_Keymod mod;
    // Only this worker touches audio or live engine state. Control requests can
    // wake a paused worker without letting guest execution or input resume.
    static bool audioPaused = false;
    {
        std::unique_lock<std::mutex> lock(stateMutex);
        for (;;) {
            const bool shouldPauseAudio = pauseReasons != 0;
            if (audioPaused != shouldPauseAudio) {
                audioPaused = shouldPauseAudio;
                lock.unlock(); SDL_PauseAudio(audioPaused); lock.lock();
                continue;
            }
            if (stopping) return 1;
            // Deliver releases through GFX_Events before acknowledging menu open.
            if (releaseBeforePause) break;
            if (!controls.empty()) {
                auto request = std::move(controls.front());controls.pop_front();
                lock.unlock();
                @autoreleasepool { request(true); }
                lock.lock();
                continue;
            }
            if (!pauseReasons) break;
            stateChanged.wait(lock,[]{return stopping || !pauseReasons ||
                releaseBeforePause || !controls.empty();});
        }
        auto now=std::chrono::steady_clock::now();
        while(!input.empty() && input.front().ready<=now) {
            Input item=input.front();input.pop_front();pending.push_back(item);
            if(item.kind==Input::Key)deliveredKeys[item.code]=item.down;
            if(item.kind==Input::Button)deliveredButtons[item.code]=item.down;
        }
        releaseBeforePause=false;mod=modifiers;
    }
    SDL_SetModState(mod);
    for (const Input &item : pending) {
        SDL_Event event{};
        if (item.kind==Input::Key) {
            event.type=item.down?SDL_KEYDOWN:SDL_KEYUP;
            event.key.state=item.down?SDL_PRESSED:SDL_RELEASED;
            event.key.keysym.scancode=static_cast<SDL_Scancode>(item.code);
            event.key.keysym.sym=SDL_GetKeyFromScancode(event.key.keysym.scancode);
            event.key.keysym.mod=static_cast<Uint16>(item.mod);
        } else if (item.kind==Input::Motion) {
            event.type=SDL_MOUSEMOTION;
            static float remainderX=0,remainderY=0;
            remainderX+=item.x;remainderY+=item.y;
            event.motion.xrel=static_cast<int>(remainderX);event.motion.yrel=static_cast<int>(remainderY);
            remainderX-=event.motion.xrel;remainderY-=event.motion.yrel;
            if(!event.motion.xrel && !event.motion.yrel)continue;
        } else {
            event.type=item.down?SDL_MOUSEBUTTONDOWN:SDL_MOUSEBUTTONUP;
            event.button.button=static_cast<Uint8>(item.code);
            event.button.state=item.down?SDL_PRESSED:SDL_RELEASED;
        }
        if (SDL_PushEvent(&event)<0) NSLog(@"nDOS-X input queue failed: %s",SDL_GetError());
    }
    return 0;
}

extern "C" void ndos_x_host_present(const void *pixels, int width, int height,
                                     int pitch, unsigned int format) {
    if (!pixels || width<=0 || height<=0 || width>4096 || height>4096 || pitch<width*SDL_BYTESPERPIXEL(format)) return;
    @autoreleasepool {
        NSMutableData *copy=[NSMutableData dataWithLength:static_cast<NSUInteger>(width)*height*4];
        if (SDL_ConvertPixels(width,height,format,pixels,pitch,
            SDL_PIXELFORMAT_ABGR8888,copy.mutableBytes,width*4)<0) return;
        std::lock_guard<std::mutex> lock(frameMutex);
        latestPixels=copy;latestWidth=width;latestHeight=height;
    }
}
UIImage *ndos_x_take_frame(void) {
    NSCAssert([NSThread isMainThread],@"Frame presentation belongs to UIKit");
    NSData *pixels;int width,height;
    {std::lock_guard<std::mutex> lock(frameMutex);pixels=latestPixels;latestPixels=nil;width=latestWidth;height=latestHeight;}
    if (!pixels) return nil;
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,color,
        kCGBitmapByteOrder32Big|kCGImageAlphaNoneSkipLast,provider,NULL,false,kCGRenderingIntentDefault);
    UIImage *result=image?[UIImage imageWithCGImage:image]:nil;
    if(image)CGImageRelease(image);CGColorSpaceRelease(color);CGDataProviderRelease(provider);
    return result;
}

extern "C" int SDL_main(int, char **) {NSLog(@"nDOS-X owns startup through its host adapter");return 1;}

@interface NDOSXMenuItem ()
- (instancetype)initWithRecord:(NSDictionary *)record children:(NSArray<NDOSXMenuItem *> *)children;
@end
@implementation NDOSXMenuItem
- (instancetype)initWithRecord:(NSDictionary *)record children:(NSArray<NDOSXMenuItem *> *)children {
    if ((self=[super init])) {
        _name=[record[@"name"] copy];_title=[record[@"title"] copy];
        _type=[record[@"type"] integerValue];_enabled=[record[@"enabled"] boolValue];
        _checked=[record[@"checked"] boolValue];_isoPicker=[record[@"isoPicker"] boolValue];_unavailableReason=[record[@"reason"] copy];
        _children=[children copy];
    }
    return self;
}
@end

namespace {
NSError *menuError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"NDOSXMenu" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}
void copyMenuEntry(const ndos_x_menu_entry *entry, void *context) {
    NSMutableArray *records=(__bridge NSMutableArray *)context;
    // DOSBox-X owns these bytes only during the visitor call.
    NSString *(^copyString)(const char *) = ^NSString *(const char *text) {
        return [[NSString alloc] initWithBytes:text length:strlen(text)
                                      encoding:NSUTF8StringEncoding] ?: @"?";
    };
    [records addObject:@{@"name":copyString(entry->name), @"title":copyString(entry->text),
        @"reason":copyString(entry->unavailable_reason), @"depth":@(entry->depth),
        @"type":@(entry->type), @"enabled":@(entry->enabled), @"checked":@(entry->checked), @"isoPicker":@(entry->iso_picker)}];
}
NSArray<NDOSXMenuItem *> *menuTree(NSArray *records, NSUInteger &index, NSUInteger depth) {
    NSMutableArray *items=[NSMutableArray array];
    while (index<records.count && [records[index][@"depth"] unsignedIntegerValue]==depth) {
        NSDictionary *record=records[index++];
        NSArray *children=menuTree(records,index,depth+1);
        [items addObject:[[NDOSXMenuItem alloc] initWithRecord:record children:children]];
    }
    return [items copy];
}
void completeMenu(NDOSXMenuSession session, NDOSXMenuCompletion completion,
                  NSArray<NDOSXMenuItem *> *items, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *resultError=error;
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            if (stopping) resultError=menuError(3,@"The engine has stopped.");
            else if (!session || menuSession!=session)
                resultError=menuError(4,@"This menu session has closed.");
        }
        completion(resultError ? @[] : items,resultError);
    });
}
NSString *localISOPath(NSURL *url) {
    if (!url.isFileURL || ![url.pathExtension.lowercaseString isEqualToString:@"iso"]) return nil;
    NSString *root=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .firstObject.URLByResolvingSymlinksInPath.path;
    NSString *path=url.URLByResolvingSymlinksInPath.path;
    if (!root || ![path hasPrefix:[root stringByAppendingString:@"/"]] ||
        ![path.pathExtension.lowercaseString isEqualToString:@"iso"]) return nil;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        ![NSFileManager.defaultManager isReadableFileAtPath:path]) return nil;
    return path;
}
void enqueueMenu(NDOSXMenuSession session, NSString *name, NSURL *url, NDOSXMenuCompletion completion) {
    NSCAssert(NSThread.isMainThread,@"Menu requests belong to UIKit");
    NSString *command=[name copy];
    NSURL *image=[url copy];
    NDOSXMenuCompletion reply=[completion copy];
    auto request=[session,command,image,reply](bool running) {
        bool valid;
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            valid=running && !stopping && session && menuSession==session;
        }
        if (!valid) { completeMenu(session,reply,@[],menuError(4,@"Menu unavailable."));return; }
        NSString *path=image ? localISOPath(image) : nil;
        if (image && !path) {
            completeMenu(session,reply,@[],menuError(5,@"Choose a readable ISO file inside the nDOS-X folder."));
            return;
        }
        // The upstream CD loader uses CROSS_LEN (512-byte) filename buffers.
        if (image && strlen(path.fileSystemRepresentation)>=512) {
            completeMenu(session,reply,@[],menuError(5,@"The ISO path is too long. Move it closer to the nDOS-X folder and try again."));
            return;
        }
        // File metadata may involve I/O; revalidate after it, before entering the engine.
        {
            std::lock_guard<std::mutex> lock(stateMutex);
            valid=!stopping && session && menuSession==session;
        }
        if (!valid) { completeMenu(session,reply,@[],menuError(4,@"Menu unavailable."));return; }
        int result=image ? ndos_x_engine_menu_replace_iso(command.UTF8String,path.fileSystemRepresentation) :
            command ? ndos_x_engine_menu_invoke(command.UTF8String) : 0;
        NSMutableArray *records=[NSMutableArray array];
        if (!result) result=ndos_x_engine_menu_snapshot(copyMenuEntry,(__bridge void *)records);
        NSUInteger index=0;
        NSArray *items=result ? @[] : menuTree(records,index,0);
        NSError *error=result ? menuError(result,result==4 ? @"The disc could not be ejected. The previous disc remains selected." : result==3 ? @"The ISO could not be loaded. The previous disc remains selected." : result==1 ? @"The engine menu is not ready. Close and reopen it after startup." :
            @"This command is unavailable in nDOS-X or in the current engine state.") : nil;
        completeMenu(session,reply,items,error);
    };
    bool accepted;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        accepted=!stopping && session && menuSession==session && controls.size()<64;
        if (accepted) controls.push_back(request);
    }
    if (accepted) stateChanged.notify_all();
    else completeMenu(session,reply,@[],menuError(2,@"Menu unavailable or too many pending requests."));
}
}

NDOSXMenuSession ndos_x_menu_open(NDOSXMenuCompletion completion) {
    NSCAssert(NSThread.isMainThread,@"Menu requests belong to UIKit");
    NDOSXMenuSession session=0;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        if (!stopping && !menuSession) {
            session=menuSession=++nextMenuSession;
            releaseLocked();pauseReasons|=menuPause;
        }
    }
    enqueueMenu(session,nil,nil,completion);
    return session;
}
void ndos_x_menu_refresh(NDOSXMenuSession session, NDOSXMenuCompletion completion) {
    enqueueMenu(session,nil,nil,completion);
}
void ndos_x_menu_invoke(NDOSXMenuSession session, NSString *name, NDOSXMenuCompletion completion) {
    enqueueMenu(session,name,nil,completion);
}
void ndos_x_menu_replace_iso(NDOSXMenuSession session, NSString *target, NSURL *url, NDOSXMenuCompletion completion) {
    enqueueMenu(session,target,url,completion);
}
void ndos_x_menu_close(NDOSXMenuSession session) {
    NSCAssert(NSThread.isMainThread,@"Menu requests belong to UIKit");
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        if (!session || menuSession!=session) return;
        menuSession=0;pauseReasons&=~menuPause;
    }
    stateChanged.notify_all();
}
