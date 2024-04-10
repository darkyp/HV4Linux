#include "common.h"

int processChild() {
	int old = dup(1);
	stdout = fdopen(old, "w");
	setlinebuf(stdout);
	if (setsid() == -1) {
		_error("setsid failed");
		return 1;
	}
	if (dup2(cfd, 0) < 0) {
		_error("Failed to dup2 to 0");
		return 1;
	}
	if (dup2(cfd, 1) < 0) {
		_error("Failed to dup2 to 1");
		return 1;
	}
	if (dup2(cfd, 2) < 0) {
		_error("Failed to dup2 to 2");
		return 1;
	}
	_log("starting shell");
	if (execv(childArgs[0], &childArgs[0]) < 0) {
		_error("Failed to start shell");
	}
}

