#define _GNU_SOURCE
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <linux/vm_sockets.h>

char buf[65536];
int vfd;

int vsockConnect() {
	struct sockaddr_vm sa = {
		.svm_family = AF_VSOCK,
		.svm_cid = 2,
		.svm_port = 130
	};
	vfd = socket(AF_VSOCK, SOCK_STREAM, 0);
	if (vfd < 0) {
		perror("socket failed");
		return 1;
	}

	if (connect(vfd, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
		perror("connect failed");
		close(vfd);
		return 2;
	}
	return 0;
}

int vsockAccept() {
	struct sockaddr_vm sa = {
		.svm_family = AF_VSOCK,
		.svm_cid = -1,
		.svm_port = 130
	};
	vfd = socket(AF_VSOCK, SOCK_STREAM, 0);
	if (vfd < 0) {
		perror("socket failed");
		return 1;
	}

	if (bind(vfd, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
		perror("bind failed");
		return 2;
	}

	if (listen(vfd, 1) != 0) {
		perror("listen failed");
		return 3;
	}

	int r = accept(vfd, NULL, 0);
	if (r == -1) {
		perror("accept failed");
		return 4;
	}
	close(vfd);
	vfd = r;

	return 0;
}

int r;
int len;
int pid;
int term = 0;
char* logName;
int tx = 0;
int rx = 0;
int bridge(int in, int out) {
	while (1) {
		r = read(in, buf, sizeof(buf));
		if (r < 0) {
			fprintf(stderr, "%s: read: %s\n", logName, strerror(errno));
			return 3;
		}
		if (r == 0) {
			fprintf(stderr, "%s: disconnected\n", logName);
			return 4;
		}
		rx += r;
		len = r;
		r = write(out, buf, len);
		if (r < 0) {
			fprintf(stderr, "%s: write: %s\n", logName, strerror(errno));
			return 5;
		}
		if (r != len) {
			fprintf(stderr, "%s: short write %d <> %d\n", logName, r, len);
			return 6;
		}
		tx += r;
	}
}

int ready = 0;
int input = -1;
void signalHandler(int signo) {
	if (signo == SIGUSR1) {
		ready = 1;
	} else
	if (signo == SIGHUP) {
		close(input);
	}
}


int main(int argc, char **argv) {
	if (argc > 1) r = vsockAccept(); else r = vsockConnect();
	if (r) return r;
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("connected\n");

	logName = "V->0";
	signal(SIGUSR1, signalHandler);
	pid = fork();
	if (pid == -1) {
		fprintf(stderr, "fork: %s\n", strerror(errno));
		return 1;
	}
	if (pid) {
		close(0);
		input = vfd;
		signal(SIGHUP, signalHandler);
		kill(pid, SIGUSR1);
		while (1) {
			sleep(1);
			if (ready) break;
		}
		r = bridge(vfd, 1);
		fprintf(stderr, "%s: RX %d, TX: %d\n", logName, rx, tx);
		close(vfd);
		close(1);
		int status;
		int wr = waitpid(pid, &status, 0);
		fprintf(stderr, "%s: %d done with %d [%d]\n", logName, pid, status, wr);
	} else {
		pid = getppid();
		close(1);
		logName = "I=>V";
		input = 0;
		signal(SIGHUP, signalHandler);
		kill(pid, SIGUSR1);
		while (1) {
			if (ready) break;
			sleep(1);
		}
		r = bridge(0, vfd);
		fprintf(stderr, "%s: RX %d, TX: %d\n", logName, rx, tx);
		close(0);
		close(vfd);
	}
	kill(pid, SIGHUP);
	return r;
}

