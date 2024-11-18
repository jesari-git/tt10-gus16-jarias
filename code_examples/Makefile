all:	hello.bin ansitris.bin mandelSDL.bin pwm.bin ram.bin sstep.bin debug.bin pru.bin
hex:	hello.hex ansitris.hex mandelSDL.hex pwm.hex ram.hex sstep.hex

%.hex : %.asm
	../util6/gus6asm -o $@ $<

%.bin : %.hex
	./h2bin $< $@
	cp $@ ..
	cp $@ ../p

h2bin:	h2bin.c
	gcc -O2 -w -o $@ $<
	
