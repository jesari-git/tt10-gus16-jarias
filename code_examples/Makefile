all:	hello.bin ansitris.bin mandelSDL.bin pwm.bin

%.hex : %.asm
	../util/gus6asm -o $@ $<

%.bin : %.hex
	./h2bin $< $@
	cp $@ ..
	cp $@ ../p

h2bin:	h2bin.c
	gcc -O2 -w -o $@ $<
	
