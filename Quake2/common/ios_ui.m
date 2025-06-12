//
//  ios_ui.m - iOS UI-specific code
//  Quake2-iOS
//
//  Created by rebelancap on 6/11/25.
//
// This file contains Objective-C code that can't be in C files

#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IOS

#import <UIKit/UIKit.h>

// Function to show missing data alert
void Sys_ShowMissingDataAlert_ObjC(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Game Data Missing"
            message:@"Please copy the game folders to the Documents directory:\n\n"
                    "• baseq2 (required)\n"
                    "• xatrix (The Reckoning)\n"
                    "• rogue (Ground Zero)\n\n"
                    "Use the Files app or iTunes File Sharing to transfer the folders."
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * _Nonnull action) {
                // Exit the app
                exit(0);
            }];
        
        [alert addAction:okAction];
        
        // Get the key window - SDL creates its own
        UIWindow *window = nil;
        
        // Try to find SDL window
        for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
            if (w.isKeyWindow) {
                window = w;
                break;
            }
        }
        
        if (!window) {
            window = [[[UIApplication sharedApplication] windows] firstObject];
        }
        
        UIViewController *rootViewController = window.rootViewController;
        
        if (rootViewController) {
            [rootViewController presentViewController:alert animated:YES completion:nil];
        } else {
            // If no view controller yet, try again after a delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIWindow *window = nil;
                for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                
                UIViewController *rootViewController = window.rootViewController;
                if (rootViewController) {
                    [rootViewController presentViewController:alert animated:YES completion:nil];
                }
            });
        }
    });
}

#endif // TARGET_OS_IOS
#endif // __APPLE__
