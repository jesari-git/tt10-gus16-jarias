CC = gcc
CFLAGS = -O2 -w

all:	gus6asm gus6dasm gus6emu 


gus6emu:	gus6emu.c opcodes.h
	$(CC) $(CFLAGS) -o $@ gus6emu.c

gus6dasm:	gus6dasm.c opcodes.h
	$(CC) $(CFLAGS) -o $@ gus6dasm.c

gus6asm:	gus6asm.c opcodes.h
	$(CC) $(CFLAGS) -o $@ gus6asm.c
	
clean:
	rm -f *.o *~
	touch *.c

