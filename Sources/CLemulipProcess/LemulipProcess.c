#define _GNU_SOURCE 1
#include "LemulipProcess.h"
#include <spawn.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>
#include <unistd.h>

int lemulip_process_spawn(pid_t *pid, const char *path, char *const argv[],
                         char *const envp[], const char *directory,
                         int stdout_fd, int stderr_fd) {
    if (!pid || !path || !argv || !envp || stdout_fd < 3 || stderr_fd < 3) return EINVAL;
    *pid = 0;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) return error;
    error = posix_spawnattr_init(&attributes);
    if (error) { posix_spawn_file_actions_destroy(&actions); return error; }
    sigset_t mask, defaults;
    sigemptyset(&mask);
    sigfillset(&defaults);
    sigdelset(&defaults, SIGKILL); sigdelset(&defaults, SIGSTOP);
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
#ifdef __APPLE__
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
#define APPLY(call) do { error = (call); if (error) goto cleanup; } while (0)
    APPLY(posix_spawnattr_setflags(&attributes, flags));
    APPLY(posix_spawnattr_setpgroup(&attributes, 0));
    APPLY(posix_spawnattr_setsigmask(&attributes, &mask));
    APPLY(posix_spawnattr_setsigdefault(&attributes, &defaults));
    APPLY(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    APPLY(posix_spawn_file_actions_adddup2(&actions, stdout_fd, STDOUT_FILENO));
    APPLY(posix_spawn_file_actions_adddup2(&actions, stderr_fd, STDERR_FILENO));
#ifndef __APPLE__
    APPLY(posix_spawn_file_actions_addclosefrom_np(&actions, 3));
#endif
    if (directory) APPLY(posix_spawn_file_actions_addchdir_np(&actions, directory));
    error = posix_spawn(pid, path, &actions, &attributes, argv, envp);
cleanup:
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return error;
#undef APPLY
}

int lemulip_process_wait(pid_t pid, int *exit_code) {
    if (pid <= 1 || !exit_code) return EINVAL;
    siginfo_t info;
    int result;
    do { result = waitid(P_PID, (id_t)pid, &info, WEXITED | WNOWAIT); } while (result < 0 && errno == EINTR);
    if (result < 0) return errno;
    *exit_code = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status;
    return 0;
}

int lemulip_process_reap(pid_t pid) {
    if (pid <= 1) return EINVAL;
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    return result < 0 ? errno : 0;
}

int lemulip_process_signal_group(pid_t pid, int signal_number) {
    /* Never target the app, its group, or a caller-supplied arbitrary group. */
    if (pid <= 1 || pid == getpid() || pid == getpgrp()) return EINVAL;
    return kill(-pid, signal_number) < 0 ? errno : 0;
}
