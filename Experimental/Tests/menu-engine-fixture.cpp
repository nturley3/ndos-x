// Host scheduling checks use a deterministic engine adapter. The real-engine
// integration check separately verifies upstream traversal and dispatch.
#include "../../vendor/dosbox-x/include/ndos_x_menu.h"
#include <cstring>
static bool muted=false;
extern "C" int ndos_x_engine_menu_snapshot(ndos_x_menu_visitor visitor, void *context) {
    const ndos_x_menu_entry menu={"SoundMenu","Sound","",0,1,1,0};
    const ndos_x_menu_entry mute={"mixer_mute","Mute","",1,0,1,muted};
    const ndos_x_menu_entry unavailable={"mapper_gui","Configuration tool","Not supported",1,0,0,0};
    visitor(&menu,context);visitor(&mute,context);visitor(&unavailable,context);
    return 0;
}
extern "C" int ndos_x_engine_menu_invoke(const char *name) {
    if (!strcmp(name,"drive_D_unmount")) return 4; // Deterministic eject failure.
    if (strcmp(name,"mixer_mute")) return 2;
    muted=!muted;return 0;
}

extern "C" int ndos_x_engine_menu_replace_iso(const char *, const char *) { return 2; }
