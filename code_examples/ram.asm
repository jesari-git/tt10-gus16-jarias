;---------------------------------------------------------------------
; Find the amount of attached RAM and check it
;  RAM under 0x100 has to be working for this program to run
;  J. Arias (2024)
;---------------------------------------------------------------------
; Programming Conventions:
; Strict:
; - Core revision 6 instruction set
; - R7 is the Stack Pointer	(software)
; - R6 holds the return address for subroutines (JAL)
; - Full-descending Stack
; Loose guidelines:
; - R0, R1, R2 are used for arguments / results
;              Values may change on subroutine calls
; - R3, R4, R5 are used for local variables
;              Values are preserved on subroutine calls
;---------------------------------------------------------------------
;---------------------------------------------------------------------
;----------- I/O MAP  -----------

IOBASE=		0x20
IRQEN=		0x20
PFLAGS=		0x21
PWM=		0x21
UARTDAT=	0x22
TIMER=		0x23

;--------- Interrupt enable --------
IRQRXEN=	1
IRQTXEN=	2
IRQTIMEN=	4
IRQHDEEN=	8
IRQVDEEN=	16
;--------- PFLAGS register bits -----------
UARTDV=		1		; Data valid (UART RX)
UARTRDY=	2		; Transmitter ready (UART TX)
UARTOVER=	4		; RX overrun Error
UARTFER=	8		; RX Frame Error
HDE=		16		; Horizontal display enable
VDE=		32		; Vertical display enable
TIMOV=		0x8000	; Timer overflow (sign bit)

;--------------------------------------
;------- HEADER for bootloader --------
;--------------------------------------

		org		0x40-4
		
		word	0x4CFF			; mark
		word	pinit			; destination address
		word	pend-pinit		; size (words)
		word	pstart			; execution address

;--------------------------------------
;------------- CODE -----------------
;--------------------------------------
pinit:

;------------------------------------------------------------------------
; fast address variables (single LDI for address loading)
;------------------------------------------------------------------------
		org		0x40

;-------------------------------------------------------------------
; I/O subroutines
;-------------------------------------------------------------------

;------------------------------------------------------------
; Prints ASCIIZ (16-bit packed, little endian) string on UART 
; parameters:
;	R0: pointer to string
;	R6: return address (JAL)
; returs:
; 	R0-R2: modified

putsle:	ldi		r2,UARTDAT
putsle1:
		ld		r1,(r0)
		andi	r1,0xff
		jz		putsle3
		st		(r2),r1
		
		ld		r1,(r0)
		rori	r1,r1,8
		andi	r1,0xff
		jz		putsle3
		st		(r2),r1
		addi	r0,1
		jr		putsle1

putsle3:
		jind	r6
;----------------------------------------------
; Sends character to UART
; parameters:
;	R0: character to send
;	R6: return address (JAL)
; returns:
; 	R1: modiffied
; notes: CPU clock stops if UART not ready for transmission

putch:	ldi		r1,UARTDAT
		st		(r1),r0		
		jind	r6			

;----------------------------------------------
; Receives character from UART
; parameters:
;	R6: return address (JAL)
; returns:
;	R0: reveived char
; 	R1: modiffied
; notes: CPU clock stops until a character is received

; getch:	ldi		r1,UARTDAT	
; 		ld		r0,(r1)		
; 		jind	r6			

;----------------------------------------------
; Prints decimal number (or hex, octal,...)
; parameters:
;	R0: number to print
;   R2: base
;	R6: return address (JAL)
 
; returns:
;	R0, R1: modiffied
; notes:
;	Avoids printing zeroes on the left
;   Stack used for temporary digit storage

prtdec:
		subi	r7,1
		st		(r7),r6

		ldi		r1,0		; end of string mark
		subi	r7,1		; to stack
		st		(r7),r1
prtd0:	ldi		r1,0		; R0=R0/R2, R1=remainder
		ldi		r6,16		
prtd1:	add		r0,r0,r0
		adc		r1,r1,r1
		sub		r1,r1,r2
		jnc		prtd2
		addi	r0,1
		jr		prtd5
prtd2:	add		r1,r1,r2
prtd5:	subi	r6,1
		jnz		prtd1
		cmpi	r1,10		; digits over '9' translated to 'A','B'...
		jmi		prtd6
		addi	r1,7
prtd6:	ldi		r6,'0'		; remainder in ASCII goes to stack
		add		r1,r1,r6
		subi	r7,1
		st		(r7),r1
		or		r0,r0,r0	; repeat until zero
		jnz		prtd0

prtd3:	ld		r0,(r7)		; retrieve character from stack
		jz		prtd9		; end of string?
		addi	r7,1
		jal		putch
		jr		prtd3

prtd9:	addi	r7,1
		ld		r6,(r7)
		addi	r7,1
		jind	r6



;-------------------------------------------------------------------
; INTERRUPTS
;-------------------------------------------------------------------
;		org	0x100
;irq0:	;jr	RXIRQ
;		org	0x104
;irq1:	;jr	TXIRQ
;		org	0x108
;irq2:	;jr	timerIRQ
;		org	0x10c
;irq3:	;jr	PWMIRQ

;-------------------------------------------------------------------
;
;		MAIN
;
;-------------------------------------------------------------------
pstart:	
start:	
		ldi		r7,0xff		; stack pointer
	
		ldi	r0	txt
		jal		putsle


		ldpc	r5			; test value
		word	0x72A5

		ldpc	r4			; start address
		word	0x100
		or		r3,r4,r4	; same as increment (256)
buc0:	st		(r3),r5
buc:	add		r4,r4,r3
		ld		r0,(r4)
		xor		r0,r0,r5
		jnz		buc
		; found value: check again with inverted bits
		not		r0,r5
		st		(r3),r0
		ld		r1,(r4)
		xor		r0,r1,r0
		jnz		buc0		; fail: the value found was a random coincidence
		
		sub		r0,r4,r3	; Print the amount of RAM
		jnz		pr2			; a value of 0 means 64K
		ldpc	r0
		word	txt64k
		jal		putsle
		jr		pr3
pr2:	ldi		r2,10		; decimal
		jal		prtdec	
pr3:	ldpc	r0
		word	txt2
		jal		putsle

		; Now do an almost whole memory test
		; 1- fill with pseudo-random values
		ldpc	r6			; LFSR poly
		word	0x1021
		sub		r4,r4,r3	; amount of RAM (r3=0x100)
		or		r0,r5,r5	; initial value
pr4:	st		(r3),r0
		add		r0,r0,r0
		jnc		pr5
		xor		r0,r0,r6
pr5:	addi	r3,1
		sub		r1,r4,r3
		jnz		pr4

		; forced error (address=0x1021)
		;ld		r0,(r6)
		;xori	r0,0x30
		;st		(r6),r0
		
		; 2- Check the stored values
		ldpc	r3			; initial address
		word	0x100
		or		r0,r5,r5	; initial value
pr6:	ld		r1,(r3)
		xor		r2,r1,r0
		jnz		perr		
		add		r0,r0,r0
		jnc		pr7
		xor		r0,r0,r6
pr7:	addi	r3,1
		sub		r1,r4,r3
		jnz		pr6		
		ldi		r0,txtok
		jr		pr8
perr:	or		r0,r3,r3	; offending address
		or		r4,r2,r2	; error bitmask
		ldi		r2,16		; Hex values
		jal		prtdec
		ldi		r0,'h'
		jal		putch
		ldi		r0,':'
		jal		putch
		or		r0,r4,r4
		jal		prtdec
		ldi		r0,txterr
pr8:	jal		putsle	
		ldi		r0,txtbak
		jal		putsle

		jr		0		; and jump to bootloader

txt:	asczle	"\nRAM: "
txt64k:	asczle	"65536"
txt2:	asczle	" words\nRAM  "
txtok:	asczle	"OK\n"
txterr:	asczle	"h error\n"
txtbak: asczle  "-back to bootloader-\n"		


pend:

