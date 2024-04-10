#include "includes.h"

extern char* logDesc;
extern int cfd;
extern char buffer[65536];
extern char **childArgs;

extern void _log(const char* format, ...);
extern void _error(const char* msg);
