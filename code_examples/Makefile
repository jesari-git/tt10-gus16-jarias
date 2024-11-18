all:	bin lst

bin:	hello.bin ansitris.bin mandelSDL.bin pwm.bin ram.bin debug.bin
hex:	hello.hex ansitris.hex mandelSDL.hex pwm.hex ram.hex debug.hex
lst:	hello.lst ansitris.lst mandelSDL.lst pwm.lst ram.lst debug.lst

%.hex : %.asm
	../util6/gus6asm -o $@ $<

%.lst : %.asm
	../util6/gus6asm -l $@ $<

%.bin : %.hex
	./h2bin $< $@
	cp $@ ..
	cp $@ ../p

h2bin:	h2bin.c
	gcc -O2 -w -o $@ $<

clean:
	rm -f *.bin *.lst *.hex
	
