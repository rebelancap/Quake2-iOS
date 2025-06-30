/*
 * Copyright (C) 1997-2001 Id Software, Inc.
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
 * =======================================================================
 *
 * This file implements all system dependent generic functions.
 *
 * =======================================================================
 */

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/select.h> /* for fd_set */

#ifdef __APPLE__
#include <mach/clock.h>
#include <mach/mach.h>
#include <sys/time.h>
#endif

#include "../../common/header/common.h"
#include "../../common/header/glob.h"

#ifdef IOS
// Used to determine where to store user-specific files
char homePath[MAX_OSPATH] = { 0 };
#include "game.h"
game_export_t *GetGameAPI(game_import_t *import);
#import <Foundation/Foundation.h>
#endif

#ifdef IOS
// Direct reference to the compiled-in GetGameAPI
extern game_export_t *GetGameAPI(game_import_t *import);

// Ensure the game's globals are properly linked
extern game_export_t globals;
#endif

// 4. Also need to declare the console command. Add this near the top of system.c, after the includes:
#ifdef IOS
void Cmd_ListGameLibs_f(void);
#endif

// Pointer to game library
static void *game_library;

// Evil hack to determine if stdin is available
qboolean stdin_active = true;

// Console logfile
extern FILE	*logfile;

/* ================================================================ */

void
Sys_Error(char *error, ...)
{
	va_list argptr;
	char string[1024];

	/* change stdin to non blocking */
	fcntl(0, F_SETFL, fcntl(0, F_GETFL, 0) & ~FNDELAY);

#ifndef DEDICATED_ONLY
	CL_Shutdown();
#endif
	Qcommon_Shutdown();

	va_start(argptr, error);
	vsnprintf(string, 1024, error, argptr);
	va_end(argptr);
	fprintf(stderr, "Error: %s\n", string);

	exit(1);
}

void
Sys_Quit(void)
{
#ifndef DEDICATED_ONLY
	CL_Shutdown();
#endif

	if (logfile)
	{
		fclose(logfile);
		logfile = NULL;
	}

	Qcommon_Shutdown();
	fcntl(0, F_SETFL, fcntl(0, F_GETFL, 0) & ~FNDELAY);

	printf("------------------------------------\n");

	exit(0);
}

void
Sys_Init(void)
{
}

/* ================================================================ */

char *
Sys_ConsoleInput(void)
{
	static char text[256];
	int len;
	fd_set fdset;
	struct timeval timeout;

	if (!dedicated || !dedicated->value)
	{
		return NULL;
	}

	if (!stdin_active)
	{
		return NULL;
	}

	FD_ZERO(&fdset);
	FD_SET(0, &fdset); /* stdin */
	timeout.tv_sec = 0;
	timeout.tv_usec = 0;

	if ((select(1, &fdset, NULL, NULL, &timeout) == -1) || !FD_ISSET(0, &fdset))
	{
		return NULL;
	}

	len = read(0, text, sizeof(text));

	if (len == 0)   /* eof! */
	{
		stdin_active = false;
		return NULL;
	}

	if (len < 1)
	{
		return NULL;
	}

	text[len - 1] = 0; /* rip off the /n and terminate */

	return text;
}

void
Sys_ConsoleOutput(char *string)
{
	fputs(string, stdout);
}

/* ================================================================ */

long long
Sys_Microseconds(void)
{
#ifdef __APPLE__
	// OSX didn't have clock_gettime() until recently, so use Mach's clock_get_time()
	// instead. fortunately its mach_timespec_t seems identical to POSIX struct timespec
	// so lots of code can be shared
	clock_serv_t cclock;
	mach_timespec_t now;
	static mach_timespec_t first;

	host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &cclock);
	clock_get_time(cclock, &now);
	mach_port_deallocate(mach_task_self(), cclock);

#else // not __APPLE__ - other Unix-likes will hopefully support clock_gettime()

	struct timespec now;
	static struct timespec first;
#ifdef _POSIX_MONOTONIC_CLOCK
	clock_gettime(CLOCK_MONOTONIC, &now);
#else
	clock_gettime(CLOCK_REALTIME, &now);
#endif

#endif // not __APPLE__

	if(first.tv_sec == 0)
	{
		long long nsec = now.tv_nsec;
		long long sec = now.tv_sec;
		// set back first by 1ms so neither this function nor Sys_Milliseconds()
		// (which calls this) will ever return 0
		nsec -= 1000000;
		if(nsec < 0)
		{
			nsec += 1000000000ll; // 1s in ns => definitely positive now
			--sec;
		}

		first.tv_sec = sec;
		first.tv_nsec = nsec;
	}

	long long sec = now.tv_sec - first.tv_sec;
	long long nsec = now.tv_nsec - first.tv_nsec;

	if(nsec < 0)
	{
		nsec += 1000000000ll; // 1s in ns
		--sec;
	}

	return sec*1000000ll + nsec/1000ll;
}

#ifdef IOS
void Sys_SetHomeDir( const char* newHomeDir )
{
    strncpy(homePath, newHomeDir, sizeof(homePath));
    strcat(homePath, "/");
}
#endif

int
Sys_Milliseconds(void)
{
	return (int)(Sys_Microseconds()/1000ll);
}

void
Sys_Nanosleep(int nanosec)
{
	struct timespec t = {0, nanosec};
	nanosleep(&t, NULL);
}

/* ================================================================ */

/* The musthave and canhave arguments are unused in YQ2. We
   can't remove them since Sys_FindFirst() and Sys_FindNext()
   are defined in shared.h and may be used in custom game DLLs. */

static char findbase[MAX_OSPATH];
static char findpath[MAX_OSPATH];
static char findpattern[MAX_OSPATH];
static DIR *fdir;

char *
Sys_FindFirst(char *path, unsigned musthave, unsigned canhave)
{
	struct dirent *d;
	char *p;

	if (fdir)
	{
		Sys_Error("Sys_BeginFind without close");
	}

	strcpy(findbase, path);

	if ((p = strrchr(findbase, '/')) != NULL)
	{
		*p = 0;
		strcpy(findpattern, p + 1);
	}
	else
	{
		strcpy(findpattern, "*");
	}

	if (strcmp(findpattern, "*.*") == 0)
	{
		strcpy(findpattern, "*");
	}

	if ((fdir = opendir(findbase)) == NULL)
	{
		return NULL;
	}

	while ((d = readdir(fdir)) != NULL)
	{
		if (!*findpattern || glob_match(findpattern, d->d_name))
		{
			if ((strcmp(d->d_name, ".") != 0) || (strcmp(d->d_name, "..") != 0))
			{
				sprintf(findpath, "%s/%s", findbase, d->d_name);
				return findpath;
			}
		}
	}

	return NULL;
}

char *
Sys_FindNext(unsigned musthave, unsigned canhave)
{
	struct dirent *d;

	if (fdir == NULL)
	{
		return NULL;
	}

	while ((d = readdir(fdir)) != NULL)
	{
		if (!*findpattern || glob_match(findpattern, d->d_name))
		{
			if ((strcmp(d->d_name, ".") != 0) || (strcmp(d->d_name, "..") != 0))
			{
				sprintf(findpath, "%s/%s", findbase, d->d_name);
				return findpath;
			}
		}
	}

	return NULL;
}

void
Sys_FindClose(void)
{
	if (fdir != NULL)
	{
		closedir(fdir);
	}

	fdir = NULL;
}

/* ================================================================ */

void
Sys_UnloadGame(void)
{
	if (game_library)
	{
		dlclose(game_library);
	}

	game_library = NULL;
}

// 2. Replace the entire Sys_GetGameAPI function with this version:
void *
Sys_GetGameAPI(void *parms)
{
#ifdef IOS
    // iOS-specific dynamic loading implementation
    static char game_library_path[MAX_OSPATH];
    const char *gamename = "gamearm64.dylib";
    char *gamedir;
    
    if (game_library)
    {
        Com_Error(ERR_FATAL, "Sys_GetGameAPI without Sys_UnloadingGame");
    }
    
    // Get the current game directory
    cvar_t *game = Cvar_Get("game", "", 0);
    gamedir = (game && game->string[0]) ? game->string : "baseq2";
    
    Com_Printf("LoadLibrary(\"%s/%s\")\n", gamedir, gamename);
    
    @autoreleasepool {
        // For iOS, we'll check two locations:
        // 1. App bundle (for pre-included mods like AQtion)
        // 2. Documents directory (for user-installed mods)
        
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *bundlePath = [mainBundle bundlePath];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL found = NO;
        
        // First, try the app bundle
        NSString *bundleLibPath = [NSString stringWithFormat:@"%@/%s/%s", bundlePath, gamedir, gamename];
        if ([fm fileExistsAtPath:bundleLibPath]) {
            strncpy(game_library_path, [bundleLibPath UTF8String], sizeof(game_library_path) - 1);
            game_library_path[sizeof(game_library_path) - 1] = '\0';
            found = YES;
            Com_Printf("Found library in bundle: %s\n", game_library_path);
        }
        
        // If not in bundle, try Documents
        if (!found) {
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *docLibPath = [NSString stringWithFormat:@"%@/%s/%s", documentsPath, gamedir, gamename];
            
            if ([fm fileExistsAtPath:docLibPath]) {
                strncpy(game_library_path, [docLibPath UTF8String], sizeof(game_library_path) - 1);
                game_library_path[sizeof(game_library_path) - 1] = '\0';
                found = YES;
                Com_Printf("Found library in Documents: %s\n", game_library_path);
            }
        }
        
        // If we found a library, try to load it
        if (found) {
            game_library = dlopen(game_library_path, RTLD_NOW | RTLD_LOCAL);
            
            if (game_library) {
                Com_Printf("Successfully loaded library\n");
                
                void *(*GetGameAPI_func)(void *) = (void *)dlsym(game_library, "GetGameAPI");

                if (!GetGameAPI_func) {
                    Com_Printf("Failed to find GetGameAPI symbol: %s\n", dlerror());
                    Sys_UnloadGame();
                } else {
                    Com_Printf("Found GetGameAPI, returning dynamic game\n");
                    return GetGameAPI_func(parms);
                }
            } else {
                const char *error = dlerror();
                Com_Printf("Failed to load library: %s\n", error ? error : "unknown error");
                
                if (error && strstr(error, "code signature")) {
                    Com_Printf("ERROR: Library not properly code signed\n");
                }
            }
        } else {
            Com_Printf("No dynamic library found for %s\n", gamedir);
            
            // For official expansion packs, use the built-in game code
            if (strcmp(gamedir, "xatrix") == 0 || strcmp(gamedir, "rogue") == 0)
            {
                Com_Printf("Using built-in game code for official expansion pack\n");
                return GetGameAPI(parms);
            }
        }
    }
    
    // Replace the vanilla Quake 2 section with:
    if (strcmp(gamedir, "baseq2") == 0 || strcmp(gamedir, "") == 0)
    {
        // Vanilla Quake 2 - just call it like before
        return GetGameAPI(parms);
    }
    
#else
    // Original non-iOS implementation stays exactly as it is
    void *(*GetGameAPI)(void *);

    char name[MAX_OSPATH];
    char *path;
    char *str_p;
#ifdef __APPLE__
    const char *gamename = "game.dylib";
#else
    const char *gamename = "game.so";
#endif

    if (game_library)
    {
        Com_Error(ERR_FATAL, "Sys_GetGameAPI without Sys_UnloadingGame");
    }

    Com_Printf("LoadLibrary(\"%s\")\n", gamename);

    /* now run through the search paths */
    path = NULL;

    while (1)
    {
        FILE *fp;

        path = FS_NextPath(path);

        if (!path)
        {
            return NULL; /* couldn't find one anywhere */
        }

        snprintf(name, MAX_OSPATH, "%s/%s", path, gamename);

        /* skip it if it just doesn't exist */
        fp = fopen(name, "rb");

        if (fp == NULL)
        {
            continue;
        }

        fclose(fp);

        game_library = dlopen(name, RTLD_NOW);

        if (game_library)
        {
            Com_MDPrintf("LoadLibrary (%s)\n", name);
            break;
        }
        else
        {
            Com_Printf("LoadLibrary (%s):", name);

            path = (char *)dlerror();
            str_p = strchr(path, ':'); /* skip the path (already shown) */

            if (str_p == NULL)
            {
                str_p = path;
            }
            else
            {
                str_p++;
            }

            Com_Printf("%s\n", str_p);

            return NULL;
        }
    }

    GetGameAPI = (void *)dlsym(game_library, "GetGameAPI");

    if (!GetGameAPI)
    {
        Sys_UnloadGame();
        return NULL;
    }

    return GetGameAPI(parms);
#endif
}

/* ================================================================ */

void
Sys_Mkdir(char *path)
{
	mkdir(path, 0755);
}

qboolean
Sys_IsDir(const char *path)
{
	struct stat sb;

	if (stat(path, &sb) != -1)
	{
		if (S_ISDIR(sb.st_mode))
		{
			return true;
		}
	}

	return false;
}

qboolean
Sys_IsFile(const char *path)
{
	struct stat sb;

	if (stat(path, &sb) != -1)
	{
		if (S_ISREG(sb.st_mode))
		{
			return true;
		}
	}

	return false;
}

char *
Sys_GetHomeDir(void)
{
#ifdef IOS
    return homePath;
#else
	static char gdir[MAX_OSPATH];
	char *home;

	home = getenv("HOME");

	if (!home)
	{
		return NULL;
	}

	snprintf(gdir, sizeof(gdir), "%s/%s/", home, CFGDIR);

	return gdir;
#endif
}

void
Sys_Remove(const char *path)
{
	remove(path);
}

/* ================================================================ */

void *
Sys_GetProcAddress(void *handle, const char *sym)
{
    if (handle == NULL)
    {
#ifdef RTLD_DEFAULT
        return dlsym(RTLD_DEFAULT, sym);
#else
        /* POSIX suggests that this is a portable equivalent */
        static void *global_namespace = NULL;

        if (global_namespace == NULL)
            global_namespace = dlopen(NULL, RTLD_GLOBAL|RTLD_LAZY);

        return dlsym(global_namespace, sym);
#endif
    }
    return dlsym(handle, sym);
}

void
Sys_FreeLibrary(void *handle)
{
	if (handle && dlclose(handle))
	{
		Com_Error(ERR_FATAL, "dlclose failed on %p: %s", handle, dlerror());
	}
}

void *
Sys_LoadLibrary(const char *path, const char *sym, void **handle)
{
	void *module, *entry;

	*handle = NULL;

	module = dlopen(path, RTLD_LAZY);

	if (!module)
	{
		Com_Printf("%s failed: %s\n", __func__, dlerror());
		return NULL;
	}

	if (sym)
	{
		entry = dlsym(module, sym);

		if (!entry)
		{
			Com_Printf("%s failed: %s\n", __func__, dlerror());
			dlclose(module);
			return NULL;
		}
	}
	else
	{
		entry = NULL;
	}

	Com_DPrintf("%s succeeded: %s\n", __func__, path);

	*handle = module;

	return entry;
}

/* ================================================================ */

void
Sys_GetWorkDir(char *buffer, size_t len)
{
	if (getcwd(buffer, len) != 0)
	{
		return;
	}

	buffer[0] = '\0';
}

qboolean
Sys_SetWorkDir(char *path)
{
	if (chdir(path) == 0)
	{
		return true;
	}

	return false;
}

// 3. Add this console command function at the END of system.c, AFTER all other functions,
//    right before the end of the file (at the same level as other functions):

#ifdef IOS
void Cmd_ListGameLibs_f(void)
{
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *bundlePath = [mainBundle bundlePath];
        
        Com_Printf("\n=== Game Libraries ===\n");
        Com_Printf("Bundle path: %s\n", [bundlePath UTF8String]);
        Com_Printf("Documents path: %s\n", [documentsPath UTF8String]);
        
        // Check bundle
        NSArray *bundleDirs = @[@"baseq2", @"xatrix", @"rogue", @"baseaq"];
        Com_Printf("\nBundle libraries:\n");
        for (NSString *dir in bundleDirs) {
            NSString *libPath = [NSString stringWithFormat:@"%@/%@/gamearm64.dylib", bundlePath, dir];
            if ([fm fileExistsAtPath:libPath]) {
                Com_Printf("  %s: FOUND\n", [dir UTF8String]);
            }
        }
        
        // Check Documents
        Com_Printf("\nDocuments directories:\n");
        NSError *error = nil;
        NSArray *contents = [fm contentsOfDirectoryAtPath:documentsPath error:&error];
        
        if (!error) {
            for (NSString *item in contents) {
                NSString *itemPath = [documentsPath stringByAppendingPathComponent:item];
                BOOL isDirectory = NO;
                
                if ([fm fileExistsAtPath:itemPath isDirectory:&isDirectory] && isDirectory) {
                    NSString *libPath = [itemPath stringByAppendingPathComponent:@"gamearm64.dylib"];
                    if ([fm fileExistsAtPath:libPath]) {
                        NSDictionary *attrs = [fm attributesOfItemAtPath:libPath error:nil];
                        NSNumber *fileSize = attrs[NSFileSize];
                        Com_Printf("  %s: gamearm64.dylib (%.2f MB)\n",
                                   [item UTF8String],
                                   [fileSize doubleValue] / (1024.0 * 1024.0));
                    } else {
                        Com_Printf("  %s: no library\n", [item UTF8String]);
                    }
                }
            }
        }
        
        Com_Printf("======================\n");
    }
}
#endif
