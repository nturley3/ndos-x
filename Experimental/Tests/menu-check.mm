#import "NDOSXHost.h"
#import "NDOSXMenu.h"
#include "SDL.h"
#include "dosbox.h"
#include "render.h"
#include "menu.h"
#include "ide.h"
#include "mem.h"
#include "cpu.h"
#include "../../vendor/dosbox-x/src/dos/drives.h"
#include "../../vendor/dosbox-x/include/ndos_x_menu.h"
#include <future>
#include <thread>
#include <cstdio>

extern cpu_cycles_count_t CPU_CycleMax, CPU_CycleUp, CPU_CycleDown, CPU_CyclePercUsed;
extern bool CPU_CycleAutoAdjust, ticksLocked;
extern uint32_t emulator_speed;
extern void KEYBOARD_SetAUXActive(bool);
extern void KEYBOARD_AUX_Write(Bitu);
extern void KEYBOARD_ClrBuffer();
extern uint32_t Keyb_ig_status();
extern uint8_t MSCDEX_GetSubUnit(char);
extern bool CDROM_IsEmpty(CDROM_Interface *);
extern int IDE_MatchCDROMDrive(char);
extern bool GetMSCDEXDriveBySubUnit(uint8_t, CDROM_Interface **);
extern void runImgmountISO(const std::string &, const std::string &, const std::vector<std::string> &, bool);
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
// Minimal ISO9660 fixtures with distinguishable sector contents and volume labels.
static void makeISO(NSString *path, const char *label, bool corrupt=false) {
    NSMutableData *image=[NSMutableData dataWithLength:24*2048];
    auto *bytes=static_cast<uint8_t *>(image.mutableBytes);
    uint8_t *pvd=bytes+16*2048;
    pvd[0]=1;memcpy(pvd+1,"CD001",5);pvd[6]=1;
    memset(pvd+40,' ',32);memcpy(pvd+40,label,strlen(label));
    pvd[80]=24;pvd[87]=24;pvd[120]=1;pvd[123]=1;
    pvd[124]=1;pvd[127]=1;pvd[129]=8;pvd[130]=8;
    uint8_t *entry=pvd+156;
    entry[0]=corrupt?0:34;entry[2]=18;entry[9]=18;
    entry[11]=8;entry[14]=8;entry[25]=2;entry[28]=1;entry[31]=1;entry[32]=1;
    uint8_t *root=bytes+18*2048;
    memcpy(root,entry,34);memcpy(root+34,entry,34);root[34+33]=1;
    uint8_t *file=root+68;file[0]=44;file[2]=20;file[9]=20;
    file[10]=static_cast<uint8_t>(strlen(label));file[17]=static_cast<uint8_t>(strlen(label));
    file[28]=1;file[31]=1;file[32]=10;memcpy(file+33,"DISC.TXT;1",10);
    uint8_t *end=bytes+17*2048;end[0]=255;memcpy(end+1,"CD001",5);end[6]=1;
    memcpy(bytes+20*2048,label,strlen(label));
    require([image writeToFile:path atomically:YES],"write ISO fixture");
}
static bool discIs(char drive, const char *label) {
    auto *iso=dynamic_cast<isoDrive *>(Drives[drive-'A']);
    DOS_File *file=nullptr;
    if (!iso || !iso->FileOpen(&file,"DISC.TXT",0)) return false;
    uint8_t contents[32]={};uint16_t size=sizeof(contents);
    const bool read=file->Read(contents,&size);
    file->Close();delete file;
    CDROM_Interface *cd=nullptr;uint8_t sector[2048]={};
    if (!GetMSCDEXDriveBySubUnit(MSCDEX_GetSubUnit(drive),&cd) || !cd) return false;
    const bool raw=cd->ReadSectorsHost(sector,false,20,1);
    cd->Release();
    return read && size==strlen(label) && !memcmp(contents,label,size) &&
        raw && !memcmp(sector,label,strlen(label));
}
static bool emptyCD(char drive) {
    if (!dynamic_cast<isoDrive *>(Drives[drive-'A'])) return false;
    CDROM_Interface *cd=nullptr;
    if (!GetMSCDEXDriveBySubUnit(MSCDEX_GetSubUnit(drive),&cd) || !cd) return false;
    const bool empty=CDROM_IsEmpty(cd);
    cd->Release();
    return empty;
}
int main(int argc, char **argv) { @autoreleasepool {
    BOOL reloadWindows=argc==3 && !strcmp(argv[1],"windows-relaunch");
    if (argc==3 && (!strcmp(argv[1],"windows") || reloadWindows)) {
        // The caller supplies a disposable, writable copy of an installed Windows disk.
        NSString *image=@(argv[2]);
        NSString *directory=[image stringByDeletingLastPathComponent];
        NSString *config=[directory stringByAppendingPathComponent:@"windows-test.conf"];
        NSString *contents=[NSString stringWithFormat:@"[sdl]\noutput=surface\nwaitonerror=false\n[dosbox]\nmemsize=64\n[cpu]\ncore=normal\ncputype=pentium_mmx\ncycles=fixed 60000\n[midi]\nmididevice=none\n[autoexec]\nimgmount c \"%@\" -t hdd\nboot c:\n",image];
        require([contents writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:nil],"Windows profile");
        SDL_SetMainReady();SDL_setenv("SDL_VIDEODRIVER","dummy",1);ndos_x_set_scene_paused(0);
        auto worker=std::async(std::launch::async,[&]{
            ndos_x_set_state_directory([NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"windows-test.slots"]]);
            char *args[]={(char *)"ndos-x",(char *)"-conf",(char *)config.UTF8String,(char *)"-fastlaunch"};
            int result=ndos_x_engine_main(4,args);ndos_x_request_stop();return result;
        });
        __block BOOL done=NO;
        __block NSError *failure;
        auto reply=^(NSArray<NDOSXMenuItem *> *items,NSError *error){failure=error;done=YES;};
        auto wait=^{require(pumpUntil(^BOOL{return done;},30),"Windows request completes");done=NO;};
        NDOSXMenuSession session=0;
        require(pumpUntil(^BOOL{
            [NSThread sleepForTimeInterval:1];
            NDOSXMenuSession probe=ndos_x_menu_open(reply);wait();
            BOOL ready=!failure && dos_kernel_disabled && (reloadWindows || (cpu.pmode && (cpu.cr0 & 0x80000000)));
            ndos_x_menu_close(probe);
            return ready;
        },120),"Windows disk boots and the guest is ready to load");
        if (!reloadWindows) [NSThread sleepForTimeInterval:12];
        session=ndos_x_menu_open(reply);wait();
        // Change one byte in extended guest RAM only while paused and restore it before resuming.
        uint8_t previous=phys_readb(0x300000);
        NSString *marker=[directory stringByAppendingPathComponent:@"windows-marker"];
        FILE *disk=nullptr;
        if (reloadWindows) {
            NSData *byte=[NSData dataWithContentsOfFile:marker];
            require(byte.length==1,"previous process marker");[byte getBytes:&previous length:1];
        } else {
            [[NSData dataWithBytes:&previous length:1] writeToFile:marker atomically:YES];
            ndos_x_menu_invoke(session,@"state_save_1",reply);wait();
            if (failure) NSLog(@"%@",failure);
            require(!failure,"Windows save");
            // MBR reserved bytes in the disposable image are outside the partition.
            disk=fopen(image.fileSystemRepresentation,"r+b");
            require(disk && fseek(disk,444,SEEK_SET)==0 && fputc(0x7b,disk)!=EOF && fclose(disk)==0,"later disk write");
        }
        phys_writeb(0x300000,previous^0xff);
        ndos_x_menu_invoke(session,@"state_load_1",reply);wait();
        if (failure) NSLog(@"%@",failure);
        require(!failure && phys_readb(0x300000)==previous,"Windows RAM restored");
        disk=fopen(image.fileSystemRepresentation,"rb");
        require(disk && fseek(disk,444,SEEK_SET)==0 && fgetc(disk)==0x7b,"Windows image write persists");fclose(disk);
        ndos_x_menu_close(session);
        [NSThread sleepForTimeInterval:3];
        session=ndos_x_menu_open(reply);wait();require(!failure && cpu.pmode,"restored guest runs");
        ndos_x_request_stop();
        require(worker.wait_for(std::chrono::seconds(5))==std::future_status::ready,"Windows engine stops");
        puts("PASS: booted Windows save/load, restored RAM, guest resumes and later image writes persist");
        return 0;
    }
    std::thread([]{std::this_thread::sleep_for(std::chrono::seconds(40));
        fprintf(stderr,"FAIL: menu watchdog\n");_Exit(124);}).detach();
    NSString *documents=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path;
    BOOL isolated=argc==3 && !strcmp(argv[1],"isolated");
    BOOL resumed=argc==3 && !strcmp(argv[1],"restore");
    NSString *directory=[documents stringByAppendingPathComponent:argc==3 ? @(argv[2]) : NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *first=[directory stringByAppendingPathComponent:@"Disc One.iso"];
    NSString *second=[directory stringByAppendingPathComponent:@"Disc Two.ISO"];
    NSString *corrupt=[directory stringByAppendingPathComponent:@"Corrupt.iso"];
    NSString *tiny=[directory stringByAppendingPathComponent:@"Tiny.iso"];
    [@"broken" writeToFile:tiny atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *missing=[directory stringByAppendingPathComponent:@"Missing.iso"];
    makeISO(first,"DISC_ONE");makeISO(second,"DISC_TWO");makeISO(corrupt,"BAD",true);
    NSString *configuration=[directory stringByAppendingPathComponent:@"menu.conf"];
    [[NSString stringWithFormat:@"[sdl]\noutput=surface\nshowmenu=true\nautolock=false\nwaitonerror=false\n"
      "[cpu]\ncore=normal\ncycles=fixed 20000\ncycleup=500\ncycledown=250\n[midi]\nmididevice=none\n[render]\nscaler=none\n"
      "[ide, primary]\nenable=true\n[ide, secondary]\nenable=true\n[autoexec]\n"
      "imgmount d \"%@\" -t iso\nimgmount e empty -t iso\n",first]
        writeToFile:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSData *originalConfiguration=[NSData dataWithContentsOfFile:configuration];
    // PROBE.COM waits on a guest-memory byte and acknowledges it with a second byte.
    const uint8_t probe[]={
        0xb8,0x00,0x90,0x8e,0xc0,                   // mov ax,9000h / mov es,ax
        0x26,0xc6,0x06,0,0,0x51,                   // mov byte es:[0],51h
        0x26,0x80,0x3e,1,0,0xa5,0x75,0xf8,         // wait for es:[1] == a5h
        0x26,0xc6,0x06,0,0,0x13,0xeb,0xfe          // acknowledge and loop
    };
    [[NSData dataWithBytes:probe length:sizeof(probe)] writeToFile:[directory stringByAppendingPathComponent:@"PROBE.COM"] atomically:YES];
    NSString *mount=[NSString stringWithFormat:@"mount c \"%@\"",directory];
    NSString *ready=[directory stringByAppendingPathComponent:@"READY.TXT"];
    [NSFileManager.defaultManager removeItemAtPath:ready error:nil];
    SDL_SetMainReady();SDL_setenv("SDL_VIDEODRIVER","dummy",1);
    ndos_x_set_scene_paused(0);
    auto worker=std::async(std::launch::async,[&]{
        ndos_x_set_state_directory([NSURL fileURLWithPath:[directory stringByAppendingPathComponent:isolated ? @"other.conf.slots" : @"menu.conf.slots"]]);
        char *arguments[]={(char *)"ndos-x",(char *)"-conf",(char *)configuration.UTF8String,
            (char *)"-fastlaunch",(char *)"-c",(char *)mount.UTF8String,
            (char *)"-c",(char *)"c:",(char *)"-c",(char *)"echo ready>READY.TXT",(char *)"-c",(char *)"probe.com",nullptr};
        if (resumed) arguments[10]=nullptr;
        int result=ndos_x_engine_main(resumed ? 10 : 12,arguments);ndos_x_request_stop();return result;
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
    if (isolated) {
        require(!find(items,@"state_load_1"),"second profile has an empty slot 1");
        ndos_x_menu_invoke(session,@"state_save_1",reply);wait();
        require(!failure && find(items,@"state_load_1"),"second profile saves in its own slot");
        ndos_x_request_stop();
        require(worker.wait_for(std::chrono::seconds(3))==std::future_status::ready,"second profile stops");
        return 0;
    }
    if (!resumed) {
        for (int attempt=0; phys_readb(0x90000)!=0x51 && attempt<20; ++attempt) {
            ndos_x_menu_close(session);
            [NSThread sleepForTimeInterval:0.05];
            session=ndos_x_menu_open(reply);wait();
        }
        require(phys_readb(0x90000)==0x51,"guest DOS program executing");
    }
    require(find(items,@"native_states").children.count==10,"ten slots");
    NSString *slotPath=[directory stringByAppendingPathComponent:@"menu.conf.slots/1.sav"];
    NSString *later=[directory stringByAppendingPathComponent:@"LATER.TXT"];
    if (!resumed) {
        require(!find(items,@"state_load_1"),"empty slot");
        // BIOS INT 15h enables both the AUX port and mouse packet reporting.
        KEYBOARD_SetAUXActive(true);
        KEYBOARD_AUX_Write(0xf4);
        KEYBOARD_ClrBuffer();
        mem_writeb(0x180000,0x71);
        ndos_x_menu_invoke(session,@"state_save_1",reply);wait();
        if (failure) NSLog(@"Save failed: %@",failure);
        require(!failure && find(items,@"state_save_1").confirmation.length,"overwrite confirmation");
        NSData *saved=[NSData dataWithContentsOfFile:slotPath];
        require(saved.length>0,"archive written");
        printf("State fixture: %s\n",slotPath.fileSystemRepresentation);
        NSString *temporary=[slotPath stringByAppendingString:@".tmp"];
        [NSFileManager.defaultManager createDirectoryAtPath:temporary withIntermediateDirectories:NO attributes:nil error:nil];
        [[NSData data] writeToFile:[temporary stringByAppendingPathComponent:@"obstruction"] atomically:YES];
        ndos_x_menu_invoke(session,@"state_save_1",reply);wait();
        require(failure && [saved isEqual:[NSData dataWithContentsOfFile:slotPath]],"failed overwrite preserves slot");
        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
        [@"later write" writeToFile:later atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    if (resumed) {
        NSArray *errors=@[@"Engine version mismatch", @"Memory (4 KiB pages) mismatch", @"Machine type mismatch",
                          @"Damaged or missing component", @"Damaged or missing component"];
        for (NSUInteger i=0; i<errors.count; ++i) {
            mem_writeb(0x180000,0x42);
            ndos_x_menu_invoke(session,[NSString stringWithFormat:@"state_load_%lu",(unsigned long)i+2],reply);wait();
            require([failure.localizedDescription containsString:errors[i]] && mem_readb(0x180000)==0x42,
                    "preflight rejects incompatible or damaged state without changing memory");
        }
        ndos_x_menu_invoke(session,@"state_load_9",reply);wait();
        require([failure.localizedDescription containsString:@"Damaged or missing component"],"incomplete ZIP entry rejected");
        ndos_x_menu_refresh(session,reply);wait();
        require([find(items,@"state_load_7").confirmation containsString:@"OTHER.EXE"],"different program named in confirmation");
    }
    KEYBOARD_AUX_Write(0xf5);
    KEYBOARD_SetAUXActive(false);
    KEYBOARD_ClrBuffer();
    mem_writeb(0x180000,0x42);
    ndos_x_menu_invoke(session,@"state_load_1",reply);wait();
    if (failure) NSLog(@"Load failed: %@",failure);
    require(!failure && mem_readb(0x180000)==0x71,"saved guest memory restored");
    constexpr uint32_t auxAndReporting=(1u<<13)|(1u<<21);
    require((Keyb_ig_status() & auxAndReporting)==auxAndReporting,"saved PS/2 port and packet reporting restored");
    require([NSFileManager.defaultManager fileExistsAtPath:later],"later disk write persists");
    phys_writeb(0x90001,0xa5);
    ndos_x_menu_close(session);
    [NSThread sleepForTimeInterval:0.2];
    session=ndos_x_menu_open(reply);wait();
    require(!failure && phys_readb(0x90000)==0x13,"restored program executes its next instruction sequence");
    if (resumed) {
        ndos_x_menu_invoke(session,@"state_load_8",reply);wait();
        require(failure && [ndos_x_state_stop_reason() containsString:@"CMOS"],"partial restore requires relaunch");
        require(worker.wait_for(std::chrono::seconds(3))==std::future_status::ready,"restored engine stops");
        [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
        puts("PASS: cross-launch DOS state, compatibility checks, ZIP integrity and persistent disk writes");
        return 0;
    }
    require(find(items,@"mixer_mute").enabled,"mute supported");
    require(!find(items,@"mapper_gui").enabled && find(items,@"mapper_gui").unavailableReason.length,"desktop dialog disabled with reason");
    require(find(items,@"frameskip_3").type==0,"nested menu traversal");
    // Worker has acknowledged the pause and no requests are outstanding. Engine
    // state is quiescent until the next request; inspect actual callback effects.
    require(!mainMenu.isVisible(),"SDL menu suppressed despite showmenu=true");
    ndos_x_menu_invoke(session,@"cpu386-25",reply);wait();
    require(!failure && CPU_CycleMax==4595,"CPU preset updates actual cycles");
    for (NSString *name in @[@"mapper_speedlock2",@"mapper_speednorm",@"mapper_speedup",@"mapper_slowdown",@"mapper_cycleup",@"mapper_cycledown"])
        require(find(items,name).enabled,"CPU timing action enabled");
    require(find(items,@"mapper_editcycles") && !find(items,@"mapper_editcycles").enabled,"cycle editor remains disabled");
    const auto fixedCycles=CPU_CycleMax;
    ndos_x_menu_invoke(session,@"mapper_speednorm",reply);wait();
    require(!failure && !ticksLocked && emulator_speed==100,"normal restores 100 percent");
    require([find(items,@"mapper_speedup").subtitle isEqual:@"Timing speed: 100%"],"normal timing subtitle");
    NSArray *oldSnapshot=items;
    ndos_x_menu_invoke(session,@"mapper_speedup",reply);wait();
    require(!failure && emulator_speed==105 && [find(items,@"mapper_slowdown").subtitle isEqual:@"Timing speed: 105%"],"speed up updates actual timing and subtitle");
    require([find(oldSnapshot,@"mapper_speedup").subtitle isEqual:@"Timing speed: 100%"],"subtitle snapshot owns immutable copy");
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    require(!failure && ticksLocked && find(items,@"mapper_speedlock2").checked,"turbo enabled and checked");
    require([find(items,@"mapper_speedup").subtitle isEqual:@"After Turbo: 105%"],"turbo subtitle distinguishes stored timing");
    ndos_x_menu_invoke(session,@"mapper_speedup",reply);wait();
    require(!failure && ticksLocked && emulator_speed==110,"speed adjustment preserves turbo");
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    require(!failure && !ticksLocked && !find(items,@"mapper_speedlock2").checked && emulator_speed==110,"turbo toggle restores stored timing");
    require([find(items,@"mapper_speedup").subtitle isEqual:@"Timing speed: 110%"],"subtitle after turbo toggle");
    ndos_x_menu_invoke(session,@"mapper_slowdown",reply);wait();
    require(!failure && emulator_speed==105,"slow down subtracts five points");
    for (int i=0;i<23;i++) {
        ndos_x_menu_invoke(session,@"mapper_slowdown",reply);wait();
        require(!failure,"repeated slow down succeeds");
    }
    require(emulator_speed==1,"slow down floors at one percent");
    ndos_x_menu_invoke(session,@"mapper_speedup",reply);wait();
    require(!failure && emulator_speed==5,"speed up from one reaches five percent");
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    ndos_x_menu_invoke(session,@"mapper_speednorm",reply);wait();
    require(!failure && !ticksLocked && emulator_speed==100 && !find(items,@"mapper_speedlock2").checked,"normal clears turbo and resets timing");
    require(CPU_CycleMax==fixedCycles && !CPU_CycleAutoAdjust,"timing controls preserve fixed CPU cycles");
    // Exercise upstream's automatic-cycle branch while the worker is quiescent.
    CPU_CycleAutoAdjust=true;
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    require(!failure && ticksLocked && !CPU_CycleAutoAdjust && CPU_CycleMax==fixedCycles/3,"turbo suspends automatic cycle adjustment");
    ndos_x_menu_invoke(session,@"mapper_speednorm",reply);wait();
    require(!failure && !ticksLocked && CPU_CycleAutoAdjust,"normal restores automatic adjustment");
    CPU_CycleAutoAdjust=false;CPU_CycleMax=fixedCycles;
    require(!ndos_x_send_keyboard(0,1,SDL_SCANCODE_A),"CPU menu retains guest pause");
    ndos_x_menu_refresh(session,reply);wait();
    require(!failure && [find(items,@"mapper_speedup").subtitle isEqual:@"Timing speed: 100%"],"refresh reports current timing");
    require(CPU_CycleUp==500 && CPU_CycleDown==250,"cycle step settings loaded from profile");
    require([find(items,@"mapper_cycleup").subtitle isEqual:@"CPU cycles: 4595"],"preset cycle count in subtitle");
    NSArray *oldCycles=items;
    ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
    require(!failure && CPU_CycleMax==5095 && [find(items,@"mapper_cycledown").subtitle isEqual:@"CPU cycles: 5095"],"configured absolute increment and subtitle");
    require([find(oldCycles,@"mapper_cycleup").subtitle isEqual:@"CPU cycles: 4595"],"cycle subtitle copied immutably");
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && CPU_CycleMax==4845,"configured absolute decrement");
    // The worker is paused and idle: set boundary/percentage fixtures directly.
    CPU_CycleMax=1000;CPU_CycleUp=20;CPU_CycleDown=20;
    ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
    require(!failure && CPU_CycleMax==1200,"percentage increment");
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && CPU_CycleMax==1000,"percentage decrement divides by step factor");
    CPU_CycleDown=250;CPU_CycleMax=200;
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && CPU_CycleMax==1,"fixed cycles clamp at one");
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && CPU_CycleMax==1,"repeated decrement respects minimum");
    CPU_CycleUp=500;CPU_CycleMax=fixedCycles;
    CPU_CycleAutoAdjust=true;CPU_CyclePercUsed=100;
    ndos_x_menu_refresh(session,reply);wait();
    require(!failure && [find(items,@"mapper_cycleup").subtitle isEqual:@"Automatic cycles target: 100%"],"automatic target subtitle");
    for (int i=0;i<2;i++) {
        ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
        require(!failure && CPU_CyclePercUsed==105,"automatic target upper bound");
    }
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && CPU_CyclePercUsed==100,"automatic target decreases five points");
    for (int i=0;i<22;i++) {
        ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
        require(!failure,"automatic target decrement succeeds");
    }
    require(CPU_CyclePercUsed==1 && CPU_CycleMax==fixedCycles,"automatic target lower bound preserves working cycle count while paused");
    require([find(items,@"mapper_cycledown").subtitle isEqual:@"Automatic cycles target: 1%"],"automatic lower bound subtitle");
    ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
    require(!failure && CPU_CyclePercUsed==6,"automatic target increases five points from minimum");
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    const auto turboCycles=CPU_CycleMax;
    require(!failure && ticksLocked && !CPU_CycleAutoAdjust && find(items,@"mapper_cycleup").enabled,"cycle controls remain available in turbo");
    require([find(items,@"mapper_cycleup").subtitle isEqual:[NSString stringWithFormat:@"CPU cycles: %lld",(long long)turboCycles]],"turbo displays working cycles");
    ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
    require(!failure && ticksLocked && CPU_CycleMax==turboCycles+500,"increment working cycles during turbo");
    ndos_x_menu_invoke(session,@"mapper_cycledown",reply);wait();
    require(!failure && ticksLocked && CPU_CycleMax==turboCycles+250,"decrement working cycles during turbo");
    ndos_x_menu_invoke(session,@"mapper_speedlock2",reply);wait();
    require(!failure && CPU_CycleAutoAdjust && CPU_CyclePercUsed==6 && [find(items,@"mapper_cycleup").subtitle isEqual:@"Automatic cycles target: 6%"],"leaving turbo restores automatic target readout");
    require(emulator_speed==100,"cycle adjustments preserve timing speed");
    CPU_CycleAutoAdjust=false;CPU_CyclePercUsed=100;
    ndos_x_menu_invoke(session,@"cpu386-25",reply);wait();
    require(!failure && CPU_CycleMax==fixedCycles,"restore fixed cycle fixture through preset");
    require(!ndos_x_send_keyboard(0,1,SDL_SCANCODE_A),"cycle actions retain menu pause");
    ndos_x_menu_invoke(session,@"frameskip_3",reply);wait();
    require(!failure && render.frameskip.max==3 && find(items,@"frameskip_3").checked,"frameskip updates renderer and checkmark");
    require(!find(items,@"frameskip_0").checked,"frameskip selection clears previous checkmark");
    bool muted=MENU_get_mute();
    ndos_x_menu_invoke(session,@"mixer_mute",reply);wait();
    require(!failure && MENU_get_mute()!=muted && find(items,@"mixer_mute").checked==!muted,"mute changes mixer and snapshot");
    bool swapped=MENU_get_swapstereo();
    ndos_x_menu_invoke(session,@"mixer_swapstereo",reply);wait();
    require(!failure && MENU_get_swapstereo()!=swapped && find(items,@"mixer_swapstereo").checked==!swapped,"stereo changes mixer and snapshot");
    // The pinned command parser rejects :ide: before parsing image paths. Build
    // this IDE-only fixture through upstream's direct mount API while quiescent.
    runImgmountISO(std::string("ide"),std::string("1s"),{std::string("empty")},false);
    ndos_x_menu_refresh(session,reply);wait();
    require(find(items,@"drive_D_mountimg").isoPicker && find(items,@"drive_D_mountimg").enabled,"configured CD exposes native picker");
    require(find(items,@"drive_E_mountimg").enabled,"empty CD drive accepts insertion");
    require(find(items,@"IDEDrive1s_mountimg").enabled,"IDE-only CD exposes native picker");
    require(!find(items,@"drive_C_mountimg").enabled && !find(items,@"drive_F_mountimg").enabled,"hard disk and vacant letter disabled");
    require(discIs('D',"DISC_ONE"),"initial disc sector readable");
    ndos_x_menu_invoke(session,@"drive_D_mountimg",reply);wait();require(failure!=nil,"native action never invokes desktop picker");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:second],reply);wait();
    require(!failure && discIs('D',"DISC_TWO"),"live replacement reads new disc contents");
    ndos_x_menu_replace_iso(session,@"drive_E_mountimg",[NSURL fileURLWithPath:tiny],reply);wait();
    require(failure!=nil,"invalid file in empty drive reports failure without stopping engine");
    ndos_x_menu_replace_iso(session,@"drive_E_mountimg",[NSURL fileURLWithPath:first],reply);wait();
    require(!failure && discIs('E',"DISC_ONE"),"insert into existing empty drive");
    ndos_x_menu_replace_iso(session,@"IDEDrive1s_mountimg",[NSURL fileURLWithPath:second],reply);wait();
    require(!failure,"replace IDE-only CD");
    for (NSString *path in @[corrupt,missing]) {
        ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:path],reply);wait();
        require(failure!=nil && discIs('D',"DISC_TWO"),"failed replacement preserves previous readable media");
    }
    NSString *moved=[directory stringByAppendingPathComponent:@"Moved.iso"];
    require([NSFileManager.defaultManager moveItemAtPath:second toPath:moved error:nil],"move active ISO fixture");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:corrupt],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"failed replacement retains original open media after file moved");
    require([NSFileManager.defaultManager moveItemAtPath:moved toPath:second error:nil],"restore fixture path");
    NSString *notISO=[directory stringByAppendingPathComponent:@"NotISO.cue"];
    makeISO(notISO,"NOT_ISO");
    NSString *folderISO=[directory stringByAppendingPathComponent:@"Folder.iso"];
    require([NSFileManager.defaultManager createDirectoryAtPath:folderISO withIntermediateDirectories:NO attributes:nil error:nil],"create non-file fixture");
    for (NSString *path in @[notISO,folderISO]) {
        ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:path],reply);wait();
        require(failure!=nil && discIs('D',"DISC_TWO"),"non-ISO file or directory rejected");
    }
    NSString *unreadable=[directory stringByAppendingPathComponent:@"Unreadable.iso"];makeISO(unreadable,"UNREADABLE");
    require([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0} ofItemAtPath:unreadable error:nil],"make unreadable fixture");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:unreadable],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"unreadable ISO rejected without changing media");
    require([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:unreadable error:nil],"restore fixture permissions");
    NSString *component=[@"x" stringByPaddingToLength:200 withString:@"x" startingAtIndex:0];
    NSString *deep=[[directory stringByAppendingPathComponent:component] stringByAppendingPathComponent:component];
    require([NSFileManager.defaultManager createDirectoryAtPath:deep withIntermediateDirectories:YES attributes:nil error:nil],"create long path fixture");
    NSString *longISO=[deep stringByAppendingPathComponent:@"Long.iso"];makeISO(longISO,"LONG");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:longISO],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"overlong engine path rejected before mounting");
    NSString *outside=[NSTemporaryDirectory() stringByAppendingPathComponent:@"outside.iso"];
    makeISO(outside,"OUTSIDE");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:outside],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"outside Documents rejected");
    NSString *link=[directory stringByAppendingPathComponent:@"escape.iso"];
    require([NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:outside error:nil],"create escape fixture");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:link],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"symlink escape rejected");
    for (NSString *target in @[@"drive_C_mountimg",@"drive_F_mountimg",@"IDEDrive1m_mountimg",@"mapper_gui"]) {
        ndos_x_menu_replace_iso(session,target,[NSURL fileURLWithPath:first],reply);wait();
        require(failure!=nil && discIs('D',"DISC_TWO"),"ineligible replacement target rejected");
    }
    ndos_x_menu_refresh(session,reply);wait();
    require(find(items,@"drive_D_unmount").enabled &&
        [find(items,@"drive_D_unmount").title isEqualToString:@"Eject disc"],"CD unmount row is native Eject disc");
    const int cdSlot=IDE_MatchCDROMDrive('D');
    require(cdSlot>=0,"CD drive has an IDE attachment");
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(!failure && emptyCD('D') && IDE_MatchCDROMDrive('D')==cdSlot,"DOS eject preserves empty CD hardware and association");
    require(discIs('E',"DISC_ONE"),"eject leaves another CD unchanged");
    require(find(items,@"drive_D_mountimg").enabled && find(items,@"drive_D_unmount").enabled,"empty CD remains available for insertion and eject");
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(!failure && emptyCD('D'),"repeated eject leaves empty CD drive");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:second],reply);wait();
    require(!failure && discIs('D',"DISC_TWO"),"insert ISO after eject without restarting");
    require([find(items,@"IDEDrive1s_unmount").title isEqualToString:@"Eject disc"],"IDE-only eject label");
    ndos_x_menu_invoke(session,@"IDEDrive1s_unmount",reply);wait();
    require(!failure && IDE_is_CDROM(0,true) && find(items,@"IDEDrive1s_mountimg").enabled,"IDE-only eject preserves CD device and insertion action");
    ndos_x_menu_invoke(session,@"IDEDrive1s_unmount",reply);wait();require(!failure,"repeated IDE-only eject");
    ndos_x_menu_replace_iso(session,@"IDEDrive1s_mountimg",[NSURL fileURLWithPath:second],reply);wait();
    require(!failure,"IDE-only ISO insertion after eject");
    for (NSString *target in @[@"drive_A_unmount",@"drive_C_unmount",@"drive_F_unmount",@"drive_Z_unmount",@"IDEDrive1m_unmount",@"unknown_unmount"]) {
        ndos_x_menu_invoke(session,target,reply);wait();
        require(failure!=nil && discIs('D',"DISC_TWO") && discIs('E',"DISC_ONE"),"invalid eject leaves CD media unchanged");
    }
    mainMenu.get_item("drive_D_unmount").enable(false);
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"upstream disabled eject rejected");
    mainMenu.get_item("drive_D_unmount").enable(true);
    // Exercise the booted-guest branch without requiring redistributable Windows media.
    // Worker is paused and idle, so this state remains stable through each request.
    mainMenu.get_item("DriveD").hide(true);
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:first],reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"replacement target under hidden menu rejected");
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(failure!=nil && discIs('D',"DISC_TWO"),"hidden eject target rejected");
    mainMenu.get_item("DriveD").hide(false);
    ndos_x_set_settings_paused(1);
    dos_kernel_disabled=true;
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:first],reply);wait();
    require(!failure && discIs('D',"DISC_ONE"),"booted guest replacement activates new image");
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(!failure && emptyCD('D') && IDE_MatchCDROMDrive('D')==cdSlot,"booted guest eject preserves empty CD hardware");
    require(discIs('E',"DISC_ONE"),"booted guest eject leaves other CD unchanged");
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:first],reply);wait();
    require(!failure && discIs('D',"DISC_ONE"),"booted guest reinsertion after eject");
    dos_kernel_disabled=false;
    ndos_x_set_settings_paused(0);
    require(!ndos_x_send_keyboard(0,1,SDL_SCANCODE_A),"replacement preserves menu pause after nested settings close");
    [NSFileManager.defaultManager removeItemAtPath:outside error:nil];
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
    ndos_x_menu_invoke(session,@"mapper_speedup",reply);wait();
    require(!failure && emulator_speed==105,"timing changed before closing menu");
    ndos_x_menu_invoke(session,@"mapper_cycleup",reply);wait();
    require(!failure && CPU_CycleMax==fixedCycles+500 && emulator_speed==105,"cycle increment preserves adjusted timing");
    ndos_x_menu_close(session);
    ndos_x_menu_replace_iso(session,@"drive_D_mountimg",[NSURL fileURLWithPath:second],reply);wait();
    require(failure!=nil,"closed session cannot replace media");
    ndos_x_menu_invoke(session,@"drive_D_unmount",reply);wait();
    require(failure!=nil,"closed session cannot eject media");
    NDOSXMenuSession stoppedSession=ndos_x_menu_open(reply);wait();
    require(!failure && [find(items,@"mapper_speedup").subtitle isEqual:@"Timing speed: 105%"],"reopened menu retains session timing");
    require([find(items,@"mapper_cycleup").subtitle isEqual:@"CPU cycles: 5095"],"cycle setting retained across menu reopening");
    require([[NSData dataWithContentsOfFile:configuration] isEqual:originalConfiguration],"menu changes never write profile");
    ndos_x_menu_invoke(stoppedSession,@"drive_D_unmount",reply);
    ndos_x_request_stop();wait();require(failure!=nil,"stop invalidates eject completion");
    require(worker.wait_for(std::chrono::seconds(3))==std::future_status::ready,"engine stops after menu close");
    (void)worker.get();
    puts("PASS: real engine hierarchy, CPU, frameskip, mixer, command validation, SDL menu suppression, live ISO replacement and eject, failure recovery, and booted-guest path");
    if (argc!=3 || resumed) [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    return 0;
}}
