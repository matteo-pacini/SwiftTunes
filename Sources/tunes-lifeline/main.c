/*
 * tunes-lifeline: runs a command (the model server) for as long as the app
 * that started it lives.
 *
 *   tunes-lifeline <program> [arguments...]
 *
 * The read end of a pipe whose write end only the app holds is open on fd 3,
 * or on the fd named by TUNES_LIFELINE_FD. The kernel closes the write end
 * however the app ends, even on SIGKILL, so end of file on the pipe means
 * the app is gone. The command runs in its own process group; on end of
 * file, or on SIGTERM, SIGINT or SIGHUP to this shim, the group gets SIGTERM
 * and, if it has not exited 5 s later, SIGKILL.
 *
 * The first line on stderr is "tunes-lifeline: started <pid>". The shim
 * exits with the command's status, or 128 + the signal that ended it; 125
 * when the lifeline fd is not open, 127 when the command cannot be run.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define KILL_GRACE_S 5

static int status_code(int status) {
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 1;
}

static int lifeline_fd(void) {
    const char *env = getenv("TUNES_LIFELINE_FD");
    if (env == NULL || *env == '\0') return 3;
    char *end = NULL;
    long fd = strtol(env, &end, 10);
    if (*end != '\0' || fd < 0 || fd > 1024) return -1;
    return (int)fd;
}

static double now_s(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

/* Waits up to `seconds` for the child's exit; its wait status, or -1. */
static int wait_exit(int kq, pid_t child, int seconds) {
    double deadline = now_s() + seconds;
    struct kevent ev;
    for (;;) {
        int status;
        pid_t got = waitpid(child, &status, WNOHANG);
        if (got == child) return status;
        if (got < 0 && errno != EINTR) return -1;
        double left = deadline - now_s();
        if (left <= 0) return -1;
        struct timespec wait = {(time_t)left, (long)((left - (double)(time_t)left) * 1e9)};
        int n = kevent(kq, NULL, 0, &ev, 1, &wait);
        if (n < 0 && errno != EINTR) return -1;
    }
}

static int stop_group(int kq, int fd, pid_t child) {
    /* End of file stays readable; left in, it would wake every wait. */
    struct kevent del;
    EV_SET(&del, fd, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    kevent(kq, &del, 1, NULL, 0, NULL);
    kill(-child, SIGTERM);
    int status = wait_exit(kq, child, KILL_GRACE_S);
    if (status >= 0) {
        kill(-child, SIGKILL); /* anything the command left in its group */
        return status_code(status);
    }
    kill(-child, SIGKILL);
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return 1;
    }
    return status_code(status);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: tunes-lifeline <program> [arguments...]\n");
        return 2;
    }
    int fd = lifeline_fd();
    if (fd < 0 || fcntl(fd, F_GETFD) < 0) {
        fprintf(stderr, "tunes-lifeline: the lifeline fd is not open\n");
        return 125;
    }
    fcntl(fd, F_SETFD, FD_CLOEXEC);

    int kq = kqueue();
    if (kq < 0) {
        fprintf(stderr, "tunes-lifeline: kqueue: %s\n", strerror(errno));
        return 125;
    }
    const int sigs[] = {SIGTERM, SIGINT, SIGHUP};
    struct kevent changes[5];
    int nchanges = 0;
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) {
        /* Ignored, so only the kqueue sees them; the child restores them. */
        signal(sigs[i], SIG_IGN);
        EV_SET(&changes[nchanges++], sigs[i], EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    }

    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "tunes-lifeline: fork: %s\n", strerror(errno));
        return 127;
    }
    if (child == 0) {
        setpgid(0, 0);
        for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], SIG_DFL);
        sigset_t none;
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        close(fd);
        close(kq);
        execvp(argv[1], argv + 1);
        fprintf(stderr, "tunes-lifeline: cannot run %s: %s\n", argv[1], strerror(errno));
        _exit(127);
    }
    /* Also set here, so a kill of the group cannot miss a child that has
     * not reached its own setpgid yet. */
    setpgid(child, child);
    fprintf(stderr, "tunes-lifeline: started %d\n", (int)child);
    fflush(stderr);

    EV_SET(&changes[nchanges++], fd, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&changes[nchanges++], child, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (kevent(kq, changes, nchanges, NULL, 0, NULL) < 0) {
        /* The child may already have exited, so NOTE_EXIT cannot be added. */
        int status;
        if (waitpid(child, &status, WNOHANG) == child) return status_code(status);
        fprintf(stderr, "tunes-lifeline: kevent: %s\n", strerror(errno));
        return stop_group(kq, fd, child);
    }

    for (;;) {
        struct kevent ev;
        int n = kevent(kq, NULL, 0, &ev, 1, NULL);
        if (n < 0) {
            if (errno == EINTR) continue;
            return stop_group(kq, fd, child);
        }
        if (n == 0) continue;
        if (ev.filter == EVFILT_PROC) {
            int status;
            while (waitpid(child, &status, 0) < 0) {
                if (errno != EINTR) return 1;
            }
            kill(-child, SIGKILL);
            return status_code(status);
        }
        if (ev.filter == EVFILT_SIGNAL) return stop_group(kq, fd, child);
        if (ev.filter == EVFILT_READ) {
            char buf[256];
            ssize_t got = read(fd, buf, sizeof buf);
            if (got == 0 || (got < 0 && errno != EINTR && errno != EAGAIN)) {
                return stop_group(kq, fd, child);
            }
        }
    }
}
