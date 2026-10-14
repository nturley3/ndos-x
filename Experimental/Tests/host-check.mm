#import "NDOSXHost.h"
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
 ndos_x_set_scene_paused(1);require(ndos_x_host_poll()==0,"stop prep release poll");drain();
 auto stopping=std::async(std::launch::async,[]{return ndos_x_host_poll();});
 require(stopping.wait_for(std::chrono::milliseconds(40))==std::future_status::timeout,"pause before stop");ndos_x_request_stop();require(stopping.get()==1,"stop wakes paused worker");
 puts("PASS: stop wakes paused worker");SDL_Quit();puts("ALL HOST CHECKS PASSED");return 0;
}}
