/*
 * Mach-O launcher for GlistEngine.app (universal binary, arm64 + x86_64).
 *
 * Resolves its own path through symlinks (so launching via a /Applications
 * symlink still works), derives the bundle's eclipse/ directory from it, and
 * execs the shell dispatcher with that directory passed in via GLIST_ECLIPSE_DIR.
 * Doing the resolve in C avoids cwd-dependent dirname()/pwd traps that the
 * shell version had.
 */
#include <unistd.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <mach-o/dyld.h>

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

int main(int argc, char **argv) {
    char self_raw[PATH_MAX];
    uint32_t size = sizeof(self_raw);
    if (_NSGetExecutablePath(self_raw, &size) != 0) {
        fprintf(stderr, "GlistEngine launcher: _NSGetExecutablePath failed\n");
        return 1;
    }

    /* Resolve symlinks. Required when the user launches via a /Applications
     * symlink to the real .app inside ~/dev/glist/...                       */
    char self[PATH_MAX];
    if (realpath(self_raw, self) == NULL) {
        fprintf(stderr, "GlistEngine launcher: realpath(%s) failed\n", self_raw);
        return 1;
    }

    /* self = .../GlistEngine.app/Contents/MacOS/launcher
     * dir1 = .../GlistEngine.app/Contents/MacOS
     * dir2 = .../GlistEngine.app/Contents
     * dir3 = .../GlistEngine.app
     * dir4 = .../eclipse                                                    */
    char dir_macos[PATH_MAX];
    snprintf(dir_macos, sizeof(dir_macos), "%s", self);
    dirname(dir_macos);  /* mutates in place via libgen; safe on char buffer */
    char dir_macos_copy[PATH_MAX];
    snprintf(dir_macos_copy, sizeof(dir_macos_copy), "%s", self);
    char *d_macos = dirname(dir_macos_copy);

    char eclipse_dir[PATH_MAX];
    snprintf(eclipse_dir, sizeof(eclipse_dir), "%s/../../..", d_macos);
    char eclipse_dir_resolved[PATH_MAX];
    if (realpath(eclipse_dir, eclipse_dir_resolved) == NULL) {
        fprintf(stderr,
                "GlistEngine launcher: could not resolve eclipse dir from %s\n",
                eclipse_dir);
        return 1;
    }

    setenv("GLIST_ECLIPSE_DIR", eclipse_dir_resolved, 1);
    setenv("GLIST_LAUNCHER_DIR", d_macos, 1);

    /* Hand off to the shell dispatcher next to us. */
    char script[PATH_MAX];
    snprintf(script, sizeof(script), "%s/launcher.sh", d_macos);
    if (!file_exists(script)) {
        fprintf(stderr, "GlistEngine launcher: %s not found\n", script);
        return 1;
    }

    argv[0] = script;
    execv(script, argv);
    perror("GlistEngine launcher exec");
    return 127;
}
