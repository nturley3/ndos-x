#import "NDOSXHost.h"
#import "NDOSXMenu.h"
#include "SDL.h"
#include "dosbox.h"
#include "render.h"
#include "menu.h"
#include <future>
#include <thread>
#include <cstdio>

extern cpu_cycles_count_t CPU_CycleMax;
extern bool MENU_get_mute(void), MENU_get_swapstereo(void);
static void require(bool ok,const char *message) {
    if (!ok) { fprintf(stderr,"FAIL: %s\n",message);_Exit(1); }
}
static bool pumpUntil(BOOL (^predicate)(void), double seconds=3) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!predicate() && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return predicate();
}
static NDOSXMenuItem *find(NSArray<NDOSXMenuItem *> *items,NSString *name) {
    for (NDOSXMenuItem *item in items) {
        if ([item.name isEqualToString:name]) return item;
        NDOSXMenuItem *child=find(item.children,name);if(child)return child;
    }
    return nil;
}
int main() { @autoreleasepool {
    std::thread([]{std::this_thread::sleep_for(std::chrono::seconds(40));
        fprintf(stderr,"FAIL: menu watchdog\n");_Exit(124);}).detach();
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *configuration=[directory stringByAppendingPathComponent:@"menu.conf"];
    [@"[sdl]\noutput=surface\nshowmenu=true\nautolock=false\nwaitonerror=false\n"
      "[cpu]\ncore=normal\ncycles=fixed 20000\n[midi]\nmididevice=none\n[render]\nscaler=none\n"
        writeToFile:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *mount=[NSString stringWithFormat:@"mount c \"%@\"",directory];
    NSString *ready=[directory stringByAppendingPathComponent:@"READY.TXT"];
    SDL_SetMainReady();SDL_setenv("SDL_VIDEODRIVER","dummy",1);
    ndos_x_set_scene_paused(0);
    auto worker=std::async(std::launch::async,[&]{
        char *arguments[]={(char *)"ndos-x",(char *)"-conf",(char *)configuration.UTF8String,
            (char *)"-fastlaunch",(char *)"-c",(char *)mount.UTF8String,
            (char *)"-c",(char *)"c:",(char *)"-c",(char *)"echo ready>READY.TXT"};
        int result=ndos_x_engine_main(10,arguments);ndos_x_request_stop();return result;
    });
    require(pumpUntil(^BOOL{return [NSFileManager.defaultManager fileExistsAtPath:ready];},20),"guest reaches shell");
    __block BOOL done=NO;
    __block NSArray<NDOSXMenuItem *> *items;
    __block NSError *failure;
    auto reply=^(NSArray<NDOSXMenuItem *> *snapshot,NSError *error){
        items=snapshot;failure=error;done=YES;
    };
    auto wait=^{require(pumpUntil(^BOOL{return done;}),"menu request completes");done=NO;};
    NDOSXMenuSession session=ndos_x_menu_open(reply);wait();
    require(!failure && items.count>=7,"upstream top-level menu copied");
    require([items[0].name isEqualToString:@"MainMenu"] && [items[1].name isEqualToString:@"CpuMenu"],"upstream ordering");
    require(find(items,@"mixer_mute").enabled,"mute supported");
    require(!find(items,@"mapper_gui").enabled && find(items,@"mapper_gui").unavailableReason.length,"desktop dialog disabled with reason");
    require(find(items,@"frameskip_3").type==0,"nested menu traversal");
    // Worker has acknowledged the pause and no requests are outstanding. Engine
    // state is quiescent until the next request; inspect actual callback effects.
    require(!mainMenu.isVisible(),"SDL menu suppressed despite showmenu=true");
    ndos_x_menu_invoke(session,@"cpu386-25",reply);wait();
    require(!failure && CPU_CycleMax==4595,"CPU preset updates actual cycles");
    ndos_x_menu_invoke(session,@"frameskip_3",reply);wait();
    require(!failure && render.frameskip.max==3 && find(items,@"frameskip_3").checked,"frameskip updates renderer and checkmark");
    require(!find(items,@"frameskip_0").checked,"frameskip selection clears previous checkmark");
    bool muted=MENU_get_mute();
    ndos_x_menu_invoke(session,@"mixer_mute",reply);wait();
    require(!failure && MENU_get_mute()!=muted && find(items,@"mixer_mute").checked==!muted,"mute changes mixer and snapshot");
    bool swapped=MENU_get_swapstereo();
    ndos_x_menu_invoke(session,@"mixer_swapstereo",reply);wait();
    require(!failure && MENU_get_swapstereo()!=swapped && find(items,@"mixer_swapstereo").checked==!swapped,"stereo changes mixer and snapshot");
    ndos_x_menu_invoke(session,@"mapper_gui",reply);wait();require(failure!=nil,"SDL dialog rejected");
    ndos_x_menu_invoke(session,@"CpuMenu",reply);wait();require(failure!=nil,"submenu cannot dispatch");
    ndos_x_menu_invoke(session,@"unknown",reply);wait();require(failure!=nil,"unknown command rejected");
    // Exercise engine-state validation with a quiescent menu. Restore before resuming.
    mainMenu.get_item("mixer_mute").enable(false);
    ndos_x_menu_invoke(session,@"mixer_mute",reply);wait();require(failure!=nil,"upstream disabled command rejected");
    mainMenu.get_item("mixer_mute").enable(true);
    mainMenu.get_item("SoundMenu").hide(true);
    ndos_x_menu_refresh(session,reply);wait();require(!failure && !find(items,@"SoundMenu"),"hidden submenu omitted");
    ndos_x_menu_invoke(session,@"mixer_mute",reply);wait();require(failure!=nil,"command under hidden submenu rejected");
    mainMenu.get_item("SoundMenu").hide(false);
    ndos_x_menu_close(session);
    ndos_x_request_stop();
    require(worker.wait_for(std::chrono::seconds(3))==std::future_status::ready,"engine stops after menu close");
    (void)worker.get();
    puts("PASS: real engine hierarchy, CPU, frameskip, mixer, command validation, and SDL menu suppression");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    return 0;
}}
