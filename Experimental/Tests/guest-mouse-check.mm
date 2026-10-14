#import "NDOSXHost.h"
#include "SDL.h"
#include <chrono>
#include <cstdio>
#include <future>
#include <string>
#include <thread>
#include "guest-mouse-probe.h"

// Matches the eight words written by the real-mode DOS probe.
struct Sample {
    uint16_t buttons, x, y, driver;
    int16_t mickeyX, mickeyY;
    uint16_t callbacks, callbackMask;
};
static_assert(sizeof(Sample) == 16, "Guest feedback layout must remain sixteen bytes");

static bool readSample(const std::string &path, Sample &sample) {
    FILE *file = fopen(path.c_str(), "rb");
    if (!file) return false;
    bool complete = fread(&sample, 1, sizeof(sample), file) == sizeof(sample);
    fclose(file);
    return complete && sample.driver == 0xffff;
}

template<class Predicate>
static bool waitSample(const std::string &path, Sample &sample, Predicate matches,
                       int timeoutMilliseconds = 2000) {
    auto deadline = std::chrono::steady_clock::now()
                  + std::chrono::milliseconds(timeoutMilliseconds);
    do {
        if (readSample(path, sample) && matches(sample)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}

int main() {
    @autoreleasepool {
        std::thread([] {
            std::this_thread::sleep_for(std::chrono::seconds(30));
            fprintf(stderr, "FAIL: guest mouse watchdog\n");
            _Exit(124);
        }).detach();

        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSData dataWithBytes:program length:sizeof(program)]
            writeToFile:[directory stringByAppendingPathComponent:@"MPROBE.COM"] atomically:YES];
        NSString *configuration = [directory stringByAppendingPathComponent:@"test.conf"];
        NSString *profile = @"[sdl]\noutput=surface\nshowmenu=false\nautolock=false\nwaitonerror=false\n"
                             "[dosbox]\nmachine=svga_s3\nmemsize=128\n"
                             "[cpu]\ncore=normal\ncputype=pentium_mmx\ncycles=fixed 20000\n"
                             "[midi]\nmididevice=none\n[render]\nscaler=none\n";
        [profile writeToFile:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *mount = [NSString stringWithFormat:@"mount c \"%@\"", directory];
        std::string feedback = [directory stringByAppendingPathComponent:@"MOUSE.DAT"].UTF8String;

        ndos_x_set_scene_paused(0);
        ndos_x_set_view_paused(0);
        ndos_x_set_settings_paused(0);
        SDL_SetMainReady();
        SDL_setenv("SDL_VIDEODRIVER", "dummy", 1);
        auto worker = std::async(std::launch::async, [&] {
            char *arguments[] = {(char *)"ndos-x", (char *)"-conf", (char *)configuration.UTF8String,
                (char *)"-fastlaunch", (char *)"-c", (char *)mount.UTF8String,
                (char *)"-c", (char *)"c:", (char *)"-c", (char *)"C:\\MPROBE.COM"};
            return ndos_x_engine_main(10, arguments);
        });

        Sample sample{};
        bool ready = waitSample(feedback, sample, [](Sample) { return true; }, 15000);
        bool passed = ready;
        printf("READY=%d driver=%04x initial=(%u,%u) buttons=%u\n",
               ready, sample.driver, sample.x, sample.y, sample.buttons);
        if (ready) {
            Sample initial = sample;
            ndos_x_send_mouse_motion(32, -16);
            bool moved = waitSample(feedback, sample, [&](Sample value) {
                return value.x > initial.x && value.y < initial.y;
            });
            // Check a second complete sample so a transient/partial read cannot pass.
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            Sample stable{};
            moved = moved && readSample(feedback, stable)
                    && stable.x == sample.x && stable.y == sample.y;
            printf("%s guest INT33 motion: (%u,%u) -> (%u,%u)\n",
                   moved ? "PASS" : "FAIL", initial.x, initial.y, sample.x, sample.y);
            passed &= moved;

            bool counters = waitSample(feedback, sample, [](Sample value) {
                return value.mickeyX > 0 && value.mickeyY < 0;
            });
            printf("%s guest INT33 motion counters: (%d,%d)\n",
                   counters ? "PASS" : "FAIL", sample.mickeyX, sample.mickeyY);
            passed &= counters;
            bool callback = waitSample(feedback, sample, [](Sample value) {
                return value.callbacks > 0 && (value.callbackMask & 1);
            });
            printf("%s guest INT33 motion callback: count=%u mask=%u\n",
                   callback ? "PASS" : "FAIL", sample.callbacks, sample.callbackMask);
            passed &= callback;

            ndos_x_send_mouse_button(1, 1);
            bool leftDown = waitSample(feedback, sample, [](Sample value) {
                return (value.buttons & 1) && (value.callbackMask & 2);
            });
            printf("%s guest INT33 left down: buttons=%u\n", leftDown ? "PASS" : "FAIL", sample.buttons);
            passed &= leftDown;
            ndos_x_send_mouse_button(1, 0);
            bool leftUp = waitSample(feedback, sample, [](Sample value) {
                return !(value.buttons & 1) && (value.callbackMask & 4);
            });
            printf("%s guest INT33 left up: buttons=%u\n", leftUp ? "PASS" : "FAIL", sample.buttons);
            passed &= leftUp;
            ndos_x_send_mouse_button(3, 1);
            bool rightDown = waitSample(feedback, sample, [](Sample value) {
                return (value.buttons & 2) && (value.callbackMask & 8);
            });
            printf("%s guest INT33 right down: buttons=%u\n", rightDown ? "PASS" : "FAIL", sample.buttons);
            passed &= rightDown;
            ndos_x_send_mouse_button(3, 0);
        }
        ndos_x_request_stop();
        worker.wait();
        printf("%s GUEST MOUSE CHECK\n", passed ? "PASS" : "FAIL");
        if (!passed) fprintf(stderr, "Feedback fixture retained at %s\n", directory.UTF8String);
        return passed ? 0 : 1;
    }
}
