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
inicio:	ldi		r1,0x80
		ldpc	r0
		word	0x1234
l0:		st		(r1),r0
		addi	r1,1
		cmpi	r1,0x84
		jnz		l0

l1:		subi	r1,1
		ld		r2,(r1)
		cmpi	r1,0x80
		jnz		l1
		jr		inicio
		
endcode:


