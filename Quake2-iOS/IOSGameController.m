//
//  IOSGameController.m
//  Quake2-iOS
//
//  Created by rebelancap on 6/29/25.
//

#import "IOSGameController.h"
#import <CoreHaptics/CoreHaptics.h>

@interface IOSGameController ()
@property (nonatomic, strong) GCController *activeController;
@property (nonatomic, strong) id connectObserver;
@property (nonatomic, strong) id disconnectObserver;
@property (nonatomic, strong) CHHapticEngine *hapticEngine API_AVAILABLE(ios(13.0));
@property (nonatomic, strong) NSTimer *controllerCheckTimer;
@end

@implementation IOSGameController

+ (instancetype)sharedController {
    static IOSGameController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[IOSGameController alloc] init];
        // Retain the instance to ensure it persists
        CFRetain((__bridge CFTypeRef)sharedInstance);
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"iOS GameController: Initializing GameController support...");
        
        // IMPORTANT: Set up observers FIRST, before any controller detection
        [self setupControllerObservers];
        
        // Run basic detection test
        [IOSGameController testBasicDetection];
        
        // Delay initial controller detection
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self findController];
            // Hide controls if we found a controller during init
            if (self.activeController) {
                extern void* GetSDLWindow(void);
                extern void HideOnScreenControls(void *sdlWindow);
                void *sdlWindow = GetSDLWindow();
                if (sdlWindow) {
                    HideOnScreenControls(sdlWindow);
                    NSLog(@"iOS GameController: Hiding controls after initial detection");
                }
            }
        });
        
        // Start wireless discovery
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startControllerDiscovery];
        });
        
        // Set up a timer to periodically check for controllers
        // This helps with wired controllers that don't always send notifications
        self.controllerCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                     target:self
                                                                   selector:@selector(checkForControllers)
                                                                   userInfo:nil
                                                                    repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.controllerCheckTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"iOS GameController: Deallocating (this should never happen!)");
    [[NSNotificationCenter defaultCenter] removeObserver:self.connectObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.disconnectObserver];
    [self.controllerCheckTimer invalidate];
    self.controllerCheckTimer = nil;
}

- (void)setupControllerObservers {
    __weak typeof(self) weakSelf = self;
    
    NSLog(@"iOS GameController: Setting up controller observers...");
    
    self.connectObserver = [[NSNotificationCenter defaultCenter]
                            addObserverForName:GCControllerDidConnectNotification
                            object:nil
                            queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
        GCController *controller = note.object;
        NSLog(@"iOS GameController: === CONNECT NOTIFICATION ===");
        NSLog(@"iOS GameController: Controller connected: %@ (ptr: %p)", controller.vendorName, controller);
        
        // If we don't have a controller, use this one
        if (!weakSelf.activeController) {
            weakSelf.activeController = controller;
            [weakSelf setupControllerCallbacks];
            NSLog(@"iOS GameController: Set as active controller");
            // Hide controls when controller connects
            extern void* GetSDLWindow(void);
            extern void HideOnScreenControls(void *sdlWindow);
            void *sdlWindow = GetSDLWindow();
            if (sdlWindow) {
                HideOnScreenControls(sdlWindow);
                NSLog(@"iOS GameController: Hiding on-screen controls");
            }
        } else {
            NSLog(@"iOS GameController: Already have active controller, ignoring");
        }
    }];
    
    self.disconnectObserver = [[NSNotificationCenter defaultCenter]
                               addObserverForName:GCControllerDidDisconnectNotification
                               object:nil
                               queue:[NSOperationQueue mainQueue]
                               usingBlock:^(NSNotification *note) {
        GCController *controller = note.object;
        NSLog(@"iOS GameController: === DISCONNECT NOTIFICATION ===");
        NSLog(@"iOS GameController: Controller disconnected: %@ (ptr: %p)", controller.vendorName, controller);
        
        if (weakSelf.activeController == controller) {
            NSLog(@"iOS GameController: Active controller disconnected, clearing");
            weakSelf.activeController = nil;
            
            // Try to find another controller after a short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf findController];
                // Show controls if no controller found
                if (!weakSelf.activeController) {
                    extern void* GetSDLWindow(void);
                    extern void ShowOnScreenControls(void *sdlWindow);
                    void *sdlWindow = GetSDLWindow();
                    if (sdlWindow) {
                        ShowOnScreenControls(sdlWindow);
                        NSLog(@"iOS GameController: Showing on-screen controls");
                    }
                }
            });
        }
    }];
}

- (void)checkForControllers {
    // This runs every 0.5 seconds to catch controllers that don't send proper notifications
    NSArray *controllers = [GCController controllers];
    
    if (self.activeController) {
        // Check if our controller is still in the array
        BOOL stillConnected = NO;
        for (GCController *controller in controllers) {
            if (controller == self.activeController) {
                stillConnected = YES;
                break;
            }
        }
        
        if (!stillConnected) {
            NSLog(@"iOS GameController: Active controller no longer in array, disconnecting");
            self.activeController = nil;
        }
    }
    
    if (!self.activeController && controllers.count > 0) {
        NSLog(@"iOS GameController: Found controller via periodic check");
        [self findController];
    }
}

- (void)findController {
    NSArray *controllers = [GCController controllers];
    
    NSLog(@"iOS GameController: Scanning for controllers...");
    NSLog(@"iOS GameController: Found %lu controller(s)", (unsigned long)controllers.count);
    
    if (self.activeController) {
        NSLog(@"iOS GameController: Already have an active controller, not changing");
        return;
    }
    
    for (GCController *controller in controllers) {
        NSLog(@"iOS GameController: - %@ (Product: %@)", controller.vendorName, controller.productCategory);
        
        if (@available(iOS 13.0, *)) {
            if (controller.physicalInputProfile) {
                NSLog(@"iOS GameController:   Has physical input profile");
            }
        }
        
        if (controller.extendedGamepad) {
            self.activeController = controller;
            [self setupControllerCallbacks];
            NSLog(@"iOS GameController: Connected to %@ (extended gamepad supported)", controller.vendorName);
            
            // Hide controls when controller is found
            extern void* GetSDLWindow(void);
            extern void HideOnScreenControls(void *sdlWindow);
            void *sdlWindow = GetSDLWindow();
            if (sdlWindow) {
                HideOnScreenControls(sdlWindow);
                NSLog(@"iOS GameController: Hiding on-screen controls");
            }
            
            // Log available inputs
            GCExtendedGamepad *gamepad = controller.extendedGamepad;
            NSLog(@"iOS GameController: Available inputs:");
            NSLog(@"  - D-Pad: %@", gamepad.dpad ? @"YES" : @"NO");
            NSLog(@"  - Buttons (A/B/X/Y): %@", (gamepad.buttonA && gamepad.buttonB) ? @"YES" : @"NO");
            NSLog(@"  - Shoulders: %@", (gamepad.leftShoulder && gamepad.rightShoulder) ? @"YES" : @"NO");
            NSLog(@"  - Triggers: %@", (gamepad.leftTrigger && gamepad.rightTrigger) ? @"YES" : @"NO");
            NSLog(@"  - Thumbsticks: %@", (gamepad.leftThumbstick && gamepad.rightThumbstick) ? @"YES" : @"NO");
            
            break;
        }
    }
    
    if (!self.activeController) {
        NSLog(@"iOS GameController: No compatible controller found");
    }
}

- (void)setupControllerCallbacks {
    if (!self.activeController || !self.activeController.extendedGamepad) {
        return;
    }
    
    // Set up haptic engine for iOS 13+
    if (@available(iOS 13.0, *)) {
        if (self.activeController.haptics) {
            NSError *error = nil;
            self.hapticEngine = [self.activeController.haptics createEngineWithLocality:GCHapticsLocalityDefault];
            if (error) {
                NSLog(@"iOS GameController: Failed to create haptic engine: %@", error);
            } else {
                [self.hapticEngine startAndReturnError:&error];
                if (error) {
                    NSLog(@"iOS GameController: Failed to start haptic engine: %@", error);
                }
            }
        }
    }
}

- (void)startControllerDiscovery {
    NSLog(@"iOS GameController: Starting wireless controller discovery...");
    
    // First check if we already have controllers connected (wired)
    NSArray *controllers = [GCController controllers];
    if (controllers.count > 0) {
        NSLog(@"iOS GameController: Controllers already connected, checking them first");
        [self findController];
    }
    
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{
        // Discovery completed
        NSLog(@"iOS GameController: Wireless discovery completed, found %lu controllers",
              (unsigned long)[GCController controllers].count);
    }];
}

- (void)stopControllerDiscovery {
    [GCController stopWirelessControllerDiscovery];
}

- (BOOL)isControllerConnected {
    // Use our more thorough check
    return [self isControllerActuallyConnected];
}

- (BOOL)isControllerActuallyConnected {
    if (!self.activeController) {
        return NO;
    }
    
    // For wired controllers, the only reliable way to check if they're still connected
    // is to see if we get nil when accessing the gamepad
    @try {
        GCExtendedGamepad *gamepad = self.activeController.extendedGamepad;
        if (!gamepad) {
            NSLog(@"iOS GameController: Controller gamepad is nil, disconnecting");
            self.activeController = nil;
            return NO;
        }
        
        // Try to capture the gamepad state - this should fail if disconnected
        if (@available(iOS 13.0, *)) {
            [gamepad capture];
        }
        
        return YES;
    }
    @catch (NSException *exception) {
        NSLog(@"iOS GameController: Exception checking controller: %@", exception);
        self.activeController = nil;
        return NO;
    }
}

// Analog stick getters
- (float)leftStickX {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.leftThumbstick.xAxis.value;
}

- (float)leftStickY {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.leftThumbstick.yAxis.value;
}

- (float)rightStickX {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.rightThumbstick.xAxis.value;
}

- (float)rightStickY {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.rightThumbstick.yAxis.value;
}

- (float)leftTrigger {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.leftTrigger.value;
}

- (float)rightTrigger {
    if (!self.activeController || !self.activeController.extendedGamepad) return 0.0f;
    return self.activeController.extendedGamepad.rightTrigger.value;
}

// Button getters
- (BOOL)buttonA {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.buttonA.pressed;
}

- (BOOL)buttonB {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.buttonB.pressed;
}

- (BOOL)buttonX {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.buttonX.pressed;
}

- (BOOL)buttonY {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.buttonY.pressed;
}

- (BOOL)leftShoulder {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.leftShoulder.pressed;
}

- (BOOL)rightShoulder {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.rightShoulder.pressed;
}

- (BOOL)dpadUp {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.dpad.up.pressed;
}

- (BOOL)dpadDown {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.dpad.down.pressed;
}

- (BOOL)dpadLeft {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.dpad.left.pressed;
}

- (BOOL)dpadRight {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    return self.activeController.extendedGamepad.dpad.right.pressed;
}

- (BOOL)buttonMenu {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return self.activeController.extendedGamepad.buttonMenu.pressed;
    }
    return NO;
}

- (BOOL)buttonOptions {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return self.activeController.extendedGamepad.buttonOptions.pressed;
    }
    return NO;
}

- (BOOL)leftStickClick {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    if (@available(iOS 12.1, *)) {
        return self.activeController.extendedGamepad.leftThumbstickButton.pressed;
    }
    return NO;
}

- (BOOL)rightStickClick {
    if (!self.activeController || !self.activeController.extendedGamepad) return NO;
    if (@available(iOS 12.1, *)) {
        return self.activeController.extendedGamepad.rightThumbstickButton.pressed;
    }
    return NO;
}

// Haptic feedback
- (void)triggerHaptic:(float)intensity duration:(int)durationMs {
    if (@available(iOS 13.0, *)) {
        if (!self.hapticEngine || self.hapticEngine.currentTime < 0) {
            return;
        }
        
        // Clamp intensity
        intensity = fmax(0.0f, fmin(1.0f, intensity));
        
        CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticIntensity
            value:intensity];
        
        CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticSharpness
            value:0.5f];
        
        CHHapticEvent *event = [[CHHapticEvent alloc]
            initWithEventType:CHHapticEventTypeHapticTransient
            parameters:@[intensityParam, sharpnessParam]
            relativeTime:0
            duration:durationMs / 1000.0f];
        
        NSError *error = nil;
        CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[event]
                                                               parameters:@[]
                                                                    error:&error];
        if (error) {
            return;
        }
        
        id<CHHapticPatternPlayer> player = [self.hapticEngine createPlayerWithPattern:pattern error:&error];
        if (error) {
            return;
        }
        
        [player startAtTime:0 error:&error];
    }
}

// Testing methods
+ (void)testBasicDetection {
    NSLog(@"=== Basic Controller Test ===");
    
    // Method 1: Direct check
    NSArray *controllers = [GCController controllers];
    NSLog(@"Method 1 - Direct check: %lu controllers", (unsigned long)controllers.count);
    
    // Check if we're on main thread
    NSLog(@"On main thread: %@", [NSThread isMainThread] ? @"YES" : @"NO");
}

+ (void)performDelayedControllerCheck {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"=== Delayed Controller Check (2 seconds) ===");
        NSArray *controllers = [GCController controllers];
        NSLog(@"Found %lu controllers", (unsigned long)controllers.count);
        
        for (GCController *controller in controllers) {
            NSLog(@"  - %@", controller.vendorName);
        }
    });
}

+ (void)debugControllerState {
    NSLog(@"=== iOS GameController Debug Info ===");
    NSArray *controllers = [GCController controllers];
    NSLog(@"Total controllers: %lu", (unsigned long)controllers.count);
    
    for (int i = 0; i < controllers.count; i++) {
        GCController *controller = controllers[i];
        NSLog(@"Controller %d: %@", i, controller.vendorName);
        NSLog(@"  - Extended gamepad: %@", controller.extendedGamepad ? @"YES" : @"NO");
        NSLog(@"  - Micro gamepad: %@", controller.microGamepad ? @"YES" : @"NO");
    }
    
    IOSGameController *shared = [IOSGameController sharedController];
    NSLog(@"Active controller: %@", shared.activeController ? shared.activeController.vendorName : @"NONE");
}

+ (void)forceRescan {
    NSLog(@"iOS GameController: Force rescan requested");
    IOSGameController *shared = [IOSGameController sharedController];
    shared.activeController = nil;
    [shared findController];
}

- (void)disconnectCurrentController {
    if (self.activeController) {
        NSLog(@"iOS GameController: Manually disconnecting current controller");
        self.activeController = nil;
        if (@available(iOS 13.0, *)) {
            if (self.hapticEngine) {
                [self.hapticEngine stopWithCompletionHandler:nil];
                self.hapticEngine = nil;
            }
        }
    }
}

- (void)refreshControllers {
    NSLog(@"iOS GameController: Manual refresh requested");
    self.activeController = nil;
    [self startControllerDiscovery];
}

@end
