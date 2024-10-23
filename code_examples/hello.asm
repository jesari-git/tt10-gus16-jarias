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
;----------- HEADER -----------------
;--------------------------------------

		org		0x100-4
		
		word	0x4CFF	; mark
		word	pinit
		word	pend-pinit
		word	pstart

;--------------------------------------
;------------- CODE -----------------
;--------------------------------------
pinit:
pstart:	

		ldi		r7,0

mbuc:	; Bucle principal del programa
		; Imprimimos mensaje "Hello World"
		ldpc	r0		; Imprime cadena de caracteres TXT
		word	txtle
		jal		putsle		

		jind	r7

;----------------------------------------------------
; Envía cadena de caracteres empaquetados al terminal
; parámetros:
;	R0: puntero a la cadena de caracteres
;	R6: dirección de retorno
; retorna:
; 	R0-R2: modificados

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

;---------------------------------------
;------------- CONSTANTES --------------
;---------------------------------------

txtle:	asczle	"\n\n¡¡¡Hola Mundo!!!\n"

;---------------------------------------
;--------------- DATOS -----------------
;---------------------------------------



pend:

