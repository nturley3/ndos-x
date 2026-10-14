#pragma once
#include <stdint.h>
#include "../../vendor/SDL2/include/SDL_scancode.h"
#ifdef __cplusplus
extern "C" {
#endif
// UIKit producers enqueue input; only the emulator worker consumes it.
int ndos_x_send_keyboard(int index, uint8_t state, SDL_Scancode scancode);
void ndos_x_send_mouse_motion(float x, float y);
void ndos_x_send_mouse_button(int button, int pressed);
void ndos_x_release_inputs(void);
unsigned int ndos_x_get_mod_state(void);
void ndos_x_set_scene_paused(int paused);
void ndos_x_set_view_paused(int paused);
void ndos_x_set_settings_paused(int paused);
int ndos_x_settings_paused(void);
void ndos_x_request_stop(void);

#ifdef __cplusplus
}
#endif
#ifdef __cplusplus
int ndos_x_engine_main(int argc, char **argv);
#endif
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C"
#endif
UIImage *ndos_x_take_frame(void);
#endif
