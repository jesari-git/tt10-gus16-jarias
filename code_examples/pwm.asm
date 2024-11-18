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
bvar:
nint:	word	0
phase:	word	0
freq:	word	1225	;440Hz


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

 getch:	ldi		r1,UARTDAT	
 		ld		r0,(r1)		
 		jind	r6			

;----------------------------------------------
; Prints decimal number
; parameters:
;	R0: number tyo print
;	R6: return address (JAL)
 
; returns:
;	R0, R1: modiffied
; retorna: R0 y R1 modificados
; notes:
;	Avoids printing zeroes on the left
;   Stack used for temporary digit storage

prtdec:
		subi	r7,1
		st		(r7),r6

		ldi		r1,0		; end of string mark
		subi	r7,1		; to stack
		st		(r7),r1
prtd0:	ldi		r1,0		; R0=R0/10, R1=remainder
		ldi		r6,16		
prtd1:	add		r0,r0,r0
		adc		r1,r1,r1
		cmpi	r1,10
		jnc		prtd2
		subi	r1,10
		addi	r0,1
prtd2:	subi	r6,1
		jnz		prtd1
		ldi		r6,'0'		; remainder in ASCII goes to stack
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
		org	0x100
irq0:	;jr	RXIRQ
		org	0x104
irq1:	;jr	TXIRQ
		org	0x108
irq2:	;jr	timerIRQ
		org	0x10c
irq3:	jr	PWMIRQ
		org	0x110
irq4:	word	0

PWMIRQ:
		subi	r7,3
		st		(r7),r0
		st		(r7+1),r1
		st		(r7+2),r2
	
		ldi		r2,bvar
		ld		r0,(r2+nint-bvar)
		addi	r0,1
		st		(r2+nint-bvar),r0
		ld		r0,(r2+phase-bvar)
		ld		r1,(r2+freq-bvar)
		add		r0,r0,r1
		st		(r2+phase-bvar),r0
		jpl		il2
		not		r0,r0
il2:	rori	r0,r0,7
		andi	r0,255
		ldi		r1,IOBASE	
		st		(r1+PWM-IOBASE),r0
		
iend:	ld		r0,(r7)
		ld		r1,(r7+1)
		ld		r2,(r7+2)
		addi	r7,3
		reti


;-------------------------------------------------------------------
;
;		MAIN
;
;-------------------------------------------------------------------
pstart:	
start:	
		ldpc	r7
		word	0x0000			; Stack 
	
		ldpc	r0
		word	txt
		jal		putsle
		
		; enable PWM IRQ
		ldi		r1,IOBASE
		ld		r0,(r1)
		ori		r0,0x8
		st		(r1),r0

		jr		.

;bu0:	ld		r2,(r1+PFLAGS-IOBASE)
;		andi	r2,0x10
;		jz		bu0
;		st		(r1+PWM-IOBASE),r0
;		addi	r0,1
;
;		jr		bu0	
		

txt:	asczle "\nPruebas PWM\n"

fnotas:	word	523*65536/23529	; 523.251 Hz DO
		word	587*65536/23529	; 587,330 Hz RE
		word	659*65536/23529	; 659,255 Hz MI
		word	698*65536/23529	; 698,456 Hz FA
		word	784*65536/23529	; 783,991 Hz SOL
		word	880*65536/23529	; 880.000 Hz LA
		word	988*65536/23529	; 987,767 Hz SI
		word	1046*65536/23529	; 1046,50 Hz DO
		word	0		; 0Hz (silencio)
		
; Melodias: Cada nota consta de 4 bits de duración (MSB)
; y de 4 bits de selección de nota (LSB) 0=DO, 1=RE, ...
; La melodía termina en 0
mustab:	word	0x10
		word	0x11
		word	0x22,
		word	0x14
		word	0x18,
		word	0x34,
		word	0x15,
		word	0x24,
		word	0x22,
		word	0x30,
		word	0x11,
		word	0x12,
		word	0x18,
		word	0x22,
		word	0x21,
		word	0x20,
		word	0x51,
		word	0x18,
		word	0x10,
		word	0x11,
		word	0x22,
		word	0x14,
		word	0x18,
		word	0x34,
		word	0x15,
		word	0x24,
		word	0x22,
		word	0x30,
		word	0x11,
		word	0x12,
		word	0x18,
		word	0x22,
		word	0x11,
		word	0x18,
		word	0x21,
		word	0x60,
		word	0x28,
		word	0x33,
		word	0x18,
		word	0x43,
		word	0x15,
		word	0x18,
		word	0x35,
		word	0x18,
		word	0x25,
		word	0x34,
		word	0x15,
		word	0x24,
		word	0x22,
		word	0x51,
		word	0x18,
		word	0x10,
		word	0x11,
		word	0x22,
		word	0x14,
		word	0x18,
		word	0x34,
		word	0x15,
		word	0x24,
		word	0x22,
		word	0x30,
		word	0x11,
		word	0x12,
		word	0x18,
		word	0x22,
		word	0x11,
		word	0x18,
		word	0x21,
		word	0x50,
		word	0
		
pend:
;-------------------------------------------------------------------
; Variables
;-------------------------------------------------------------------

	


