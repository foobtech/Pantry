// pantry-helper: tiny setuid-root helper for Pantry (rootless jailbreaks, /var/jb).
// It runs a fixed set of commands and nothing else. It never executes a shell and
// never takes arbitrary paths or arguments.
//
//   pantry-helper install <file.deb>   dpkg -i, only for .deb files inside the Pantry cache dir
//   pantry-helper remove <package>     dpkg -r, only for well-formed package names
//   pantry-helper uicache              uicache -a
//   pantry-helper sbreload             sbreload

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

// Rootless: "/var/jb". Rootful (iOS 12 era jailbreaks): "" (build with -DJBROOT=\"\").
#ifndef JBROOT
#define JBROOT "/var/jb"
#endif
#define DPKG JBROOT "/usr/bin/dpkg"
#define UICACHE JBROOT "/usr/bin/uicache"
#define SBRELOAD JBROOT "/usr/bin/sbreload"
#define CACHE_DIR "/var/mobile/Library/Caches/com.foobtech.pantry"

static int run(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid == 0) {
        char *envp[] = {
            "PATH=" JBROOT "/usr/bin:" JBROOT "/bin:/usr/bin:/bin",
            "HOME=/var/root",
            NULL,
        };
        execve(argv[0], argv, envp);
        perror("execve");
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return 1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

// Debian package names: lowercase letters, digits, '+', '-', '.', starting with a letter or digit.
static int valid_package_name(const char *s) {
    size_t n = strlen(s);
    if (n < 2 || n > 128) return 0;
    if (!isalnum((unsigned char)s[0])) return 0;
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (!(islower(c) || isdigit(c) || c == '+' || c == '-' || c == '.')) return 0;
    }
    return 1;
}

// The .deb must resolve (after symlinks) to a regular file inside the Pantry cache directory.
static int resolve_deb_path(const char *path, char *resolved) {
    char base[PATH_MAX];
    if (!realpath(CACHE_DIR, base)) return 0;
    if (!realpath(path, resolved)) return 0;
    size_t n = strlen(base);
    if (strncmp(resolved, base, n) != 0 || resolved[n] != '/') return 0;
    size_t len = strlen(resolved);
    if (len < 5 || strcmp(resolved + len - 4, ".deb") != 0) return 0;
    struct stat st;
    if (lstat(resolved, &st) != 0 || !S_ISREG(st.st_mode)) return 0;
    return 1;
}

static int usage(void) {
    fprintf(stderr, "usage: pantry-helper install <file.deb> | remove <package> | uicache | sbreload\n");
    return 64;
}

int main(int argc, char **argv) {
    if (argc < 2) return usage();

    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "pantry-helper: cannot become root (is the binary setuid root?)\n");
        return 2;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "install") == 0 && argc == 3) {
        char resolved[PATH_MAX];
        if (!resolve_deb_path(argv[2], resolved)) {
            fprintf(stderr, "pantry-helper: refusing path outside the Pantry cache: %s\n", argv[2]);
            return 65;
        }
        char *args[] = { DPKG, "-i", resolved, NULL };
        return run(args);
    }
    if (strcmp(cmd, "remove") == 0 && argc == 3) {
        if (!valid_package_name(argv[2])) {
            fprintf(stderr, "pantry-helper: invalid package name\n");
            return 65;
        }
        char *args[] = { DPKG, "-r", argv[2], NULL };
        return run(args);
    }
    if (strcmp(cmd, "uicache") == 0 && argc == 2) {
        char *args[] = { UICACHE, "-a", NULL };
        return run(args);
    }
    if (strcmp(cmd, "sbreload") == 0 && argc == 2) {
        char *args[] = { SBRELOAD, NULL };
        return run(args);
    }
    return usage();
}
