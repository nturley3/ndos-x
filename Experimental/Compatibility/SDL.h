#pragma once
#include "../../vendor/SDL2/include/SDL.h"
#include "../Host/NDOSXHost.h"
typedef SDL_Scancode SDL_scancode;
typedef SDL_Keymod SDL_keymod;
typedef SDL_Keymod SDLMod;
#define SDL_SendKeyboardKey ndos_x_send_keyboard
#define SDL_GetModState() ((SDLMod)ndos_x_get_mod_state())
