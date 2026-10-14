#import "NDOSXHost.h"
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
    {std::lock_guard<std::mutex> lock(stateMutex);stopping=true;}
    stateChanged.notify_all();
}

extern "C" int ndos_x_host_poll(void) {
    std::deque<Input> pending;
    SDL_Keymod mod;
    {
        std::unique_lock<std::mutex> lock(stateMutex);
        if (pauseReasons) {
            lock.unlock(); SDL_PauseAudio(1); lock.lock();
            if (!releaseBeforePause)
                stateChanged.wait(lock,[]{return stopping || !pauseReasons || releaseBeforePause;});
            if (!pauseReasons && !stopping) {
                lock.unlock(); SDL_PauseAudio(0); lock.lock();
            }
        }
        if (stopping) return 1;
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
