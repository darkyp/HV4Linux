all: /bin/vsockshell

/bin/vsockshell: vsockshell.c child.c common.c vsock.c
	gcc vsockshell.c child.c common.c vsock.c term.c -o /bin/vsockshell

