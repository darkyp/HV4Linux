#include "includes.h"

char buffer[65536];
char* logDesc;
int cfd;
char** childArgs;

void _log(const char* format, ...) {
	flockfile(stdout);
	printf("%s: ", logDesc);
	va_list args;
	va_start(args, format);
	vprintf(format, args);
	va_end(args);
	printf("\n");
	funlockfile(stdout);
}

void _error(const char* msg) {
	printf("%s: %s: %s\n", logDesc, msg, strerror(errno));
}

