/*
 * Copyright (C) 2010 Yamagi Burmeister
 * Copyright (C) 1997-2005 Id Software, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA.
 *
 * Joystick threshold code is partially based on http://ioquake3.org code.
 *
 * =======================================================================
 *
 * This is the Quake II input system backend, implemented with SDL.
 *
 * =======================================================================
 */

#include <SDL.h>

#include "header/input.h"
#include "../../client/header/keyboard.h"
#include "../../client/header/client.h"

// Forward declaration for Key_StringToKeynum
extern int Key_StringToKeynum(char *str);

// Forward declaration for Cbuf_AddText
extern void Cbuf_AddText(char *text);
extern int Sys_Milliseconds(void);

#if !TARGET_OS_TV
#import <CoreMotion/CoreMotion.h>
#endif

// iOS GameController support
#ifdef __APPLE__
#include "TargetConditionals.h"
#if TARGET_OS_IOS || TARGET_OS_TV
#include "ios_gamecontroller_bridge.h"
#define USE_IOS_GAMECONTROLLER 1
#endif
#endif

// ----

// Maximal mouse move per frame
#define MOUSE_MAX 3000

// Minimal mouse move per frame
#define MOUSE_MIN 40

// ----

static int mouse_x, mouse_y;
static int back_button_id = -1;

#ifdef IOS
// Make these global (non-static) for iOS so Swift can access them
float joystick_yaw, joystick_pitch;
float joystick_forwardmove, joystick_sidemove;
#else

// Keep them static for other platforms
static float joystick_yaw, joystick_pitch;
static float joystick_forwardmove, joystick_sidemove;
#endif
static float joystick_up;
static qboolean mlooking;

// The last time input events were processed.
// Used throughout the client.
int sys_frame_time;

// Console Variables
cvar_t *vid_fullscreen;
cvar_t *freelook;
cvar_t *lookstrafe;
cvar_t *m_forward;
cvar_t *m_pitch;
cvar_t *m_side;
cvar_t *m_up;
cvar_t *m_yaw;
cvar_t *sensitivity;

static cvar_t *exponential_speedup;
static cvar_t *in_grab;
static cvar_t *m_filter;
static cvar_t *windowed_mouse;

#ifdef USE_IOS_GAMECONTROLLER
// iOS GameController cvars
static cvar_t *joy_haptic_strength;
static cvar_t *joy_deadzone;
static cvar_t *joy_leftStickSensitivity;
static cvar_t *joy_rightStickSensitivity;

// Button mapping cvars
static cvar_t *joy_buttonA_bind;
static cvar_t *joy_buttonB_bind;
static cvar_t *joy_buttonX_bind;
static cvar_t *joy_buttonY_bind;
static cvar_t *joy_leftShoulder_bind;
static cvar_t *joy_rightShoulder_bind;
static cvar_t *joy_leftTrigger_bind;
static cvar_t *joy_rightTrigger_bind;
static cvar_t *joy_dpadUp_bind;
static cvar_t *joy_dpadDown_bind;
static cvar_t *joy_dpadLeft_bind;
static cvar_t *joy_dpadRight_bind;
static cvar_t *joy_buttonMenu_bind;
static cvar_t *joy_buttonOptions_bind;
static cvar_t *joy_leftStickClick_bind;
static cvar_t *joy_rightStickClick_bind;

// iOS controller state tracking
typedef struct {
    qboolean buttonA;
    qboolean buttonB;
    qboolean buttonX;
    qboolean buttonY;
    qboolean leftShoulder;
    qboolean rightShoulder;
    qboolean leftTrigger;
    qboolean rightTrigger;
    qboolean dpadUp;
    qboolean dpadDown;
    qboolean dpadLeft;
    qboolean dpadRight;
    qboolean buttonMenu;
    qboolean buttonOptions;
    qboolean leftStickClick;
    qboolean rightStickClick;
} ios_controller_state_t;

static ios_controller_state_t ios_controller_state;
#endif

// ----

/* Haptic feedback types */
enum QHARPICTYPES {
    HAPTIC_EFFECT_UNKNOWN = -1,
    HAPTIC_EFFECT_BLASTER = 0,
    HAPTIC_EFFECT_MENY,
    HAPTIC_EFFECT_HYPER_BLASTER,
    HAPTIC_EFFECT_MACHINEGUN,
    HAPTIC_EFFECT_SHOTGUN,
    HAPTIC_EFFECT_SSHOTGUN,
    HAPTIC_EFFECT_RAILGUN,
    HAPTIC_EFFECT_ROCKETGUN,
    HAPTIC_EFFECT_GRENADE,
    HAPTIC_EFFECT_BFG,
    HAPTIC_EFFECT_PALANX,
    HAPTIC_EFFECT_IONRIPPER,
    HAPTIC_EFFECT_ETFRIFLE,
    HAPTIC_EFFECT_SHOTGUN2,
    HAPTIC_EFFECT_TRACKER,
    HAPTIC_EFFECT_PAIN,
    HAPTIC_EFFECT_STEP,
    HAPTIC_EFFECT_TRAPCOCK,
    HAPTIC_EFFECT_LAST
};

struct hapric_effects_cache {
    int effect_type;
    int effect_volume;
    int effect_id;
    int effect_x;
    int effect_y;
    int effect_z;
};

qboolean show_haptic;

static SDL_Haptic *joystick_haptic = NULL;
static SDL_Joystick *joystick = NULL;
static SDL_GameController *controller = NULL;

#if !TARGET_OS_TV
static CMMotionManager *motionManager = nil;
#endif

static int last_haptic_volume = 0;
static int last_haptic_efffect_size = HAPTIC_EFFECT_LAST;
static int last_haptic_efffect_pos = 0;
static struct hapric_effects_cache last_haptic_efffect[HAPTIC_EFFECT_LAST];

// Joystick sensitivity
static cvar_t *joy_yawsensitivity;
static cvar_t *joy_pitchsensitivity;
static cvar_t *joy_forwardsensitivity;
static cvar_t *joy_sidesensitivity;
static cvar_t *joy_upsensitivity;

// Joystick direction settings
static cvar_t *joy_axis_leftx;
static cvar_t *joy_axis_lefty;
static cvar_t *joy_axis_rightx;
static cvar_t *joy_axis_righty;
static cvar_t *joy_axis_triggerleft;
static cvar_t *joy_axis_triggerright;

// Joystick threshold settings
static cvar_t *joy_axis_leftx_threshold;
static cvar_t *joy_axis_lefty_threshold;
static cvar_t *joy_axis_rightx_threshold;
static cvar_t *joy_axis_righty_threshold;
static cvar_t *joy_axis_triggerleft_threshold;
static cvar_t *joy_axis_triggerright_threshold;

// Joystick haptic
static cvar_t *joy_haptic_magnitude;

#ifdef USE_IOS_GAMECONTROLLER
/*
 * Apply deadzone to stick input
 */
static float
IN_ApplyDeadzone(float value, float deadzone)
{
    if (fabs(value) < deadzone)
        return 0.0f;
    
    // Smooth ramp from deadzone to full value
    float sign = value < 0 ? -1.0f : 1.0f;
    return sign * ((fabs(value) - deadzone) / (1.0f - deadzone));
}

/*
 * iOS GameController haptic event
 */
void
IN_HapticEvent(float intensity, int duration_ms)
{
    if (!iOS_IsControllerConnected())
        return;
    
    if (joy_haptic_strength->value <= 0)
        return;
    
    float adjusted_intensity = intensity * joy_haptic_strength->value;
    iOS_TriggerHaptic(adjusted_intensity, duration_ms);
}

/*
 * Handle iOS GameController input
 */
static void
IN_iOSGameControllerMove(void)
{
    if (!iOS_IsControllerConnected())
    {
        joystick_yaw = 0;
        joystick_pitch = 0;
        joystick_forwardmove = 0;
        joystick_sidemove = 0;
        return;
    }
    
    float deadzone = joy_deadzone->value;
    float leftStickSens = joy_leftStickSensitivity->value;
    float rightStickSens = joy_rightStickSensitivity->value;
    
    // Get analog stick values
    float leftX = iOS_GetLeftStickX();
    float leftY = iOS_GetLeftStickY();
    float rightX = iOS_GetRightStickX();
    float rightY = iOS_GetRightStickY();
    
    // Apply acceleration curve to right stick for better precision
    float accelPower = 2.3f; // Higher = more curve (try 1.5 to 3.0)
    float rightXSign = rightX < 0 ? -1.0f : 1.0f;
    float rightYSign = rightY < 0 ? -1.0f : 1.0f;
    rightX = rightXSign * powf(fabsf(rightX), accelPower);
    rightY = rightYSign * powf(fabsf(rightY), accelPower);
    
    // Apply deadzone
    leftX = IN_ApplyDeadzone(leftX, deadzone);
    leftY = IN_ApplyDeadzone(leftY, deadzone);
    rightX = IN_ApplyDeadzone(rightX, deadzone);
    rightY = IN_ApplyDeadzone(rightY, deadzone);
    
    // Check if we're in menu/console
    qboolean in_menu = (cls.key_dest != key_game || cl_paused->value);
    
    if (in_menu)
    {
        // Clear movement when in menu
        joystick_yaw = 0;
        joystick_pitch = 0;
        joystick_forwardmove = 0;
        joystick_sidemove = 0;
        
        // Menu navigation with sticks
        static float stick_repeat_time = 0;
        float current_time = Sys_Milliseconds() * 0.001f;
        
        if (current_time > stick_repeat_time)
        {
            // Left stick for menu navigation
            if (leftY > 0.5f) {
                Key_Event(K_UPARROW, true, true);
                Key_Event(K_UPARROW, false, true);
                stick_repeat_time = current_time + 0.2f;
            }
            else if (leftY < -0.5f) {
                Key_Event(K_DOWNARROW, true, true);
                Key_Event(K_DOWNARROW, false, true);
                stick_repeat_time = current_time + 0.2f;
            }
            
            if (leftX > 0.5f) {
                Key_Event(K_RIGHTARROW, true, true);
                Key_Event(K_RIGHTARROW, false, true);
                stick_repeat_time = current_time + 0.2f;
            }
            else if (leftX < -0.5f) {
                Key_Event(K_LEFTARROW, true, true);
                Key_Event(K_LEFTARROW, false, true);
                stick_repeat_time = current_time + 0.2f;
            }
        }
        
        // In menu, use different button mappings
        typedef struct {
            int (*getter)(void);
            qboolean *state;
            int key;
        } menu_button_mapping_t;
        
        menu_button_mapping_t menu_buttons[] = {
            { iOS_GetButtonA, &ios_controller_state.buttonA, K_ENTER },      // A - Select/Enter
            { iOS_GetButtonB, &ios_controller_state.buttonB, K_ESCAPE },     // B - Back/Cancel
            { iOS_GetButtonX, &ios_controller_state.buttonX, K_ENTER },      // X - Also Enter
            { iOS_GetButtonY, &ios_controller_state.buttonY, K_ESCAPE },     // Y - Also Escape
            { iOS_GetDpadUp, &ios_controller_state.dpadUp, K_UPARROW },
            { iOS_GetDpadDown, &ios_controller_state.dpadDown, K_DOWNARROW },
            { iOS_GetDpadLeft, &ios_controller_state.dpadLeft, K_LEFTARROW },
            { iOS_GetDpadRight, &ios_controller_state.dpadRight, K_RIGHTARROW },
            { iOS_GetButtonMenu, &ios_controller_state.buttonMenu, K_ESCAPE },
            { iOS_GetButtonOptions, &ios_controller_state.buttonOptions, K_TAB },
        };
        
        for (int i = 0; i < sizeof(menu_buttons) / sizeof(menu_buttons[0]); i++)
        {
            qboolean pressed = menu_buttons[i].getter() ? true : false;
            qboolean was_pressed = *menu_buttons[i].state;
            
            if (pressed != was_pressed)
            {
                *menu_buttons[i].state = pressed;
                Key_Event(menu_buttons[i].key, pressed, true);
            }
        }
    }
    else
    {
        // In game - set joystick values for movement and look
        // Movement uses different scaling than look
        joystick_sidemove = leftX * leftStickSens;
        joystick_forwardmove = -leftY * leftStickSens;
        
        // Look values - use much higher scaling like Q3
        joystick_yaw = rightX * rightStickSens;
        joystick_pitch = rightY * rightStickSens;
        
        // Game button mappings with correct Xbox layout
        typedef struct {
            int (*getter)(void);
            qboolean *state;
            int key;
        } button_mapping_t;
        
        button_mapping_t buttons[] = {
            { iOS_GetButtonA, &ios_controller_state.buttonA, K_SPACE },          // A (Bottom) - Jump
            { iOS_GetButtonB, &ios_controller_state.buttonB, K_AUX11 },          // B (Right) - Crouch
            { iOS_GetButtonX, &ios_controller_state.buttonX, K_AUX1 },           // X (Left) - Help
            { iOS_GetButtonY, &ios_controller_state.buttonY, K_AUX2 },           // Y (Top) - Taunt
            { iOS_GetLeftShoulder, &ios_controller_state.leftShoulder, K_AUX3 }, // Prev Weapon
            { iOS_GetRightShoulder, &ios_controller_state.rightShoulder, K_AUX4 }, // Next Weapon
            { iOS_GetDpadUp, &ios_controller_state.dpadUp, K_AUX5 },             // Use Item
            { iOS_GetDpadDown, &ios_controller_state.dpadDown, K_AUX6 },         // Drop Item
            { iOS_GetDpadLeft, &ios_controller_state.dpadLeft, K_AUX7 },         // Prev Item
            { iOS_GetDpadRight, &ios_controller_state.dpadRight, K_AUX8 },       // Next Item
            { iOS_GetButtonMenu, &ios_controller_state.buttonMenu, K_ESCAPE },    // Menu
            { iOS_GetButtonOptions, &ios_controller_state.buttonOptions, K_TAB }, // Show Scores
            { iOS_GetLeftStickClick, &ios_controller_state.leftStickClick, K_AUX12 }, // Crouch
            { iOS_GetRightStickClick, &ios_controller_state.rightStickClick, K_AUX10 }, // Center View
        };
        
        for (int i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++)
        {
            qboolean pressed = buttons[i].getter() ? true : false;
            qboolean was_pressed = *buttons[i].state;
            
            if (pressed != was_pressed)
            {
                *buttons[i].state = pressed;
                Key_Event(buttons[i].key, pressed, true);
            }
        }
        
        // Handle triggers specially (analog to digital conversion)
        float leftTriggerValue = iOS_GetLeftTrigger();
        float rightTriggerValue = iOS_GetRightTrigger();
        
        qboolean leftTriggerPressed = leftTriggerValue > 0.5f;
        qboolean rightTriggerPressed = rightTriggerValue > 0.5f;
        
        if (leftTriggerPressed != ios_controller_state.leftTrigger)
        {
            ios_controller_state.leftTrigger = leftTriggerPressed;
            Key_Event(K_SPACE, leftTriggerPressed, true);  // Left trigger = Jump
        }
        
        if (rightTriggerPressed != ios_controller_state.rightTrigger)
        {
            ios_controller_state.rightTrigger = rightTriggerPressed;
            Key_Event(K_MOUSE1, rightTriggerPressed, true);  // Right trigger = Fire
        }
    }
}

/*
 * Console command to test controller
 */
static void
IN_TestController_f(void)
{
    Com_Printf("Testing iOS GameController detection...\n");
    
    if (iOS_IsControllerConnected())
    {
        Com_Printf("Controller is connected!\n");
        iOS_DebugControllerState();
    }
    else
    {
        Com_Printf("No controller connected.\n");
        Com_Printf("Triggering delayed check...\n");
        iOS_PerformDelayedControllerCheck();
    }
}

static void
IN_ControllerStatus_f(void)
{
    Com_Printf("=== Controller Status ===\n");
    if (iOS_IsControllerConnected()) {
        Com_Printf("Controller: CONNECTED\n");
        Com_Printf("Left Stick: X=%.2f Y=%.2f\n", iOS_GetLeftStickX(), iOS_GetLeftStickY());
        Com_Printf("Right Stick: X=%.2f Y=%.2f\n", iOS_GetRightStickX(), iOS_GetRightStickY());
        Com_Printf("Triggers: L=%.2f R=%.2f\n", iOS_GetLeftTrigger(), iOS_GetRightTrigger());
        Com_Printf("Deadzone: %.2f\n", joy_deadzone->value);
        Com_Printf("Sensitivity: Left=%.2f Right=%.2f\n",
                   joy_leftStickSensitivity->value, joy_rightStickSensitivity->value);
    } else {
        Com_Printf("Controller: NOT CONNECTED\n");
        Com_Printf("Note: Controllers must be connected before launching the game.\n");
    }
}

static void
IN_DebugController_f(void)
{
    iOS_DebugControllerState();
}
#endif // USE_IOS_GAMECONTROLLER

/* ------------------------------------------------------------------ */

/*
 * This creepy function translates SDL keycodes into
 * the id Tech 2 engines interal representation.
 */
static int
IN_TranslateSDLtoQ2Key(unsigned int keysym)
{
    int key = 0;

    /* These must be translated */
    switch (keysym)
    {
        case SDLK_PAGEUP:
            key = K_PGUP;
            break;
        case SDLK_KP_9:
            key = K_KP_PGUP;
            break;
        case SDLK_PAGEDOWN:
            key = K_PGDN;
            break;
        case SDLK_KP_3:
            key = K_KP_PGDN;
            break;
        case SDLK_KP_7:
            key = K_KP_HOME;
            break;
        case SDLK_HOME:
            key = K_HOME;
            break;
        case SDLK_KP_1:
            key = K_KP_END;
            break;
        case SDLK_END:
            key = K_END;
            break;
        case SDLK_KP_4:
            key = K_KP_LEFTARROW;
            break;
        case SDLK_LEFT:
            key = K_LEFTARROW;
            break;
        case SDLK_KP_6:
            key = K_KP_RIGHTARROW;
            break;
        case SDLK_RIGHT:
            key = K_RIGHTARROW;
            break;
        case SDLK_KP_2:
            key = K_KP_DOWNARROW;
            break;
        case SDLK_DOWN:
            key = K_DOWNARROW;
            break;
        case SDLK_KP_8:
            key = K_KP_UPARROW;
            break;
        case SDLK_UP:
            key = K_UPARROW;
            break;
        case SDLK_ESCAPE:
            key = K_ESCAPE;
            break;
        case SDLK_KP_ENTER:
            key = K_KP_ENTER;
            break;
        case SDLK_RETURN:
            key = K_ENTER;
            break;
        case SDLK_TAB:
            key = K_TAB;
            break;
        case SDLK_F1:
            key = K_F1;
            break;
        case SDLK_F2:
            key = K_F2;
            break;
        case SDLK_F3:
            key = K_F3;
            break;
        case SDLK_F4:
            key = K_F4;
            break;
        case SDLK_F5:
            key = K_F5;
            break;
        case SDLK_F6:
            key = K_F6;
            break;
        case SDLK_F7:
            key = K_F7;
            break;
        case SDLK_F8:
            key = K_F8;
            break;
        case SDLK_F9:
            key = K_F9;
            break;
        case SDLK_F10:
            key = K_F10;
            break;
        case SDLK_F11:
            key = K_F11;
            break;
        case SDLK_F12:
            key = K_F12;
            break;
        case SDLK_F13:
            key = K_F13;
            break;
        case SDLK_F14:
            key = K_F14;
            break;
        case SDLK_F15:
            key = K_F15;
            break;
        case SDLK_BACKSPACE:
            key = K_BACKSPACE;
            break;
        case SDLK_KP_PERIOD:
            key = K_KP_DEL;
            break;
        case SDLK_DELETE:
            key = K_DEL;
            break;
        case SDLK_PAUSE:
            key = K_PAUSE;
            break;
        case SDLK_LSHIFT:
        case SDLK_RSHIFT:
            key = K_SHIFT;
            break;
        case SDLK_LCTRL:
        case SDLK_RCTRL:
            key = K_CTRL;
            break;
        case SDLK_LGUI:
        case SDLK_RGUI:
            key = K_COMMAND;
            break;
        case SDLK_RALT:
        case SDLK_LALT:
            key = K_ALT;
            break;
        case SDLK_KP_5:
            key = K_KP_5;
            break;
        case SDLK_INSERT:
            key = K_INS;
            break;
        case SDLK_KP_0:
            key = K_KP_INS;
            break;
        case SDLK_KP_MULTIPLY:
            key = K_KP_STAR;
            break;
        case SDLK_KP_PLUS:
            key = K_KP_PLUS;
            break;
        case SDLK_KP_MINUS:
            key = K_KP_MINUS;
            break;
        case SDLK_KP_DIVIDE:
            key = K_KP_SLASH;
            break;
        case SDLK_MODE:
            key = K_MODE;
            break;
        case SDLK_APPLICATION:
            key = K_COMPOSE;
            break;
        case SDLK_HELP:
            key = K_HELP;
            break;
        case SDLK_PRINTSCREEN:
            key = K_PRINT;
            break;
        case SDLK_SYSREQ:
            key = K_SYSREQ;
            break;
        case SDLK_MENU:
            key = K_MENU;
            break;
        case SDLK_POWER:
            key = K_POWER;
            break;
        case SDLK_UNDO:
            key = K_UNDO;
            break;
        case SDLK_SCROLLLOCK:
            key = K_SCROLLOCK;
            break;
        case SDLK_NUMLOCKCLEAR:
            key = K_KP_NUMLOCK;
            break;
        case SDLK_CAPSLOCK:
            key = K_CAPSLOCK;
            break;
        default:
            break;
    }

    return key;
}

/* ------------------------------------------------------------------ */

/*
 * Updates the input queue state. Called every
 * frame by the client and does nearly all the
 * input magic.
 */
void IN_Update(void)
{
    qboolean want_grab;
    SDL_Event event;
    unsigned int key;
    
    // Restart TextInput on game switch
    static int text_input_restart_time = 0;
    
    if (text_input_restart_time > 0 && sys_frame_time > text_input_restart_time) {
        SDL_StartTextInput();
        text_input_restart_time = 0;
        Com_Printf("Text input restarted\n");
    }
    
    // Detect game changes
    static char last_game[64] = {0};
    cvar_t *game = Cvar_Get("game", "", 0);
    
    if (game && game->string && strcmp(last_game, game->string) != 0) {
        Q_strlcpy(last_game, game->string, sizeof(last_game));
        // Schedule a restart in 100ms
        text_input_restart_time = sys_frame_time + 100;
    }
    
    static char last_hat = SDL_HAT_CENTERED;
    static qboolean left_trigger = false;
    static qboolean right_trigger = false;

#if !TARGET_OS_TV
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"tiltAiming"] == 1) {
        cl.viewangles[PITCH] = -(([[[motionManager deviceMotion] attitude] roll] - 1.5) * 45);
    }
#endif

#ifdef USE_IOS_GAMECONTROLLER
    // Process iOS GameController input
    IN_iOSGameControllerMove();
#endif

    /* Get and process an event */
    while (SDL_PollEvent(&event))
    {
//        printf("SDL_PollEvent: %i\n", event.type);

        switch (event.type)
        {
#ifndef USE_IOS_GAMECONTROLLER  // Skip SDL joystick events when using iOS GameController
            case SDL_JOYDEVICEADDED:
                printf("JSADD\n");
                
                // cribbed from elsewhere -tkidd
                
                Com_Printf ("TAKE 2: %i joysticks were found.\n", SDL_NumJoysticks());
                
                if (SDL_NumJoysticks() > 0) {
                    for (int i = 0; i < SDL_NumJoysticks(); i++) {
                        joystick = SDL_JoystickOpen(i);
                        
                        Com_Printf ("The name of the joystick is '%s'\n", SDL_JoystickName(joystick));
                        Com_Printf ("Number of Axes: %d\n", SDL_JoystickNumAxes(joystick));
                        Com_Printf ("Number of Buttons: %d\n", SDL_JoystickNumButtons(joystick));
                        Com_Printf ("Number of Balls: %d\n", SDL_JoystickNumBalls(joystick));
                        Com_Printf ("Number of Hats: %d\n", SDL_JoystickNumHats(joystick));
                        
                        joystick_haptic = SDL_HapticOpenFromJoystick(joystick);
                        
                        if (joystick_haptic == NULL)
                        {
                            Com_Printf("Most likely joystick isn't haptic\n");
                        }
                        else
                        {
//                            IN_Haptic_Effects_Info();
                        }
                        
                        if(SDL_IsGameController(i))
                        {
                            SDL_GameControllerButtonBind backBind;
                            controller = SDL_GameControllerOpen(i);
                            
                            Com_Printf ("Controller settings: %s\n", SDL_GameControllerMapping(controller));
                            Com_Printf ("Controller axis: \n");
                            Com_Printf (" * leftx = %s\n", joy_axis_leftx->string);
                            Com_Printf (" * lefty = %s\n", joy_axis_lefty->string);
                            Com_Printf (" * rightx = %s\n", joy_axis_rightx->string);
                            Com_Printf (" * righty = %s\n", joy_axis_righty->string);
                            Com_Printf (" * triggerleft = %s\n", joy_axis_triggerleft->string);
                            Com_Printf (" * triggerright = %s\n", joy_axis_triggerright->string);
                            
                            Com_Printf ("Controller thresholds: \n");
                            Com_Printf (" * leftx = %f\n", joy_axis_leftx_threshold->value);
                            Com_Printf (" * lefty = %f\n", joy_axis_lefty_threshold->value);
                            Com_Printf (" * rightx = %f\n", joy_axis_rightx_threshold->value);
                            Com_Printf (" * righty = %f\n", joy_axis_righty_threshold->value);
                            Com_Printf (" * triggerleft = %f\n", joy_axis_triggerleft_threshold->value);
                            Com_Printf (" * triggerright = %f\n", joy_axis_triggerright_threshold->value);
                            
                            backBind = SDL_GameControllerGetBindForButton(controller, SDL_CONTROLLER_BUTTON_BACK);
                            
                            if (backBind.bindType == SDL_CONTROLLER_BINDTYPE_BUTTON)
                            {
                                back_button_id = backBind.value.button;
                                Com_Printf ("\nBack button JOY%d will be unbindable.\n", back_button_id+1);
                            }
                            
                            Cbuf_AddText(va("bind TRIG_RIGHT \"+attack\"\n"));
                            Cbuf_AddText(va("bind JOY1 \"+movedown\"\n"));
                            Cbuf_AddText(va("bind JOY2 \"+moveup\"\n"));
                            Cbuf_AddText(va("bind JOY3 \"cmd help\"\n"));
                            Cbuf_AddText(va("bind JOY5 \"weapnext\"\n"));
                            Cbuf_AddText(va("bind JOY6 \"weapprev\"\n"));

                            break;
                        }
                        else
                        {
                            char joystick_guid[256] = {0};
                            
                            SDL_JoystickGUID guid;
                            guid = SDL_JoystickGetDeviceGUID(i);
                            
                            SDL_JoystickGetGUIDString(guid, joystick_guid, 255);
                            
                            Com_Printf ("To use joystick as game controller please set SDL_GAMECONTROLLERCONFIG:\n");
                            Com_Printf ("e.g.: SDL_GAMECONTROLLERCONFIG='%s,%s,leftx:a0,lefty:a1,rightx:a2,righty:a3,back:b1,...\n", joystick_guid, SDL_JoystickName(joystick));
                        }
                    }
                }
                
                break;
#endif // !USE_IOS_GAMECONTROLLER
                
            case SDL_MOUSEWHEEL:
                Key_Event((event.wheel.y > 0 ? K_MWHEELUP : K_MWHEELDOWN), true, true);
                Key_Event((event.wheel.y > 0 ? K_MWHEELUP : K_MWHEELDOWN), false, true);
                break;

            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP:
                switch (event.button.button)
                {
                    case SDL_BUTTON_LEFT:
                        key = K_MOUSE1;
                        break;
                    case SDL_BUTTON_MIDDLE:
                        key = K_MOUSE3;
                        break;
                    case SDL_BUTTON_RIGHT:
                        key = K_MOUSE2;
                        break;
                    case SDL_BUTTON_X1:
                        key = K_MOUSE4;
                        break;
                    case SDL_BUTTON_X2:
                        key = K_MOUSE5;
                        break;
                    default:
                        return;
                }

                Key_Event(key, (event.type == SDL_MOUSEBUTTONDOWN), true);
                break;

            case SDL_MOUSEMOTION:
                if (cls.key_dest == key_game && (int) cl_paused->value == 0)
                {
                    mouse_x += event.motion.xrel;
                    mouse_y += event.motion.yrel;
                }
                break;

            case SDL_TEXTINPUT:
                if ((event.text.text[0] >= ' ') && (event.text.text[0] <= '~'))
                {
                    Char_Event(event.text.text[0]);
                }

                break;

            case SDL_KEYDOWN:
            case SDL_KEYUP:
            {
                qboolean down = (event.type == SDL_KEYDOWN);

                /* workaround for AZERTY-keyboards, which don't have 1, 2, ..., 9, 0 in first row:
                 * always map those physical keys (scancodes) to those keycodes anyway
                 * see also https://bugzilla.libsdl.org/show_bug.cgi?id=3188 */
                SDL_Scancode sc = event.key.keysym.scancode;

                if (sc >= SDL_SCANCODE_1 && sc <= SDL_SCANCODE_0)
                {
                    /* Note that the SDL_SCANCODEs are SDL_SCANCODE_1, _2, ..., _9, SDL_SCANCODE_0
                     * while in ASCII it's '0', '1', ..., '9' => handle 0 and 1-9 separately
                     * (quake2 uses the ASCII values for those keys) */
                    int key = '0'; /* implicitly handles SDL_SCANCODE_0 */

                    if (sc <= SDL_SCANCODE_9)
                    {
                        key = '1' + (sc - SDL_SCANCODE_1);
                    }

                    Key_Event(key, down, false);
                }
                else
                {
                    if ((event.key.keysym.sym >= SDLK_SPACE) && (event.key.keysym.sym < SDLK_DELETE))
                    {
                        Key_Event(event.key.keysym.sym, down, false);
                    }
                    else
                    {
                        Key_Event(IN_TranslateSDLtoQ2Key(event.key.keysym.sym), down, true);
                    }
                }

                break;
            }

            case SDL_WINDOWEVENT:
                if (event.window.event == SDL_WINDOWEVENT_FOCUS_LOST ||
                    event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED)
                {
                    Key_MarkAllUp();
                }
                else if (event.window.event == SDL_WINDOWEVENT_MOVED)
                {
                    // make sure GLimp_GetRefreshRate() will query from SDL again - the window might
                    // be on another display now!
                    glimp_refreshRate = -1;
                }
                break;

#ifndef USE_IOS_GAMECONTROLLER  // Skip SDL controller events when using iOS GameController
            case SDL_CONTROLLERBUTTONUP:
            case SDL_CONTROLLERBUTTONDOWN: /* Handle Controller Back button */
            {
                qboolean down = (event.type == SDL_CONTROLLERBUTTONDOWN);

                if (event.cbutton.button == SDL_CONTROLLER_BUTTON_BACK)
                {
                    Key_Event(K_JOY_BACK, down, true);
                }

                break;
            }

            case SDL_CONTROLLERAXISMOTION:  /* Handle Controller Motion */
            {
                char *direction_type;
                float threshold = 0;
                float fix_value = 0;
                int axis_value = event.caxis.value;

                switch (event.caxis.axis)
                {
                    /* left/right */
                    case SDL_CONTROLLER_AXIS_LEFTX:
                        direction_type = joy_axis_leftx->string;
                        threshold = joy_axis_leftx_threshold->value;
                        break;

                    /* top/bottom */
                    case SDL_CONTROLLER_AXIS_LEFTY:
                        direction_type = joy_axis_lefty->string;
                        threshold = joy_axis_lefty_threshold->value;
                        break;

                    /* second left/right */
                    case SDL_CONTROLLER_AXIS_RIGHTX:
                        direction_type = joy_axis_rightx->string;
                        threshold = joy_axis_rightx_threshold->value;
                        break;

                    /* second top/bottom */
                    case SDL_CONTROLLER_AXIS_RIGHTY:
                        direction_type = joy_axis_righty->string;
                        threshold = joy_axis_righty_threshold->value;
                        break;

                    case SDL_CONTROLLER_AXIS_TRIGGERLEFT:
                        direction_type = joy_axis_triggerleft->string;
                        threshold = joy_axis_triggerleft_threshold->value;
                        break;

                    case SDL_CONTROLLER_AXIS_TRIGGERRIGHT:
                        direction_type = joy_axis_triggerright->string;
                        threshold = joy_axis_triggerright_threshold->value;
                        break;

                    default:
                        direction_type = "none";
                }

                if (threshold > 0.9)
                {
                    threshold = 0.9;
                }

                if (axis_value < 0 && (axis_value > (32768 * threshold)))
                {
                    axis_value = 0;
                }
                else if (axis_value > 0 && (axis_value < (32768 * threshold)))
                {
                    axis_value = 0;
                }

                // Smoothly ramp from dead zone to maximum value (from ioquake)
                // https://github.com/ioquake/ioq3/blob/master/code/sdl/sdl_input.c
                fix_value = ((float) abs(axis_value) / 32767.0f - threshold) / (1.0f - threshold);

                if (fix_value < 0.0f)
                {
                    fix_value = 0.0f;
                }

                axis_value = (int) (32767 * ((axis_value < 0) ? -fix_value : fix_value));

                if (cls.key_dest == key_game && (int) cl_paused->value == 0)
                {
                    if (strcmp(direction_type, "sidemove") == 0)
                    {
                        joystick_sidemove = axis_value * joy_sidesensitivity->value;

                        // We need to be twice faster because with joystic we run...
                        joystick_sidemove *= cl_sidespeed->value * 2.0f;
                    }
                    else if (strcmp(direction_type, "forwardmove") == 0)
                    {
                        joystick_forwardmove = axis_value * joy_forwardsensitivity->value;

                        // We need to be twice faster because with joystic we run...
                        joystick_forwardmove *= cl_forwardspeed->value * 2.0f;
                    }
                    else if (strcmp(direction_type, "yaw") == 0)
                    {
                        joystick_yaw = axis_value * joy_yawsensitivity->value;
                        joystick_yaw *= cl_yawspeed->value;
                    }
                    else if (strcmp(direction_type, "pitch") == 0)
                    {
                        joystick_pitch = axis_value * joy_pitchsensitivity->value;
                        joystick_pitch *= cl_pitchspeed->value;
                    }
                    else if (strcmp(direction_type, "updown") == 0)
                    {
                        joystick_up = axis_value * joy_upsensitivity->value;
                        joystick_up *= cl_upspeed->value;
                    }
                }

                if (strcmp(direction_type, "triggerleft") == 0)
                {
                    qboolean new_left_trigger = abs(axis_value) > (32767 / 4);

                    if (new_left_trigger != left_trigger)
                    {
                        left_trigger = new_left_trigger;
                        Key_Event(K_TRIG_LEFT, left_trigger, true);
                    }
                }
                else if (strcmp(direction_type, "triggerright") == 0)
                {
                    qboolean new_right_trigger = abs(axis_value) > (32767 / 4);

                    if (new_right_trigger != right_trigger)
                    {
                        right_trigger = new_right_trigger;
                        Key_Event(K_TRIG_RIGHT, right_trigger, true);
                    }
                }

                break;
            }

            // Joystick can have more buttons than on general game controller
            // so try to map not free buttons
            case SDL_JOYBUTTONUP:
            case SDL_JOYBUTTONDOWN:
            {
                qboolean down = (event.type == SDL_JOYBUTTONDOWN);

                // Ignore back button, we don't need event for such button
                if (back_button_id == event.jbutton.button)
                {
                    return;
                }

                if (event.jbutton.button <= (K_JOY32 - K_JOY1))
                {
                    Key_Event(event.jbutton.button + K_JOY1, down, true);
                }

                break;
            }

            case SDL_JOYHATMOTION:
            {
                if (last_hat != event.jhat.value)
                {
                    char diff = last_hat ^event.jhat.value;
                    int i;

                    for (i = 0; i < 4; i++)
                    {
                        if (diff & (1 << i))
                        {
                            // check that we have button up for some bit
                            if (last_hat & (1 << i))
                            {
                                Key_Event(i + K_HAT_UP, false, true);
                            }

                            /* check that we have button down for some bit */
                            if (event.jhat.value & (1 << i))
                            {
                                Key_Event(i + K_HAT_UP, true, true);
                            }
                        }
                    }

                    last_hat = event.jhat.value;
                }

                break;
            }
#endif // !USE_IOS_GAMECONTROLLER

            case SDL_QUIT:
                Com_Quit();
                break;
        }
    }

    /* Grab and ungrab the mouse if the console or the menu is opened */
    if (in_grab->value == 3)
    {
        want_grab = windowed_mouse->value;
    }
    else
    {
        want_grab = (vid_fullscreen->value || in_grab->value == 1 ||
            (in_grab->value == 2 && windowed_mouse->value));
    }

    // calling GLimp_GrabInput() each frame is a bit ugly but simple and should work.
    // The called SDL functions return after a cheap check, if there's nothing to do.
    GLimp_GrabInput(want_grab);

    // We need to save the frame time so other subsystems
    // know the exact time of the last input events.
    sys_frame_time = Sys_Milliseconds();
}

/*
 * Removes all pending events from SDLs queue.
 */
void
In_FlushQueue(void)
{
    SDL_FlushEvents(SDL_FIRSTEVENT, SDL_LASTEVENT);
    Key_MarkAllUp();
}

/*
 * Move handling
 */
void
IN_Move(usercmd_t *cmd)
{
    static int old_mouse_x;
    static int old_mouse_y;

    if (m_filter->value)
    {
        if ((mouse_x > 1) || (mouse_x < -1))
        {
            mouse_x = (mouse_x + old_mouse_x) * 0.5;
        }

        if ((mouse_y > 1) || (mouse_y < -1))
        {
            mouse_y = (mouse_y + old_mouse_y) * 0.5;
        }
    }

    old_mouse_x = mouse_x;
    old_mouse_y = mouse_y;

    if (mouse_x || mouse_y)
    {
        if (!exponential_speedup->value)
        {
            mouse_x *= sensitivity->value;
            mouse_y *= sensitivity->value;
        }
        else
        {
            if ((mouse_x > MOUSE_MIN) || (mouse_y > MOUSE_MIN) ||
                (mouse_x < -MOUSE_MIN) || (mouse_y < -MOUSE_MIN))
            {
                mouse_x = (mouse_x * mouse_x * mouse_x) / 4;
                mouse_y = (mouse_y * mouse_y * mouse_y) / 4;

                if (mouse_x > MOUSE_MAX)
                {
                    mouse_x = MOUSE_MAX;
                }
                else if (mouse_x < -MOUSE_MAX)
                {
                    mouse_x = -MOUSE_MAX;
                }

                if (mouse_y > MOUSE_MAX)
                {
                    mouse_y = MOUSE_MAX;
                }
                else if (mouse_y < -MOUSE_MAX)
                {
                    mouse_y = -MOUSE_MAX;
                }
            }
        }

        // add mouse X/Y movement to cmd
        if ((in_strafe.state & 1) || (lookstrafe->value && mlooking))
        {
            cmd->sidemove += m_side->value * mouse_x;
        }
        else
        {
            cl.viewangles[YAW] -= m_yaw->value * mouse_x;
        }

        if ((mlooking || freelook->value) && !(in_strafe.state & 1))
        {
            cl.viewangles[PITCH] += m_pitch->value * mouse_y;
        }
        else
        {
            cmd->forwardmove -= m_forward->value * mouse_y;
        }

        mouse_x = mouse_y = 0;
    }

    // To make the the viewangles changes independent of framerate we need to scale
    // with frametime (assuming the configured values are for 60hz)
    //
    // 1/32768 is to normalize the input values from SDL (they're between -32768 and
    // 32768 and we want -1 to 1) for movement this is not needed, as those are
    // absolute values independent of framerate
    float joyViewFactor = (1.0f/32768.0f) * (cls.rframetime/0.01666f);

#ifdef USE_IOS_GAMECONTROLLER
    // For iOS GameController, our values are already normalized (-1 to 1)
    // So we need different scaling
    if (joystick_yaw)
    {
        cl.viewangles[YAW] -= (m_yaw->value * joystick_yaw * joy_yawsensitivity->value) * (cls.rframetime/0.01666f) * 175.0f;
    }

    if(joystick_pitch)
    {
        // Note the negative sign for inverted Y-axis (natural aiming)
        cl.viewangles[PITCH] -= (m_pitch->value * joystick_pitch * joy_pitchsensitivity->value) * (cls.rframetime/0.01666f) * 175.0f;
    }

    if (joystick_forwardmove)
    {
        cmd->forwardmove -= (m_forward->value * joystick_forwardmove * joy_forwardsensitivity->value) * 200;
    }

    if (joystick_sidemove)
    {
        cmd->sidemove += (m_side->value * joystick_sidemove * joy_sidesensitivity->value) * 200;
    }
#else
    // Original SDL joystick code
    if (joystick_yaw)
    {
        cl.viewangles[YAW] -= (m_yaw->value * joystick_yaw) * joyViewFactor;
    }

    if(joystick_pitch)
    {
        cl.viewangles[PITCH] += (m_pitch->value * joystick_pitch) * joyViewFactor;
    }

    if (joystick_forwardmove)
    {
        cmd->forwardmove -= (m_forward->value * joystick_forwardmove) / 32768;
    }

    if (joystick_sidemove)
    {
        cmd->sidemove += (m_side->value * joystick_sidemove) / 32768;
    }
#endif

    if (joystick_up)
    {
        cmd->upmove -= (m_up->value * joystick_up) / 32768;
    }
}

/* ------------------------------------------------------------------ */

/*
 * Look down
 */
static void
IN_MLookDown(void)
{
    mlooking = true;
}

/*
 * Look up
 */
static void
IN_MLookUp(void)
{
    mlooking = false;
    IN_CenterView();
}

/* ------------------------------------------------------------------ */

static void IN_Haptic_Shutdown(void);

/*
 * Init haptic effects
 */
static int
IN_Haptic_Effect_Init(int effect_x, int effect_y, int effect_z, int period, int magnitude, int length, int attack, int fade)
{
    /*
     * Direction:
     * North - 0
     * East - 9000
     * South - 18000
     * West - 27000
     */
    static SDL_HapticEffect haptic_effect;

    SDL_memset(&haptic_effect, 0, sizeof(SDL_HapticEffect)); // 0 is safe default

    haptic_effect.type = SDL_HAPTIC_SINE;
    haptic_effect.periodic.direction.type = SDL_HAPTIC_CARTESIAN; // Cartesian/3d coordinates
    haptic_effect.periodic.direction.dir[0] = effect_x;
    haptic_effect.periodic.direction.dir[1] = effect_y;
    haptic_effect.periodic.direction.dir[2] = effect_z;
    haptic_effect.periodic.period = period;
    haptic_effect.periodic.magnitude = magnitude;
    haptic_effect.periodic.length = length;
    haptic_effect.periodic.attack_length = attack;
    haptic_effect.periodic.fade_length = fade;

    int effect_id = SDL_HapticNewEffect(joystick_haptic, &haptic_effect);

    if (effect_id < 0)
    {
        Com_Printf ("SDL_HapticNewEffect failed: %s\n", SDL_GetError());
        Com_Printf ("Please try to rerun game. Effects will be disabled for now.\n");

        IN_Haptic_Shutdown();
    }

    return effect_id;
}

static int
IN_Haptic_Effects_To_Id(int haptic_effect, int effect_volume, int effect_x, int effect_y, int effect_z)
{
    if ((SDL_HapticQuery(joystick_haptic) & SDL_HAPTIC_SINE)==0)
    {
        return -1;
    }

    int hapric_volume = joy_haptic_magnitude->value * effect_volume * 16; // * 128 = 32767 max strength;

    if (hapric_volume > 255)
    {
        hapric_volume = 255;
    }
    else if (hapric_volume < 0)
    {
        hapric_volume = 0;
    }

    switch(haptic_effect) {
    case HAPTIC_EFFECT_MENY:
    case HAPTIC_EFFECT_TRAPCOCK:
    case HAPTIC_EFFECT_STEP:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 48,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_PAIN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 196,
                                     300/* 0.3 seconds long */, 200/* Takes 0.2 second to get max strength */,
                                     200/* Takes 0.2 second to fade away */);
    case HAPTIC_EFFECT_BLASTER:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_HYPER_BLASTER:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_ETFRIFLE:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_TRACKER:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_MACHINEGUN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 800/* 800 ms*/, hapric_volume * 88,
                                     600/* 0.6 seconds long */, 200/* Takes 0.2 second to get max strength */,
                                     400/* Takes 0.4 second to fade away */);
    case HAPTIC_EFFECT_SHOTGUN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 100,
                                     500/* 0.5 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     200/* Takes 0.2 second to fade away */);
    case HAPTIC_EFFECT_SHOTGUN2:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 96,
                                     500/* 0.5 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_SSHOTGUN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 96,
                                     500/* 0.5 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_RAILGUN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 64,
                                     400/* 0.4 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_ROCKETGUN:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 700/* 700 ms*/, hapric_volume * 128,
                                     400/* 0.4 seconds long */, 300/* Takes 0.3 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_GRENADE:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_BFG:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 800/* 800 ms*/, hapric_volume * 100,
                                     600/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_PALANX:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    case HAPTIC_EFFECT_IONRIPPER:
        return IN_Haptic_Effect_Init(effect_x, effect_y, effect_z, 500/* 500 ms*/, hapric_volume * 64,
                                     200/* 0.2 seconds long */, 100/* Takes 0.1 second to get max strength */,
                                     100/* Takes 0.1 second to fade away */);
    default:
        return -1;
    }
}

static void
IN_Haptic_Effects_Info(void)
{
    show_haptic = true;

    Com_Printf ("Joystic/Mouse haptic:\n");
    Com_Printf (" * %d effects\n", SDL_HapticNumEffects(joystick_haptic));
    Com_Printf (" * %d effects in same time\n", SDL_HapticNumEffectsPlaying(joystick_haptic));
    Com_Printf (" * %d haptic axis\n", SDL_HapticNumAxes(joystick_haptic));
}

static void
IN_Haptic_Effects_Init(void)
{
    last_haptic_efffect_size = SDL_HapticNumEffectsPlaying(joystick_haptic);

    if (last_haptic_efffect_size > HAPTIC_EFFECT_LAST)
    {
        last_haptic_efffect_size = HAPTIC_EFFECT_LAST;
    }

    for (int i=0; i<HAPTIC_EFFECT_LAST; i++)
    {
        last_haptic_efffect[i].effect_type = HAPTIC_EFFECT_UNKNOWN;
        last_haptic_efffect[i].effect_id = -1;
        last_haptic_efffect[i].effect_volume = 0;
        last_haptic_efffect[i].effect_x = 0;
        last_haptic_efffect[i].effect_y = 0;
        last_haptic_efffect[i].effect_z = 0;
    }
}

/*
 * Shuts the backend down
 */
static void
IN_Haptic_Effect_Shutdown(int * effect_id)
{
    if (!effect_id)
    {
        return;
    }

    if (*effect_id >= 0)
    {
        SDL_HapticDestroyEffect(joystick_haptic, *effect_id);
    }

    *effect_id = -1;
}

static void
IN_Haptic_Effects_Shutdown(void)
{
    for (int i=0; i<HAPTIC_EFFECT_LAST; i++)
    {
        last_haptic_efffect[i].effect_type = HAPTIC_EFFECT_UNKNOWN;
        last_haptic_efffect[i].effect_volume = 0;
        last_haptic_efffect[i].effect_x = 0;
        last_haptic_efffect[i].effect_y = 0;
        last_haptic_efffect[i].effect_z = 0;

        IN_Haptic_Effect_Shutdown(&last_haptic_efffect[i].effect_id);
    }
}

/*
 * Haptic Feedback:
 *    effect_volume=0..16
 *    effect{x,y,z} - effect direction
 *    name - sound file name
 */
void
Haptic_Feedback(char *name, int effect_volume, int effect_x, int effect_y, int effect_z)
{
#ifdef USE_IOS_GAMECONTROLLER
    // Use native iOS haptic feedback
    if (iOS_IsControllerConnected() && joy_haptic_strength->value > 0)
    {
        float intensity = 0.5f; // Default intensity
        int duration = 100; // Default duration in ms
        
        // Map sound names to haptic intensities
        if (strstr(name, "weapons/blastf1a") || strstr(name, "weapons/hyprbf1a"))
        {
            intensity = 0.3f;
            duration = 50;
        }
        else if (strstr(name, "weapons/machgf"))
        {
            intensity = 0.4f;
            duration = 60;
        }
        else if (strstr(name, "weapons/shotgf1b") || strstr(name, "weapons/sshotf1b"))
        {
            intensity = 0.6f;
            duration = 100;
        }
        else if (strstr(name, "weapons/railgf1a"))
        {
            intensity = 0.5f;
            duration = 80;
        }
        else if (strstr(name, "weapons/rocklf1a") || strstr(name, "weapons/rocklx1a"))
        {
            intensity = 0.8f;
            duration = 150;
        }
        else if (strstr(name, "weapons/grenlf1a") || strstr(name, "weapons/grenlx1a"))
        {
            intensity = 0.6f;
            duration = 100;
        }
        else if (strstr(name, "weapons/bfg__f1y"))
        {
            intensity = 1.0f;
            duration = 200;
        }
        else if (strstr(name, "player/male/pain") || strstr(name, "player/female/pain"))
        {
            intensity = 0.7f;
            duration = 150;
        }
        else if (strstr(name, "player/step") || strstr(name, "player/land"))
        {
            intensity = 0.2f;
            duration = 50;
        }
        
        IN_HapticEvent(intensity, duration);
        return;
    }
#endif
    
    int effect_type = HAPTIC_EFFECT_UNKNOWN;
    
    if (joy_haptic_magnitude->value <= 0)
    {
        return;
    }
    
    if (effect_volume <= 0)
    {
        return;
    }
    
    if (!joystick_haptic)
    {
        return;
    }
    
    if (last_haptic_volume != (int)(joy_haptic_magnitude->value * 255))
    {
        IN_Haptic_Effects_Shutdown();
        IN_Haptic_Effects_Init();
    }
    
    last_haptic_volume = joy_haptic_magnitude->value * 255;
    
    if (strstr(name, "misc/menu"))
    {
        effect_type = HAPTIC_EFFECT_MENY;
    }
    else if (strstr(name, "weapons/blastf1a"))
    {
        effect_type = HAPTIC_EFFECT_BLASTER;
    }
    else if (strstr(name, "weapons/hyprbf1a"))
    {
        effect_type = HAPTIC_EFFECT_HYPER_BLASTER;
    }
    else if (strstr(name, "weapons/machgf"))
    {
        effect_type = HAPTIC_EFFECT_MACHINEGUN;
    }
    else if (strstr(name, "weapons/shotgf1b"))
    {
        effect_type = HAPTIC_EFFECT_SHOTGUN;
    }
    else if (strstr(name, "weapons/sshotf1b"))
    {
        effect_type = HAPTIC_EFFECT_SSHOTGUN;
    }
    else if (strstr(name, "weapons/railgf1a"))
    {
        effect_type = HAPTIC_EFFECT_RAILGUN;
    }
    else if (strstr(name, "weapons/rocklf1a") ||
             strstr(name, "weapons/rocklx1a"))
    {
        effect_type = HAPTIC_EFFECT_ROCKETGUN;
    }
    else if (strstr(name, "weapons/grenlf1a") ||
             strstr(name, "weapons/grenlx1a") ||
             strstr(name, "weapons/hgrent1a"))
    {
        effect_type = HAPTIC_EFFECT_GRENADE;
    }
    else if (strstr(name, "weapons/bfg__f1y"))
    {
        effect_type = HAPTIC_EFFECT_BFG;
    }
    else if (strstr(name, "weapons/plasshot"))
    {
        effect_type = HAPTIC_EFFECT_PALANX;
    }
    else if (strstr(name, "weapons/rippfire"))
    {
        effect_type = HAPTIC_EFFECT_IONRIPPER;
    }
    else if (strstr(name, "weapons/nail1"))
   {
       effect_type = HAPTIC_EFFECT_ETFRIFLE;
   }
   else if (strstr(name, "weapons/shotg2"))
   {
       effect_type = HAPTIC_EFFECT_SHOTGUN2;
   }
   else if (strstr(name, "weapons/disint2"))
   {
       effect_type = HAPTIC_EFFECT_TRACKER;
   }
   else if (strstr(name, "player/male/pain") ||
       strstr(name, "player/female/pain") ||
       strstr(name, "players/male/pain") ||
       strstr(name, "players/female/pain"))
   {
       effect_type = HAPTIC_EFFECT_PAIN;
   }
   else if (strstr(name, "player/step") ||
       strstr(name, "player/land"))
   {
       effect_type = HAPTIC_EFFECT_STEP;
   }
   else if (strstr(name, "weapons/trapcock"))
   {
       effect_type = HAPTIC_EFFECT_TRAPCOCK;
   }

   if (effect_type != HAPTIC_EFFECT_UNKNOWN)
   {
       // check last effect for reuse
       if (last_haptic_efffect[last_haptic_efffect_pos].effect_type != effect_type ||
           last_haptic_efffect[last_haptic_efffect_pos].effect_volume != effect_volume ||
           last_haptic_efffect[last_haptic_efffect_pos].effect_x != effect_x ||
           last_haptic_efffect[last_haptic_efffect_pos].effect_y != effect_y ||
           last_haptic_efffect[last_haptic_efffect_pos].effect_z != effect_z)
       {
           // FIFO for effects
           last_haptic_efffect_pos = (last_haptic_efffect_pos+1) % last_haptic_efffect_size;
           IN_Haptic_Effect_Shutdown(&last_haptic_efffect[last_haptic_efffect_pos].effect_id);
           last_haptic_efffect[last_haptic_efffect_pos].effect_volume = effect_volume;
           last_haptic_efffect[last_haptic_efffect_pos].effect_type = effect_type;
           last_haptic_efffect[last_haptic_efffect_pos].effect_x = effect_x;
           last_haptic_efffect[last_haptic_efffect_pos].effect_y = effect_y;
           last_haptic_efffect[last_haptic_efffect_pos].effect_z = effect_z;
           last_haptic_efffect[last_haptic_efffect_pos].effect_id = IN_Haptic_Effects_To_Id(
               effect_type, effect_volume, effect_x, effect_y, effect_z);
       }

       SDL_HapticRunEffect(joystick_haptic, last_haptic_efffect[last_haptic_efffect_pos].effect_id, 1);
   }
}

/*
* Initializes the backend
*/
void
IN_Init(void)
{
   Com_Printf("------- input initialization -------\n");

   mouse_x = mouse_y = 0;
   joystick_yaw = joystick_pitch = joystick_forwardmove = joystick_sidemove = 0;

   exponential_speedup = Cvar_Get("exponential_speedup", "0", CVAR_ARCHIVE);
   freelook = Cvar_Get("freelook", "1", 0);
   in_grab = Cvar_Get("in_grab", "2", CVAR_ARCHIVE);
   lookstrafe = Cvar_Get("lookstrafe", "0", 0);
   m_filter = Cvar_Get("m_filter", "0", CVAR_ARCHIVE);
   m_up = Cvar_Get("m_up", "1", 0);
   m_forward = Cvar_Get("m_forward", "1", 0);
   m_pitch = Cvar_Get("m_pitch", "0.022", 0);
   m_side = Cvar_Get("m_side", "0.8", 0);
   m_yaw = Cvar_Get("m_yaw", "0.022", 0);
   sensitivity = Cvar_Get("sensitivity", "3", 0);

   joy_haptic_magnitude = Cvar_Get("joy_haptic_magnitude", "0.0", CVAR_ARCHIVE);

    joy_yawsensitivity = Cvar_Get("joy_yawsensitivity", "10.0", CVAR_ARCHIVE);
    joy_pitchsensitivity = Cvar_Get("joy_pitchsensitivity", "10.0", CVAR_ARCHIVE);
    joy_forwardsensitivity = Cvar_Get("joy_forwardsensitivity", "1.0", CVAR_ARCHIVE);
    joy_sidesensitivity = Cvar_Get("joy_sidesensitivity", "1.0", CVAR_ARCHIVE);

    joy_leftStickSensitivity = Cvar_Get("joy_leftStickSensitivity", "1.0", CVAR_ARCHIVE);
    joy_rightStickSensitivity = Cvar_Get("joy_rightStickSensitivity", "10.0", CVAR_ARCHIVE);

   joy_axis_leftx = Cvar_Get("joy_axis_leftx", "sidemove", CVAR_ARCHIVE);
   joy_axis_lefty = Cvar_Get("joy_axis_lefty", "forwardmove", CVAR_ARCHIVE);
   joy_axis_rightx = Cvar_Get("joy_axis_rightx", "yaw", CVAR_ARCHIVE);
   joy_axis_righty = Cvar_Get("joy_axis_righty", "pitch", CVAR_ARCHIVE);
   joy_axis_triggerleft = Cvar_Get("joy_axis_triggerleft", "triggerleft", CVAR_ARCHIVE);
   joy_axis_triggerright = Cvar_Get("joy_axis_triggerright", "triggerright", CVAR_ARCHIVE);

   joy_axis_leftx_threshold = Cvar_Get("joy_axis_leftx_threshold", "0.15", CVAR_ARCHIVE);
   joy_axis_lefty_threshold = Cvar_Get("joy_axis_lefty_threshold", "0.15", CVAR_ARCHIVE);
   joy_axis_rightx_threshold = Cvar_Get("joy_axis_rightx_threshold", "0.15", CVAR_ARCHIVE);
   joy_axis_righty_threshold = Cvar_Get("joy_axis_righty_threshold", "0.15", CVAR_ARCHIVE);
   joy_axis_triggerleft_threshold = Cvar_Get("joy_axis_triggerleft_threshold", "0.15", CVAR_ARCHIVE);
   joy_axis_triggerright_threshold = Cvar_Get("joy_axis_triggerright_threshold", "0.15", CVAR_ARCHIVE);

    // In IN_Init(), update the default bindings:
    #ifdef USE_IOS_GAMECONTROLLER
        // Initialize iOS GameController cvars
        joy_haptic_strength = Cvar_Get("joy_haptic_strength", "1.0", CVAR_ARCHIVE);
        joy_deadzone = Cvar_Get("joy_deadzone", "0.15", CVAR_ARCHIVE);
        joy_leftStickSensitivity = Cvar_Get("joy_leftStickSensitivity", "1.0", CVAR_ARCHIVE);
        joy_rightStickSensitivity = Cvar_Get("joy_rightStickSensitivity", "1.0", CVAR_ARCHIVE);
        
        // Button binding cvars with your requested defaults
        joy_buttonA_bind = Cvar_Get("joy_buttonA_bind", "invuse", CVAR_ARCHIVE);      // Face Left - Show Inventory
        joy_buttonB_bind = Cvar_Get("joy_buttonB_bind", "+moveup", CVAR_ARCHIVE);   // Face Bottom - Jump
        joy_buttonX_bind = Cvar_Get("joy_buttonX_bind", "+movedown", CVAR_ARCHIVE);     // Face Right - Crouch
        joy_buttonY_bind = Cvar_Get("joy_buttonY_bind", "wave 0", CVAR_ARCHIVE);      // Face Top - Taunt
        joy_leftShoulder_bind = Cvar_Get("joy_leftShoulder_bind", "invprev", CVAR_ARCHIVE);    // Prev Weapon
        joy_rightShoulder_bind = Cvar_Get("joy_rightShoulder_bind", "invnext", CVAR_ARCHIVE);  // Next Weapon
        joy_leftTrigger_bind = Cvar_Get("joy_leftTrigger_bind", "", CVAR_ARCHIVE);    // Unbound for zoom alias
        joy_rightTrigger_bind = Cvar_Get("joy_rightTrigger_bind", "+attack", CVAR_ARCHIVE);    // Attack
        joy_dpadUp_bind = Cvar_Get("joy_dpadUp_bind", "invuse", CVAR_ARCHIVE);        // Use Item
        joy_dpadDown_bind = Cvar_Get("joy_dpadDown_bind", "invdrop", CVAR_ARCHIVE);   // Drop Item
        joy_dpadLeft_bind = Cvar_Get("joy_dpadLeft_bind", "invprev", CVAR_ARCHIVE);   // Prev Item
        joy_dpadRight_bind = Cvar_Get("joy_dpadRight_bind", "invnext", CVAR_ARCHIVE); // Next Item
        joy_buttonMenu_bind = Cvar_Get("joy_buttonMenu_bind", "togglemenu", CVAR_ARCHIVE);     // Menu
        joy_buttonOptions_bind = Cvar_Get("joy_buttonOptions_bind", "score", CVAR_ARCHIVE);    // Show Scores
        
        // Add stick click bindings
        joy_leftStickClick_bind = Cvar_Get("joy_leftStickClick_bind", "+movedown", CVAR_ARCHIVE);   // Crouch
        joy_rightStickClick_bind = Cvar_Get("joy_rightStickClick_bind", "centerview", CVAR_ARCHIVE); // Center View
    
        // Set up default bindings for controller buttons with correct Xbox layout
        Cbuf_AddText("bind AUX1 \"cmd help\"\n");      // X button (Face Left) - Help/Mission
        Cbuf_AddText("bind AUX2 \"wave 0\"\n");        // Y button (Face Top) - Taunt
        Cbuf_AddText("bind AUX3 \"invprev\"\n");       // Left Shoulder - Prev Weapon
        Cbuf_AddText("bind AUX4 \"invnext\"\n");       // Right Shoulder - Next Weapon
        Cbuf_AddText("bind AUX5 \"invuse\"\n");        // DPad Up - Use Item
        Cbuf_AddText("bind AUX6 \"invdrop\"\n");       // DPad Down - Drop Item
        Cbuf_AddText("bind AUX7 \"invprev\"\n");       // DPad Left - Prev Item
        Cbuf_AddText("bind AUX8 \"invnext\"\n");       // DPad Right - Next Item
        Cbuf_AddText("bind AUX10 \"centerview\"\n");   // Right Stick Click - Center View
        Cbuf_AddText("bind AUX11 \"+movedown\"\n");      // B button - Crouch
        Cbuf_AddText("bind AUX12 \"+movedown\"\n");      // Left Stick Click - Crouch
        
        // IMPORTANT: We're using K_SPACE directly for A button (Jump) and Left Trigger
        // We're using K_AUX11/K_AUX12 for B and Left Stick (Crouch)
        
        // These are already bound by default in Quake 2:
        // A button = SPACE = jump (+movedown)
        // B button = CTRL = crouch (+moveup)
        // ESCAPE = menu (togglemenu)
        // TAB = scores
        // MOUSE1 = fire (+attack) - Right Trigger
        
        Com_Printf("iOS GameController default bindings set\n");
        
        // Add console commands for testing
        Cmd_AddCommand("testcontroller", IN_TestController_f);
        Cmd_AddCommand("debugcontroller", IN_DebugController_f);
        Cmd_AddCommand("controllerstatus", IN_ControllerStatus_f);
        Com_DPrintf("Registered controller commands\n");
    #endif

   vid_fullscreen = Cvar_Get("vid_fullscreen", "0", CVAR_ARCHIVE);
   windowed_mouse = Cvar_Get("windowed_mouse", "1", CVAR_USERINFO | CVAR_ARCHIVE);

   Cmd_AddCommand("+mlook", IN_MLookDown);
   Cmd_AddCommand("-mlook", IN_MLookUp);

#ifndef IOS
   SDL_StartTextInput();
#else
   SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
   SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
   SDL_StartTextInput();  // Enable typing in console!
   
#ifdef USE_IOS_GAMECONTROLLER
   // Disable SDL controller hints and subsystems on iOS
   SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "0");
   SDL_SetHint(SDL_HINT_GAMECONTROLLERCONFIG, "");
   SDL_SetHint("SDL_JOYSTICK_DISABLE", "1");
   SDL_SetHint("SDL_GAMECONTROLLER_DISABLE", "1");
   Com_Printf("iOS: Disabled SDL controller hints and subsystems\n");
   
   // Initialize iOS GameController FIRST, before any SDL initialization
   Com_Printf("Initializing iOS GameController (bypassing SDL)...\n");
   iOS_InitGameController();
   Com_Printf("iOS GameController support initialized\n");
#endif
   
#if !TARGET_OS_TV
   if (motionManager == nil) {
       motionManager = [[CMMotionManager alloc] init];
   }
   motionManager.deviceMotionUpdateInterval = 0.1;
   [motionManager startDeviceMotionUpdates];
#endif
#endif
   
   Cbuf_AddText(va("bind MWHEELDOWN \"weapprev\"\n"));
   Cbuf_AddText(va("bind MWHEELUP \"weapnext\"\n"));

#ifndef USE_IOS_GAMECONTROLLER  // Skip SDL joystick init when using iOS GameController
   /* Joystick init */
   if (!SDL_WasInit(SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC))
   {
       if (SDL_Init(SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC) == -1)
       {
           Com_Printf ("Couldn't init SDL joystick: %s.\n", SDL_GetError ());
       }
       else
       {
           Com_Printf ("%i joysticks were found.\n", SDL_NumJoysticks());

           if (SDL_NumJoysticks() > 0) {
               for (int i = 0; i < SDL_NumJoysticks(); i++) {
                   joystick = SDL_JoystickOpen(i);

                   Com_Printf ("The name of the joystick is '%s'\n", SDL_JoystickName(joystick));
                   Com_Printf ("Number of Axes: %d\n", SDL_JoystickNumAxes(joystick));
                   Com_Printf ("Number of Buttons: %d\n", SDL_JoystickNumButtons(joystick));
                   Com_Printf ("Number of Balls: %d\n", SDL_JoystickNumBalls(joystick));
                   Com_Printf ("Number of Hats: %d\n", SDL_JoystickNumHats(joystick));

                   joystick_haptic = SDL_HapticOpenFromJoystick(joystick);

                   if (joystick_haptic == NULL)
                   {
                       Com_Printf("Most likely joystick isn't haptic\n");
                   }
                   else
                   {
                       IN_Haptic_Effects_Info();
                   }

                   if(SDL_IsGameController(i))
                   {
                       SDL_GameControllerButtonBind backBind;
                       controller = SDL_GameControllerOpen(i);

                       Com_Printf ("Controller settings: %s\n", SDL_GameControllerMapping(controller));
                       Com_Printf ("Controller axis: \n");
                       Com_Printf (" * leftx = %s\n", joy_axis_leftx->string);
                       Com_Printf (" * lefty = %s\n", joy_axis_lefty->string);
                       Com_Printf (" * rightx = %s\n", joy_axis_rightx->string);
                       Com_Printf (" * righty = %s\n", joy_axis_righty->string);
                       Com_Printf (" * triggerleft = %s\n", joy_axis_triggerleft->string);
                       Com_Printf (" * triggerright = %s\n", joy_axis_triggerright->string);

                       Com_Printf ("Controller thresholds: \n");
                       Com_Printf (" * leftx = %f\n", joy_axis_leftx_threshold->value);
                       Com_Printf (" * lefty = %f\n", joy_axis_lefty_threshold->value);
                       Com_Printf (" * rightx = %f\n", joy_axis_rightx_threshold->value);
                       Com_Printf (" * righty = %f\n", joy_axis_righty_threshold->value);
                       Com_Printf (" * triggerleft = %f\n", joy_axis_triggerleft_threshold->value);
                       Com_Printf (" * triggerright = %f\n", joy_axis_triggerright_threshold->value);

                       backBind = SDL_GameControllerGetBindForButton(controller, SDL_CONTROLLER_BUTTON_BACK);

                       if (backBind.bindType == SDL_CONTROLLER_BINDTYPE_BUTTON)
                       {
                           back_button_id = backBind.value.button;
                           Com_Printf ("\nBack button JOY%d will be unbindable.\n", back_button_id+1);
                       }

                       break;
                   }
                   else
                   {
                       char joystick_guid[256] = {0};

                       SDL_JoystickGUID guid;
                       guid = SDL_JoystickGetDeviceGUID(i);

                       SDL_JoystickGetGUIDString(guid, joystick_guid, 255);

                       Com_Printf ("To use joystick as game controller please set SDL_GAMECONTROLLERCONFIG:\n");
                       Com_Printf ("e.g.: SDL_GAMECONTROLLERCONFIG='%s,%s,leftx:a0,lefty:a1,rightx:a2,righty:a3,back:b1,...\n", joystick_guid, SDL_JoystickName(joystick));
                   }
               }
           }
           else
           {
               joystick_haptic = SDL_HapticOpenFromMouse();

               if (joystick_haptic == NULL)
               {
                   Com_Printf("Most likely mouse isn't haptic\n");
               }
               else
               {
                   IN_Haptic_Effects_Info();
               }
           }
       }
   }
#endif // !USE_IOS_GAMECONTROLLER

   Com_Printf("------------------------------------\n\n");
}

/*
* Shuts the backend down
*/
static void
IN_Haptic_Shutdown(void)
{
   if (joystick_haptic)
   {
       IN_Haptic_Effects_Shutdown();

       SDL_HapticClose(joystick_haptic);
       joystick_haptic = NULL;
   }
}

void
IN_Shutdown(void)
{
   Cmd_RemoveCommand("force_centerview");
   Cmd_RemoveCommand("+mlook");
   Cmd_RemoveCommand("-mlook");

#ifdef USE_IOS_GAMECONTROLLER
   Cmd_RemoveCommand("testcontroller");
   Cmd_RemoveCommand("debugcontroller");
#endif

   Com_Printf("Shutting down input.\n");

   IN_Haptic_Shutdown();

   if (controller)
   {
       back_button_id = -1;
       SDL_GameControllerClose(controller);
       controller  = NULL;
   }

   if (joystick)
   {
       SDL_JoystickClose(joystick);
       joystick = NULL;
   }
}

/* ------------------------------------------------------------------ */
