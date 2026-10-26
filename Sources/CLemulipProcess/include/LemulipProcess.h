#ifndef LEMULIP_PROCESS_H
#define LEMULIP_PROCESS_H
#include <sys/types.h>
/* Returns a POSIX error number, or zero. Each launch owns a new process group. */
int lemulip_process_spawn(pid_t *pid, const char *path, char *const argv[],
                         char *const envp[], const char *directory,
                         int stdout_fd, int stderr_fd);
/* Observe termination without reaping. This reserves the group leader's PID. */
int lemulip_process_wait(pid_t pid, int *exit_code);
int lemulip_process_reap(pid_t pid);
int lemulip_process_signal_group(pid_t pid, int signal_number);
#endif
