#define _GNU_SOURCE
#include "common.h"
#include "vsock.h"


fd_set rfd;
struct timeval to = { .tv_usec = 0};
int fd;
int vfd = -1;
extern char* cookie;
extern int pinned;
char* logDesc;
char expect = 0;
char* initCmd = NULL;
int term = 0;

extern int processChild();

// from term.c
extern char* scrTitleBuf;
extern char* scrTitle;
extern char* titleBuf;
extern char* title;
extern void processBuf(char *p, int len);

int processMain() {
	int len;
	while (1) {
		to.tv_sec = 1;
		to.tv_usec = 0;
		FD_ZERO(&rfd);
		FD_SET(fd, &rfd);
		if (vfd >= 0) FD_SET(vfd, &rfd);
		int n = select(vfd + 1, &rfd, NULL, NULL, &to);
		if (n == 0) continue;
		if (n < 0) {
			if (errno == EINTR) {
				if (term) return 0;
				if (vfd < 0) {
					_log("Attempt to resume");
					if (!vsockConnect()) {
						if (vfd >= 0) {
							close(vfd);
							vfd = -1;
						}
						continue;
					}
					// Send the title and the screenTitle
					write(vfd, "\x1b[", 2);
					write(vfd, titleBuf, title - titleBuf);
					write(vfd, "\x07", 1);
					write(vfd, "\x1bk", 2);
					write(vfd, scrTitleBuf, scrTitle - scrTitleBuf);
					write(vfd, "\x1b\\", 2);
				}
				continue;
			}
			_error("select failed");
			return 1;
		}
		
		if (FD_ISSET(fd, &rfd)) {
			// Received from shell, forward to network
			len = read(fd, buffer, sizeof(buffer));
			if (len == 0) {
				_log("ptmx disconnected");
				return 2;
			}
			if (len < 0) {
				_error("ptmx read failed");
				return 2;
			}
			if (pinned) {
				// TODO: write to screen buffer so that
				// upon resuming the vsock connection
				// the buffer is sent to the client
				processBuf(buffer, len);
			}
			if (expect) {
				char* p = buffer;
				int n = len;
				while (n) {
					if (*p == expect) {
						write(fd, initCmd, strlen(initCmd));
						expect = 0x0d;
						write(fd, &expect, 1);
						expect = 0;
						break;
					}
					n--;
					p++;
				}
			}
			if (vfd >= 0) {
				int r = write(vfd, buffer, len);
				if (r != len) {
					_log("vsock write failed");
					return 1;
				}
			}
		}
		if (FD_ISSET(vfd, &rfd)) {
			// Received from network, forward to shell
			int pktlen;
			if (!vsockread(&pktlen, 4)) goto vsockerr;
			if (pktlen & 0x40000000) {
				pktlen ^= 0x40000000;
				if (pktlen == 1) pinned = 1; else
				if (pktlen == 2) pinned = 0;
				continue;
			}
			if (pktlen & 0x80000000) {
				pktlen ^= 0x80000000;
				if (pktlen > 1024) {
					_log("bad IOCTL size");
					return 1;
				}
				int cmd;
				if (!vsockread(&cmd, 4)) goto vsockerr;
				if (!vsockread(buffer, pktlen)) goto vsockerr;
				if (ioctl(fd, cmd, buffer) == -1) {
					_error("ioctl failed");
					return 2;
				}
				continue;
			}
			if (pktlen > 65536) {
				_log("bad size");
				return 1;
			}
			if (!vsockread(buffer, pktlen)) goto vsockerr;
			len = write(fd, buffer, pktlen);
			if (len != pktlen) {
				_log("ptmx write failed");
				return 2;
			}
			continue;
			vsockerr:
				if (pinned) {
					if (vfd != -1) {
						close(vfd);
						vfd = -1;
					}
				} else {
					return 1;
				}
		}
	}
}

void sig_handler(int signo) {
	_log("Received signal %d\n", signo);
	if (signo == SIGTERM) {
		term = 1;
	}
}

int main(int argc, char **argv) {
	logDesc = "vsockshell";
	setlinebuf(stdout);
	// default child args
	char* defArgs[2] = {"/bin/bash", NULL};
	childArgs = defArgs;
	char **arg = argv;
	int n = 0;
	cookie = "";
	int detach = 0;
	while (1) {
		if (*arg == NULL) break;
		if (!strcmp("--detach", *arg)) {
			detach = 1;
		} else
		if (!strcmp("--pinned", *arg)) {
			pinned = 1;
		} else
		if (!strcmp("--cookie", *arg)) {
			arg++;
			cookie = *arg;
		} else
		if (!strcmp("--cmd", *arg)) {
			arg++;
			childArgs = arg;
			break;
		} else
		if (!strcmp("--expect", *arg)) {
			arg++;
			expect = **arg;
			arg++;
			initCmd = *arg;
		}
		arg++;
	}
	//_log("started");
	fd = open("/dev/pts/ptmx", O_RDWR);
	if (fd < 0) {
		_error("Failed to open child terminal");
		return 1;
	}
	grantpt(fd);
	unlockpt(fd);
	cfd = open(ptsname(fd), O_RDWR);
	if (cfd < 0) {
		_error("Failed to open child terminal");
		return 1;
	}
	if (!vsockConnect()) return 1;

	int pid;
	
	if (detach) {
		pid = fork();
		if (pid == -1) {
			_error("Failed to fork");
			return 1;
		}
		if (pid > 0) return 0;
	}
	
	pid = fork();
	if (pid == -1) {
		_error("Failed to fork");
		return 1;
	}
	if (pid > 0) {
		close(cfd);
		logDesc = "vsockshell.main";
		signal(SIGHUP, sig_handler);
		int r = processMain();
		return r;
	} else {
		close(fd);
		close(vfd);
		logDesc = "vsockshell.child";
		return processChild();
	}
}

