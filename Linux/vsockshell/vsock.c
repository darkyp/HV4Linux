#include "common.h"

int vfd;
char* cookie;
// whether closing the VSOCK should not terminate
// if pinned != 0 then closing the sock will 
// wait for SIGHUP and an attempt to restart the connection 
// will be made
int pinned = 0; 
int vsockread(void* buf, int len) {
	int r = read(vfd, buf, len);
	if (r == 0) {
		_log("vsock disconnect");
		return 0;
	}
	if (r < 0) {
		_error("vsock read failed");
		return 0;
	}
	if (r != len) {
		_log("vsock short read len");
		return 0;
	}
	return 1;
}

int vsockConnect() {
	struct sockaddr_vm sa = {
		.svm_family = AF_VSOCK,
		.svm_cid = 2,
		.svm_port = 130
	};
	vfd = socket(AF_VSOCK, SOCK_STREAM, 0);
	if (vfd < 0) {
		_error("socket failed");
		return 0;
	}

	if (connect(vfd, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
		_error("connect failed");
		return 0;
	}
	//_log("connected");

	int len;
	len = snprintf(buffer, sizeof(buffer), "newtty %d %d %s\n", getpid(), pinned, cookie);
	if (send(vfd, buffer, len, 0) != len) {
		_error("send failed");
		return 0;
	}
	int pos = 0;
	char c;
	while (1) {
		if (recv(vfd, &c, 1, 0) != 1) {
			_error("recv failed");
			return 0;
		}
		if (c == 0x0d) continue;
		if (c == 0x0a) break;
		buffer[pos++] = c;
		if (pos == sizeof(buffer) - 1) {
			_log("buffer overflow");
			return 0;
		}
	}

	buffer[pos++] = 0;
	if (strcmp(buffer, "OK")) {
		_log("Error: %s", buffer);
		return 0;
	}
	//_log("vsock working");
	return 1;
}

