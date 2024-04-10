#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/mount.h>
#include <stdio.h>
#include <error.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(int argc, char** argv) {
	if (mkdir("/rootfs", 0755) == -1) {
		perror("mkdir /rootfs failed");
		return 1;
	}
	if (mknod("/dev/sda", 0644 | S_IFBLK, makedev(8, 0)) == -1) {
		perror("mknod /dev/sda failed");
		return 1;
	}
	if (mount("/dev/sda", "/rootfs", "ext3", MS_NOATIME | MS_RDONLY, NULL) == -1) {
		perror("mount failed");
		return 1;
	}

	if (chdir("/rootfs") == -1) {
		perror("chdir /rootfs failed");
		return 1;
	}

	if (mount(".", "/", NULL, MS_MOVE, NULL) == -1) {
		perror("mount move failed");
		return 1;
	}

	if (chroot(".") == -1) {
		perror("chroot failed");
		return 1;
	}

	if (chdir("/") == -1) {
		perror("chdir / failed");
		return 1;
	}

	char *args[2] = {"/init", NULL};
	execv(args[0], &args[0]);
	perror("execv /init failed");

	args[0] = "/bin/bash";
	execv(args[0], &args[0]);
	perror("execv /bin/bash failed");
	return 1;
}