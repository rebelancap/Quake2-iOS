//
//  AppDelegate.m
//  Quake2-iOS
//
//  Created by Tom Kidd on 1/26/19.
//

#import "AppDelegate.h"

@implementation SDLUIKitDelegate (customDelegate)

// hijack the the SDL_UIKitAppDelegate to use the UIApplicationDelegate we implement here
+ (NSString *)getAppDelegateClassName {
    return @"AppDelegate";
}

@end

@implementation AppDelegate
@synthesize rootNavigationController, uiwindow;

#pragma mark -
#pragma mark AppDelegate methods

- (id)init {
    self = [super init];
    if (self) {
        rootNavigationController = nil;
        uiwindow = nil;
    }
    return self;
}

// Handle Quick Actions (3D Touch)
- (BOOL)handleShortcutItem:(UIApplicationShortcutItem *)shortcutItem {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    
    if ([shortcutItem.type isEqualToString:[NSString stringWithFormat:@"%@.vanilla", bundleId]]) {
        [defaults removeObjectForKey:@"launchMod"];
    } else if ([shortcutItem.type isEqualToString:[NSString stringWithFormat:@"%@.xatrix", bundleId]]) {
        [defaults setObject:@"xatrix" forKey:@"launchMod"];
    } else if ([shortcutItem.type isEqualToString:[NSString stringWithFormat:@"%@.rogue", bundleId]]) {
        [defaults setObject:@"rogue" forKey:@"launchMod"];
    } else {
        return NO;
    }
    
    [defaults synchronize];
    
    // If app is already running, show restart alert
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Restart Required"
            message:@"Please restart the app to load the selected game mode."
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:@"Restart"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];
        
        [alert addAction:okAction];
        
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    }
    
    return YES;
}

// Handle URL launch
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    return [self handleQuakeURL:url];
}

// For iOS 8 and earlier
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self handleQuakeURL:url];
}

- (BOOL)handleQuakeURL:(NSURL *)url {
    NSLog(@"Handling URL: %@", url.absoluteString);
    
    if ([url.scheme isEqualToString:@"quake2"]) {
        NSString *host = url.host;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        
        NSString *mod = nil;
        NSString *map = nil;
        
        // Parse query parameters
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"mod"]) {
                mod = item.value;
            } else if ([item.name isEqualToString:@"map"]) {
                map = item.value;
            }
        }
        
        // Store launch parameters
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        if ([host isEqualToString:@"vanilla"]) {
            // Vanilla Quake 2
            [defaults removeObjectForKey:@"launchMod"];
            if (map) {
                [defaults setObject:map forKey:@"launchMap"];
            }
        } else if ([host isEqualToString:@"mod"] && mod) {
            // Mission pack or mod
            [defaults setObject:mod forKey:@"launchMod"];
            if (map) {
                [defaults setObject:map forKey:@"launchMap"];
            }
        }
        
        [defaults synchronize];
        
        // If app is already running, we need to restart
        UIApplicationState state = [[UIApplication sharedApplication] applicationState];
        if (state == UIApplicationStateActive || state == UIApplicationStateInactive) {
            
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Restart Required"
                message:@"Please restart the app to load the selected game mode."
                preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:@"Restart"
                style:UIAlertActionStyleDefault
                handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }];
            
            [alert addAction:okAction];
            
            [self.uiwindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
        
        return YES;
    }
    
    return NO;
}

// App launch
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Handle URL launch if present
    NSURL *url = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if (url) {
        [self handleQuakeURL:url];
    }
    
    // Check if launched from a shortcut
    UIApplicationShortcutItem *shortcutItem = launchOptions[UIApplicationLaunchOptionsShortcutItemKey];
    if (shortcutItem) {
        [self handleShortcutItem:shortcutItem];
        // Don't return NO here - let the app continue launching
    }
    
    // Set up game background/foreground notifications
    [self setupGameNotifications];
    
    // IMPORTANT: Must call super to let SDL initialize
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

// Handle Quick Actions when app is already running
- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    BOOL handled = [self handleShortcutItem:shortcutItem];
    completionHandler(handled);
}

// override the direct execution of SDL_main to allow us to implement our own frontend
- (void)postFinishLaunch
{
    [self performSelector:@selector(hideLaunchScreen) withObject:nil afterDelay:0.0];

#if !TARGET_OS_TV
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
#endif
    
    // Get launch parameters
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *launchMod = [defaults stringForKey:@"launchMod"];
    
    // Check for game data FIRST, before anything else
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *baseq2Path = [documentsPath stringByAppendingPathComponent:@"baseq2"];
    
    // Always need baseq2
    BOOL baseq2Exists = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:baseq2Path]) {
        // Check for any valid pak file (pak0.pak, pak0.pkz, pak0.pk3)
        NSString *pak0Path = [baseq2Path stringByAppendingPathComponent:@"pak0.pak"];
        NSString *pak0PkzPath = [baseq2Path stringByAppendingPathComponent:@"pak0.pkz"];
        NSString *pak0Pk3Path = [baseq2Path stringByAppendingPathComponent:@"pak0.pk3"];
        
        baseq2Exists = [fm fileExistsAtPath:pak0Path] ||
                       [fm fileExistsAtPath:pak0PkzPath] ||
                       [fm fileExistsAtPath:pak0Pk3Path];
    }
    
    // Check if mod exists (if launching a mod)
    BOOL modExists = YES; // Assume true unless we're loading a mod
    NSString *missingFolder = nil;
    
    if (!baseq2Exists) {
        missingFolder = @"baseq2";
    }
    else if (launchMod && launchMod.length > 0) {
        NSString *modPath = [documentsPath stringByAppendingPathComponent:launchMod];
        
        // Special handling for AQtion
        if ([launchMod isEqualToString:@"baseaq"]) {
            NSString *pak0Path = [modPath stringByAppendingPathComponent:@"pak0.pkz"];
            NSString *pak1Path = [modPath stringByAppendingPathComponent:@"pak1.pkz"];
            modExists = [fm fileExistsAtPath:pak0Path] && [fm fileExistsAtPath:pak1Path];
        } else {
            // Generic mod check
            NSString *modPak0Path = [modPath stringByAppendingPathComponent:@"pak0.pak"];
            NSString *modPak0PkzPath = [modPath stringByAppendingPathComponent:@"pak0.pkz"];
            NSString *modPak0Pk3Path = [modPath stringByAppendingPathComponent:@"pak0.pk3"];
            
            modExists = [fm fileExistsAtPath:modPak0Path] ||
                        [fm fileExistsAtPath:modPak0PkzPath] ||
                        [fm fileExistsAtPath:modPak0Pk3Path];
        }
        
        if (!modExists) {
            missingFolder = launchMod;
        }
    }
    
    if (!baseq2Exists || !modExists) {
        // Create a simple window and show alert
        self.uiwindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        self.uiwindow.backgroundColor = [UIColor blackColor];
        UIViewController *rootVC = [[UIViewController alloc] init];
        self.uiwindow.rootViewController = rootVC;
        [self.uiwindow makeKeyAndVisible];
        
        NSString *message;
        if (!baseq2Exists) {
            message = @"Game data missing!\n\n"
                      "Please copy the game folders to the Documents directory:\n\n"
                      "Required:\n"
                      "• baseq2 folder with pak0.pak\n\n"
                      "Optional:\n"
                      "• xatrix (The Reckoning)\n"
                      "• rogue (Ground Zero)\n"
                      "• baseaq (AQtion)\n\n"
                      "Use the Files app or macOS Finder to transfer the folders.";
        } else {
            // Mod-specific message
            NSString *modName = launchMod;
            if ([launchMod isEqualToString:@"xatrix"]) {
                modName = @"The Reckoning";
            } else if ([launchMod isEqualToString:@"rogue"]) {
                modName = @"Ground Zero";
            } else if ([launchMod isEqualToString:@"baseaq"]) {
                modName = @"AQtion";
            }
            
            NSString *expectedFiles = @"pak0.pak";
            if ([launchMod isEqualToString:@"baseaq"]) {
                expectedFiles = @"pak0.pkz and pak1.pkz";
            }
            
            message = [NSString stringWithFormat:@"%@ data missing!\n\n"
                                                 "The folder '%@' was not found in Documents or is incomplete.\n\n"
                                                 "To play %@, please copy the '%@' folder to Documents.\n\n"
                                                 "The folder should contain %@.",
                                                 modName, missingFolder, modName, missingFolder, expectedFiles];
        }
        
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Game Data Missing"
            message:message
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * _Nonnull action) {
                // Clear the mod selection so next launch is vanilla
                [defaults removeObjectForKey:@"launchMod"];
                [defaults synchronize];
                exit(0);
            }];
        
        [alert addAction:okAction];
        
        [rootVC presentViewController:alert animated:YES completion:nil];
        
        // Don't continue to game launch
        return;
    }
    
    // If we get here, all required game data exists, so launch the game
    dispatch_async(dispatch_get_main_queue(), ^{
        // Build command line arguments
        NSString *launchMap = [defaults stringForKey:@"launchMap"];
        
        // Start with basic args
        NSMutableArray *args = [NSMutableArray arrayWithObject:@"quake2"];
        
        // Add retexturing support for PNG fallback
        [args addObject:@"+set"];
        [args addObject:@"gl_retexturing"];
        [args addObject:@"1"];

        // Skip demo and go to menu (important for mods without demo files)
//        [args addObject:@"+menu_main"];
        
        // Add mod args
        if (launchMod && launchMod.length > 0) {
            [args addObject:@"+set"];
            [args addObject:@"game"];
            [args addObject:launchMod];
            
            // Clear the stored mod
            [defaults removeObjectForKey:@"launchMod"];
        }
        
        // Add map args
        if (launchMap && launchMap.length > 0) {
            [args addObject:@"+map"];
            [args addObject:launchMap];
            
            // Clear the stored map
            [defaults removeObjectForKey:@"launchMap"];
        }
        
        [defaults synchronize];
        
        // Convert to C args
        int argc = (int)[args count];
        char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
        
        for (int i = 0; i < argc; i++) {
            NSString *arg = args[i];
            argv[i] = strdup([arg UTF8String]);
        }
        argv[argc] = NULL;
        
        // Call the real Quake 2 main
        extern int Sys_Startup(int argc, char **argv);
        Sys_Startup(argc, argv);
    });
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    [super applicationDidReceiveMemoryWarning:application];
}

#pragma mark - Background GPU Handling

// Setup notifications for background/foreground handling
- (void)setupGameNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePauseRendering:)
                                                 name:@"PauseGameRendering"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleResumeRendering:)
                                                 name:@"ResumeGameRendering"
                                               object:nil];
}

- (void)handlePauseRendering:(NSNotification *)notification {
    NSLog(@"Quake2 AppDelegate: Handling pause rendering notification");
    extern void CL_PauseRendering(void);
    CL_PauseRendering();
}

- (void)handleResumeRendering:(NSNotification *)notification {
    NSLog(@"Quake2 AppDelegate: Handling resume rendering notification");
    extern void CL_ResumeRendering(void);
    CL_ResumeRendering();
}

// Background/foreground handling
- (void)applicationWillResignActive:(UIApplication *)application {
    [super applicationWillResignActive:application];
    NSLog(@"Quake2: App going to background - pausing game rendering");
    
    // Send notification to pause rendering
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PauseGameRendering" object:nil];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [super applicationDidEnterBackground:application];
    NSLog(@"Quake2: App entered background");
    
    // Send notification to pause rendering (backup)
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PauseGameRendering" object:nil];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [super applicationDidBecomeActive:application];
    NSLog(@"Quake2: App became active - resuming game rendering");
    
    // Send notification to resume rendering
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ResumeGameRendering" object:nil];
}

// SDL requires this symbol to exist
int SDL_main(int argc, char **argv) {
    // Build command line arguments from URL parameters
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *launchMod = [defaults stringForKey:@"launchMod"];
    NSString *launchMap = [defaults stringForKey:@"launchMap"];
    
    // Count how many args we need
    int newArgc = argc;
    if (launchMod) newArgc += 3; // +set game modname
    if (launchMap) newArgc += 2; // +map mapname
    
    // Allocate new argv array
    char **newArgv = (char **)malloc(sizeof(char *) * (newArgc + 1));
    
    // Copy original args
    int i;
    for (i = 0; i < argc; i++) {
        newArgv[i] = argv[i];
    }
    
    // Add mod args
    if (launchMod) {
        newArgv[i++] = "+set";
        newArgv[i++] = "game";
        newArgv[i++] = (char *)[launchMod UTF8String];
        
        // Clear the stored mod
        [defaults removeObjectForKey:@"launchMod"];
    }
    
    // Add map args
    if (launchMap) {
        newArgv[i++] = "+map";
        newArgv[i++] = (char *)[launchMap UTF8String];
        
        // Clear the stored map
        [defaults removeObjectForKey:@"launchMap"];
    }
    
    [defaults synchronize];
    
    newArgv[newArgc] = NULL;
    
    // Call the real Quake 2 main
    extern int Sys_Startup(int argc, char **argv);
    return Sys_Startup(newArgc, newArgv);
}

@end
