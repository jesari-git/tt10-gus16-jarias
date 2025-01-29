;---------------------------------------------------------------------
;                   Test GUS16 V6 source code
;                       Jesús Arias (2023)
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Programming Conventions:
; Strict:
; - Core revision 6
; - R7 is the Stack Pointer	(software)
; - R6 holds the return address for subroutines (core parameter)
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
UARTDAT=	0x22
OUTPORT=	0x23

; Offsets relative to IOBASE
OIRQEN=		0
OPFLAGS=	1
OUARTDAT=	2
OOUTPORT=   3

;--------- Interrupts --------
IRQ0EN=		1
;--------- PFLAGS register bits -----------
UARTDV=		1		; Data valid (UART RX)
UARTRDY=	2		; Transmitter busy (UART TX)


;--------------------------------------
;----------- VECTORS -----------------
;-------------------------------------- 

		org 0			; RESET
inicio:	ldi		r7,UARTDAT
buc1:	ld		r0,(r7)
		cmpi	r0,'L'
		jnz		buc1
		st		(r7),r0
		jal		getw
		or		r2,r0,r0		; address
		jal		getw			; + word count
		add		r3,r2,r0		; = last address
		jal		getw
		or		r4,r0,r0		; entry point
		jr		buc2e
		
buc2:	jal		getw
		st		(r2),r0
		addi	r2,1
buc2e:	sub		r0,r3,r2		; compare address
		jnz		buc2
		jind	r4

getw:	ld		r0,(r7)
		ld		r1,(r7)
		rori	r1,r1,8
		or		r0,r0,r1
		jind	r6

endcode:


