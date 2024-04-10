all: init initrd

init: init.c
	gcc  init.c -o init -static

initrd: init
	echo init | cpio --create --format=newc > initrd.img

