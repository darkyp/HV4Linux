#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
char buf[1024];
char outBuf[1024];
int pos = 0;

void flushOut() {
	if (!pos) return;
	int f = open("/dev/kmsg", O_WRONLY);
	if (f >= 0) {
		outBuf[pos++] = 0x0a;
		write(f, outBuf, pos);
		close(f);
	}
	pos = 0;
}

void processIn(int len) {
	char *p;
	p = buf - 1;
	while (len > 0) {
		len--;
		p++;
		if (*p == 0x0d) continue;
		if (*p == 0x0a) {
			flushOut();
			continue;
		}
		outBuf[pos++] = *p;
		if (pos == 1023) flushOut();
	}
}

int main(int argc, char **argv) {
	while (1) {
		int len = read(0, buf, 1024);
		if (len == -1) break;
		if (len == 0) break;
		processIn(len);
	}
	flushOut();
}