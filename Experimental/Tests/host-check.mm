#import "NDOSXHost.h"
#import "NDOSXMenu.h"
#include "SDL.h"
#include <future>
#include <thread>
#include <vector>
#include <cstdio>
#include <cstdlib>
extern "C" int ndos_x_host_poll(void);
extern "C" void ndos_x_host_present(const void *,int,int,int,unsigned int);
static void require(bool ok,const char *message) { if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);} }
static std::vector<SDL_Event> drain() { std::vector<SDL_Event> out; SDL_Event e; while(SDL_PeepEvents(&e,1,SDL_GETEVENT,SDL_FIRSTEVENT,SDL_LASTEVENT)>0)out.push_back(e);return out; }
static void resetInput() {ndos_x_release_inputs();require(ndos_x_host_poll()==0,"poll reset");drain();}
static std::vector<SDL_Event> collect(int rounds) {std::vector<SDL_Event> out;for(int n=0;n<rounds;n++){require(ndos_x_host_poll()==0,"poll");auto more=drain();out.insert(out.end(),more.begin(),more.end());std::this_thread::sleep_for(std::chrono::milliseconds(25));}return out;}
int main() {@autoreleasepool {
 std::thread([]{std::this_thread::sleep_for(std::chrono::seconds(20));fprintf(stderr,"FAIL: watchdog\n");_Exit(124);}).detach();
 SDL_SetMainReady();SDL_setenv("SDL_VIDEODRIVER","dummy",1);
 require(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_EVENTS|SDL_INIT_TIMER)==0,SDL_GetError());
 ndos_x_set_scene_paused(0);resetInput();
 ndos_x_send_keyboard(0,SDL_PRESSED,SDL_SCANCODE_A);collect(1);
 ndos_x_send_keyboard(0,SDL_RELEASED,SDL_SCANCODE_A);
 ndos_x_set_settings_paused(1);ndos_x_set_scene_paused(1);
 require(ndos_x_host_poll()==0,"release poll");auto released=drain();bool found=false;
 for(auto e:released)if(e.type==SDL_KEYUP&&e.key.keysym.scancode==SDL_SCANCODE_A)found=true;
 require(found,"pending keyup survives nested pause");
 auto waiting=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 require(waiting.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"paused worker blocks");
 ndos_x_set_settings_paused(0);
 require(waiting.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"scene pause survives closing settings");
 ndos_x_set_scene_paused(0);require(waiting.get()==0,"resume wakes worker");drain();
 ndos_x_set_view_paused(1);require(ndos_x_host_poll()==0,"view release poll");drain();
 auto hidden=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 ndos_x_set_scene_paused(0);
 require(hidden.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"active scene does not resume hidden view");
 ndos_x_set_scene_paused(1);require(hidden.get()==0,"new pause reason delivers releases");drain();
 auto inactive=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 ndos_x_set_view_paused(0);
 require(inactive.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"visible view does not resume inactive scene");
 ndos_x_set_scene_paused(0);require(inactive.get()==0,"active visible view resumes");drain();
 puts("PASS: pending keyup and independent scene/settings/view pause reasons");
 resetInput();
 for(int n=0;n<2;n++){ndos_x_send_keyboard(0,SDL_PRESSED,SDL_SCANCODE_L);ndos_x_send_keyboard(0,SDL_RELEASED,SDL_SCANCODE_L);}
 auto repeated=collect(6);std::vector<unsigned int> types;
 for(auto e:repeated)if(e.type==SDL_KEYDOWN||e.type==SDL_KEYUP)types.push_back(e.type);
 require(types==std::vector<unsigned int>{SDL_KEYDOWN,SDL_KEYUP,SDL_KEYDOWN,SDL_KEYUP},"repeated key transitions");
 puts("PASS: repeated characters");
 resetInput();ndos_x_send_keyboard(0,SDL_PRESSED,SDL_SCANCODE_LSHIFT);ndos_x_send_keyboard(0,SDL_PRESSED,SDL_SCANCODE_A);ndos_x_send_keyboard(0,SDL_RELEASED,SDL_SCANCODE_A);ndos_x_send_keyboard(0,SDL_RELEASED,SDL_SCANCODE_LSHIFT);
 auto shifted=collect(6);found=false;for(auto e:shifted)if(e.type==SDL_KEYDOWN&&e.key.keysym.scancode==SDL_SCANCODE_A)found=(e.key.keysym.mod&KMOD_LSHIFT)!=0;require(found,"per-event shift modifier");
 puts("PASS: modifier ordering");
 resetInput();int dx=0;for(int n=0;n<4;n++){ndos_x_send_mouse_motion(.25f,0);require(ndos_x_host_poll()==0,"mouse poll");for(auto e:drain())if(e.type==SDL_MOUSEMOTION)dx+=e.motion.xrel;}
 require(dx==1,"fractional relative movement preserved");puts("PASS: fractional mouse movement");
 unsigned char pixels[]={255,0,0,255,0,255,0,255};
 ndos_x_host_present(pixels,2,1,8,SDL_PIXELFORMAT_ABGR8888);pixels[0]=0;
 UIImage *frame=ndos_x_take_frame();require(frame&&frame.size.width==2&&frame.size.height==1,"frame dimensions");
 CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(frame.CGImage));require(CFDataGetBytePtr(data)[0]==255,"frame owns a copy");CFRelease(data);require(ndos_x_take_frame()==nil,"mailbox consumed once");
 puts("PASS: frame ownership and mailbox");
 // Exercise control requests on a worker that remains paused for guest execution.
 __block bool menuDone=false;
 __block NSArray<NDOSXMenuItem *> *menuItems;
 __block NSError *menuFailure;
 auto completion=^(NSArray<NDOSXMenuItem *> *items,NSError *error) {
     require(NSThread.isMainThread,"menu completion belongs to main thread");
     menuItems=items;menuFailure=error;menuDone=true;
 };
 auto waitMenu=^{
     auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(2);
     while(!menuDone && std::chrono::steady_clock::now()<deadline)
         [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
     require(menuDone,"menu request completes while paused");menuDone=false;
 };
 NDOSXMenuSession menu=ndos_x_menu_open(completion);
 require(menu!=0,"menu session opens");
 require(!ndos_x_send_keyboard(0,SDL_PRESSED,SDL_SCANCODE_A),"menu suppresses guest input");
 require(ndos_x_host_poll()==0,"menu open delivers releases first");drain();
 auto menuWorker=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 waitMenu();require(!menuFailure && menuItems.count==1,"menu snapshot while paused");
 require(menuItems[0].children.count==2,"menu hierarchy copied");
 NSArray *original=menuItems;
 ndos_x_menu_invoke(menu,@"mixer_mute",completion);waitMenu();
 require(!menuFailure && menuItems[0].children[0].checked,"menu command updates snapshot");
 require(!((NDOSXMenuItem *)((NDOSXMenuItem *)original[0]).children[0]).checked,"old snapshot immutable");
 ndos_x_menu_invoke(menu,@"mapper_gui",completion);waitMenu();require(menuFailure!=nil,"unsupported command rejected");
 ndos_x_menu_invoke(menu,@"missing",completion);waitMenu();require(menuFailure!=nil,"missing command rejected");
 ndos_x_set_scene_paused(1);require(menuWorker.get()==0,"nested scene pause delivers releases");drain();
 menuWorker=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 ndos_x_menu_close(menu);
 require(menuWorker.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"closing menu preserves scene pause");
 ndos_x_menu_refresh(menu,completion);waitMenu();require(menuFailure!=nil,"closed session rejected");
 NDOSXMenuSession newMenu=ndos_x_menu_open(completion);
 require(newMenu!=menu,"new session has unique identity");
 require(menuWorker.get()==0,"new menu delivers releases");drain();
 menuWorker=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 waitMenu();require(!menuFailure,"menu available during independent pause");
 ndos_x_menu_close(menu); // Stale close must not unpause the new session.
 ndos_x_menu_refresh(newMenu,completion);waitMenu();require(!menuFailure,"stale close leaves current session intact");
 ndos_x_menu_close(newMenu);ndos_x_set_scene_paused(0);
 require(menuWorker.get()==0,"menu worker resumes after all pauses clear");drain();
 puts("PASS: paused menu controls, immutable snapshots, unsupported commands and session lifetimes");
 ndos_x_set_scene_paused(1);require(ndos_x_host_poll()==0,"stop prep release poll");drain();
 auto stopping=std::async(std::launch::async,[]{while (!ndos_x_host_poll()) drain();return 1;});
 require(stopping.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"pause before stop");NDOSXMenuSession stoppingMenu=ndos_x_menu_open(completion);
 ndos_x_menu_refresh(stoppingMenu,completion);
 ndos_x_request_stop();require(stopping.get()==1,"stop wakes paused worker");
 waitMenu();require(menuFailure!=nil,"stop cancels queued menu requests");
 puts("PASS: stop wakes paused worker and cancels menu requests");SDL_Quit();puts("ALL HOST CHECKS PASSED");return 0;
}}
