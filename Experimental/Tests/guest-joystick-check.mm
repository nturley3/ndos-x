#import "NDOSXHost.h"
#include "SDL.h"
#include <chrono>
#include <cstdio>
#include <future>
#include <string>
#include <thread>
#include "guest-joystick-probe.h"

struct Sample {uint16_t x,y,buttons,marker;};
template<class Predicate>
static bool waitSample(const std::string &path, Sample &sample, Predicate matches, int milliseconds=3000) {
    auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(milliseconds);
    do {
        FILE *file=fopen(path.c_str(),"rb");
        bool complete=file && fread(&sample,1,sizeof(sample),file)==sizeof(sample);
        if (file) fclose(file);
        if (complete && sample.marker==0x594a && matches(sample)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now()<deadline);
    return false;
}
int main() {@autoreleasepool {
    std::thread([]{std::this_thread::sleep_for(std::chrono::seconds(30));_Exit(124);}).detach();
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSData dataWithBytes:program length:sizeof(program)] writeToFile:[directory stringByAppendingPathComponent:@"JPROBE.COM"] atomically:YES];
    NSString *configuration=[directory stringByAppendingPathComponent:@"test.conf"];
    [@"[sdl]\noutput=surface\nwaitonerror=false\nautolock=false\nshowmenu=false\n[cpu]\ncore=normal\ncycles=fixed 20000\n[midi]\nmididevice=none\n[joystick]\njoysticktype=2axis\ntimed=false\nautofire=false\n"
        writeToFile:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *mount=[NSString stringWithFormat:@"mount c \"%@\"",directory];
    std::string feedback=[directory stringByAppendingPathComponent:@"JOYSTICK.DAT"].UTF8String;
    SDL_SetMainReady();SDL_setenv("SDL_VIDEODRIVER","dummy",1);
    ndos_x_set_scene_paused(0);
    auto worker=std::async(std::launch::async,[&]{
        char *arguments[]={(char *)"ndos-x",(char *)"-conf",(char *)configuration.UTF8String,
            (char *)"-fastlaunch",(char *)"-c",(char *)mount.UTF8String,(char *)"-c",(char *)"c:",
            (char *)"-c",(char *)"C:\\JPROBE.COM"};
        return ndos_x_engine_main(10,arguments);
    });
    Sample sample{};
    bool passed=waitSample(feedback,sample,[](Sample s){return s.x>=126 && s.x<=129 && s.y>=126 && s.y<=129;},15000);
    passed &= ndos_x_joystick_status()==2;
    printf("%s guest BIOS centered joystick (%u,%u)\n",passed?"PASS":"FAIL",sample.x,sample.y);
    ndos_x_send_joystick_motion(-1,1);ndos_x_send_joystick_button(0,1);ndos_x_send_joystick_button(1,1);
    bool moved=waitSample(feedback,sample,[](Sample s){return s.x<10 && s.y>245 && !(s.buttons&0x30);});
    printf("%s guest BIOS axes and both buttons (%u,%u) buttons=%x\n",moved?"PASS":"FAIL",sample.x,sample.y,sample.buttons);passed &= moved;
    ndos_x_release_inputs();
    bool released=waitSample(feedback,sample,[](Sample s){return s.x>=126 && s.x<=129 && s.y>=126 && s.y<=129 && (s.buttons&0x30)==0x30;});
    printf("%s guest BIOS release recenters and releases both buttons\n",released?"PASS":"FAIL");passed &= released;
    ndos_x_send_joystick_motion(1,-1);ndos_x_send_joystick_button(1,1);
    bool opposite=waitSample(feedback,sample,[](Sample s){return s.x>245 && s.y<10 && (s.buttons&0x30)==0x10;});
    printf("%s guest BIOS opposite axes and independent button\n",opposite?"PASS":"FAIL");passed &= opposite;
    ndos_x_set_settings_paused(1);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    ndos_x_set_settings_paused(0);
    bool resumed=waitSample(feedback,sample,[](Sample s){return s.x>=126 && s.x<=129 && s.y>=126 && s.y<=129 && (s.buttons&0x30)==0x30;});
    printf("%s guest BIOS pause/resume has no held input\n",resumed?"PASS":"FAIL");passed &= resumed;
    ndos_x_request_stop();worker.wait();
    if (passed) [fm removeItemAtPath:directory error:nil];
    else fprintf(stderr,"Fixture retained: %s\n",directory.UTF8String);
    printf("%s GUEST JOYSTICK CHECK\n",passed?"PASS":"FAIL");return passed?0:1;
}}
