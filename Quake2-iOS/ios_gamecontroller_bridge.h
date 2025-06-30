//
//  ios_gamecontroller_bridge.h
//  Quake2-iOS
//
//  Created by rebelancap on 6/29/25.
//

#ifndef IOS_GAMECONTROLLER_BRIDGE_H
#define IOS_GAMECONTROLLER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the controller system
void iOS_InitGameController(void);

// Check if a controller is connected
int iOS_IsControllerConnected(void);

// Get analog stick values (-1.0 to 1.0)
float iOS_GetLeftStickX(void);
float iOS_GetLeftStickY(void);
float iOS_GetRightStickX(void);
float iOS_GetRightStickY(void);

// Get trigger values (0.0 to 1.0)
float iOS_GetLeftTrigger(void);
float iOS_GetRightTrigger(void);

// Get button states (0 or 1)
int iOS_GetButtonA(void);
int iOS_GetButtonB(void);
int iOS_GetButtonX(void);
int iOS_GetButtonY(void);
int iOS_GetLeftShoulder(void);
int iOS_GetRightShoulder(void);
int iOS_GetDpadUp(void);
int iOS_GetDpadDown(void);
int iOS_GetDpadLeft(void);
int iOS_GetDpadRight(void);
int iOS_GetButtonMenu(void);
int iOS_GetButtonOptions(void);
int iOS_GetLeftStickClick(void);
int iOS_GetRightStickClick(void);

// Haptic feedback
void iOS_TriggerHaptic(float intensity, int durationMs);

// Perform delayed controller check
void iOS_PerformDelayedControllerCheck(void);

// Debug controller state
void iOS_DebugControllerState(void);

#ifdef __cplusplus
}
#endif

#endif
