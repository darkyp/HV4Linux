#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/select.h>
#include <linux/vm_sockets.h>

char buffer[65536];
fd_set rfd;
struct timeval to = { .tv_usec = 0};
int fd = 0;
int vfd = 0;

int process(char *hostAdapterName) {
	struct sockaddr_vm sa = {
		.svm_family = AF_VSOCK,
		.svm_cid = 2,
		.svm_port = 130
	};
	vfd = socket(AF_VSOCK, SOCK_STREAM, 0);
	if (vfd < 0) {
		printf("socket failed\n");
		return -1;
	}

	if (connect(vfd, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
		printf("connect failed\n");
		close(vfd);
		return 1;
	}
	printf("connected\n");

	int len = snprintf(buffer, sizeof(buffer), "connect %s\n", hostAdapterName);
	if (send(vfd, buffer, len, 0) != len) {
		printf("send failed\n");
		return 1;
	}
	int pos = 0;
	char c;
	while (1) {
		if (recv(vfd, &c, 1, 0) != 1) {
			printf("recv failed\n");
			return 1;
		}
		if (c == 0x0d) continue;
		if (c == 0x0a) break;
		buffer[pos++] = c;
		if (pos == sizeof(buffer) - 1) {
			printf("buffer overflow\n");
		}
	}

	buffer[pos++] = 0;
	if (strcmp(buffer, "OK")) {
		printf("Error: %s\n", buffer);
		return 1;
	}
	printf("started\n");

	while (1) {
		to.tv_sec = 1;
		FD_ZERO(&rfd);
		FD_SET(fd, &rfd);
		FD_SET(vfd, &rfd);
		int n = select(vfd + 1, &rfd, NULL, NULL, &to);
		if (n == 0) continue;
		if (n < 0) {
			printf("Select failed\n");
			return -1;
		}
		if (FD_ISSET(fd, &rfd)) {
			len = read(fd, buffer, sizeof(buffer));
			if (len <= 0) {
				printf("tap read failed\n");
				return -1;
			}
			//printf("Read %d\n", len);
			write(vfd, &len, 4);
			int r = write(vfd, buffer, len);
			if (r != len) {
				printf("vsock write failed\n");
				return 1;
			}
		}
		if (FD_ISSET(vfd, &rfd)) {
			int pktlen;
			len = read(vfd, &pktlen, 4);
			if (len != 4) {
				printf("vsock read failed\n");
				return 1;
			}
			if (pktlen > 65536) {
				printf("vsock too much data %d\n", pktlen);
				return 1;
			}
			len = read(vfd, buffer, pktlen);
			if (len != pktlen) {
				printf("vsock shortread\n");
				return 1;
			}
			//printf("vsock read %d\n", pktlen);
			write(fd, buffer, pktlen);
		}
	}
}

int main(int argc, char **argv) {
	if (argc != 3) {
		printf("Usage: %s host_adapter_name local_adapter_name\n", argv[0]);
		return 1;
	}
	fd = open("/dev/net/tun", O_RDWR);
	struct ifreq ifr;

	memset(&ifr, 0, sizeof(ifr));
	ifr.ifr_flags = IFF_TAP | IFF_NO_PI;

	strncpy(ifr.ifr_name, argv[2], IFNAMSIZ);
	if (ioctl(fd, TUNSETIFF, &ifr) == -1) {
		printf("IOCTL failed\n");
		return 1;
	}

	while (1) {
		int r = process(argv[1]);
		printf("process finished with code %d\n", r);
		if (r < 0) break;
		usleep(1000000);
	}
}

