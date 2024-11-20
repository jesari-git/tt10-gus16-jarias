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
PWM=		0x21
UARTDAT=	0x22
TIMER=		0x23
GPIO=		0x24


;--------- Interrupts --------
IRQ0EN=		1
;--------- PFLAGS register bits -----------
UARTDV=		1		; Data valid (UART RX)
UARTRDY=	2		; Transmitter busy (UART TX)

;------- Simbolos -------
ANCHO=10
ALTO=20

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
; Espacio para variables de acceso rápido (la dirección se carga con LDI)
;------------------------------------------------------------------------
		org		0x40
vars:
segs:	word	0
nints:	word	(6000000/255)

;-------------------------------------------------------------------
; INTERRUPTS
;-------------------------------------------------------------------
		org	0x100
irq0:	
		org	0x104
irq1:	
		org	0x108
irq2:	
		org	0x10C
		jr		pwmirq
irq3:
		org	0x110
irq4:
		org	0x114
pwmirq:	subi	r7,2
		st		(r7),r0
		st		(r7+1),r1
		ldi		r1,IOBASE
		ldi		r0,0
		st		(r1+PWM-IOBASE),r0
		ldi		r1,vars
		ld		r0,(r1+nints-vars)
		subi	r0,1
		jnz		pwir2
		ld		r0,(r1+segs-vars)
		addi	r0,1
		st		(r1+segs-vars),r0
		ldpc	r0
		word	(6000000/255)
pwir2:	st		(r1+nints-vars),r0		
		ld		r0,(r7)
		ld		r1,(r7+1)
		addi	r7,2
		reti


;-------------------------------------------------------------------
;		INICIO
;-------------------------------------------------------------------


X0VAL=	-4080
Y0VAL=	2400
DELTA=  8
pstart:
		ldpc	r7		; Puntero de Pila al final de RAM
		word	0x7fff	; space for single variable after stack

restart:

		ldpc	r0			; PGM file header
		word	txt1
		jal		putsle	

		; PWM IRQs for time measurement
		ldi		r0,0
		ldi		r1,vars
		st		(r1+segs-vars),r0
		ldi		r1,IOBASE
		ld		r0,(r1+IRQEN-IOBASE)
		ori		r0,8
		st		(r1+IRQEN-IOBASE),r0

		ldpc	r5			; y0 = 1
		word	Y0VAL
		ldpc	r0
		word	600
		st		(r7),r0		; iteraciones y

buc1:	ldpc	r4			; x0 = -2.34
		word	X0VAL	
		ldpc	r3			; iteraciones x		
		word	800
buc2:
		or		r0,r4,r4
		or		r1,r5,r5
		jal		mandel_iter
		jal		putch

		ldi		r0,DELTA		; dx
		add		r4,r4,r0
		subi	r3,1
		jnz		buc2

		ldi		r0,DELTA		; dy
		sub		r5,r5,r0
		ld		r0,(r7)
		subi	r0,1
		st		(r7),r0
		jnz		buc1

mbuc:	
		ldi		r5,nints		; Tiempo en segundos
		ldpc	r0
		word	txt2
		jal		putsle
		ldi		r1,vars
		ld		r0,(r1+segs-vars)
		jal		prtdec
		ldpc	r0
		word	txt3
		jal		putsle

		jr		.

txt1:	asczle "P5\n#Mandelbrot GUS16v6\n800 600\n255\n"
txt2:	asczle "\n# "
txt3:	asczle " seconds\n"

;----------------------------------------------------
; Envía cadena de caracteres empaquetados al terminal
; parámetros:
;	R0: puntero a la cadena de caracteres
;	R6: dirección de retorno
; retorna:
; 	R0-R2: modificados

putsle:	subi	r7,2
		st		(r7),r3
		st		(r7+1),r6
		or		r3,r0,r0
putsle1:
		ld		r0,(r3)
		andi	r0,0xff
		jz		putsle3
		jal		putch
		
		ld		r0,(r3)
		rori	r0,r0,8
		andi	r0,0xff
		jz		putsle3
		jal		putch
		addi	r3,1
		jr		putsle1

putsle3:
		ld		r3,(r7)
		ld		r6,(r7+1)
		addi	r7,2
		jind	r6
;----------------------------------------------
; Envía caracter al terminal
; parámetros:
;	R0: dato a enviar
;	R6: dirección de retorno
; retorna:
; 	R1: modificado

putch:	ldi		r1,IOBASE
		ld		r1,(r1+PFLAGS-IOBASE)
		andi	r1,2
		jz		putch
		ldi		r1,IOBASE
		st		(r1+UARTDAT-IOBASE),r0		; envía dato
		jind	r6			; y retornamos

;----------------------------------------------
; Recibe caracter del terminal
; parámetros:
;	R6: dirección de retorno
; retorna:
;	R0: dato recibido
; 	R1: modificado

 getch:	ldi		r1,IOBASE
		ld		r0,(r1+PFLAGS-IOBASE)
		andi	r0,1
		jz		getch
 		ld		r0,(r1+UARTDAT-IOBASE)		; leemos dato
 		jind	r6			; y retornamos

;----------------------------------------------
; Imprime R0 en decimal
; retorna: R0 y R1 modificados
; usa la pila para el almacenamiento temporal de dígitos

prtdec:
		; prólogo
		subi	r7,1
		st		(r7),r6
		;
		ldi		r1,0		; marca de final de cadena
		subi	r7,1		; a la pila
		st		(r7),r1
prtd0:	ldi		r1,0		; R0=R0/10, R1=resto
		ldi		r6,16		; contador
prtd1:	add		r0,r0,r0
		adc		r1,r1,r1
		cmpi	r1,10
		jnc		prtd2
		subi	r1,10
		addi	r0,1
prtd2:	subi	r6,1
		jnz		prtd1
		ldi		r6,'0'		; resto a la pila
		add		r1,r1,r6
		subi	r7,1
		st		(r7),r1
		or		r0,r0,r0	; hasta que el cociente sea 0
		jnz		prtd0

prtd3:	ld		r0,(r7)		; caracter desde la pila
		jz		prtd9		; final de cadena?
		addi	r7,1
		jal		putch
		jr		prtd3

prtd9:	addi	r7,1
		; epílogo
		ld		r6,(r7)
		addi	r7,1
		jind	r6


;-------------------------------------------------------------------
;		Multiplicación fraccional
; Datos de 16 bits con 11 bits fraccionales val = dato/2048
;		R0 = (R0 * R1) >> 11
;  Nota: el valor de R2 se conserva
;-------------------------------------------------------------------

fmul11:	subi	r7,1
		st		(r7),r6
		or		r6,r0,r0
		jpl		fml2			; Multiplicando (R6) siempre positivo
		neg		r6,r6
		neg		r1,r1
fml2:	ldi		r0,0
		add		r6,r6,r6		; Bit 14 (*8)
		jpl		fml3
		add		r0,r1,r1
		add		r0,r0,r0
		add		r0,r0,r0
fml3:	add		r6,r6,r6		; Bit 13 (*4)
		jpl		fml5
		add		r0,r0,r1
		add		r0,r0,r1
		add		r0,r0,r1
		add		r0,r0,r1
fml5:	add		r6,r6,r6		; Bit 12 (*2)
		jpl		fml7
		add		r0,r0,r1
		add		r0,r0,r1
		jr		fml7

fml4:	shra	r1,r1			; Resto de bits
fml7:	add		r6,r6,r6
		jz		fml6
		jpl		fml4
		add		r0,r0,r1
		jr		fml4
fml6:	ld		r6,(r7)
		addi	r7,1
		jind	r6

;-------------------------------------------------------------------
; Iteración Mandelbrot
;  Calcula Zr = Zr*Zr - Zi*Zi + Cr
;          Zi = 2*Zr*Zi + Ci
;    mientras (Zr*Zr + Zi*Zi)<4
;  Parámetros: R0: Cr, R1: Ci
;  Retorna el nº de iteraciones (max 255)
;-------------------------------------------------------------------

mandel_iter:
		subi	r7,8		; 4 regs + 4 variables
		st		(r7+7),r6
		st		(r7+6),r5
		st		(r7+5),r4
		st		(r7+4),r3


		or		r4,r0,r0	; R4 = Cr
		or		r5,r1,r1	; R5 = Ci

		or		r2,r4,r4	; R2 = Zr = Cr
		or		r3,r5,r5	; R3 = Zi = Ci
		ldi		r0,0		; i = 0
		st		(r7),r0

mitr1:	or		r0,r2,r2	; zri=fmul11(zr,zi);
		or		r1,r3,r3
		jal		fmul11
		add		r0,r0,r0	; zri= 2*zr*zi
		st		(r7+3),r0

		or		r0,r2,r2	; zr2=fmul11(zr,zr);
		or		r1,r2,r2
		jal		fmul11
		st		(r7+1),r0

		or		r0,r3,r3	; zi2=fmul11(zi,zi);
		or		r1,r3,r3
		jal		fmul11
		st		(r7+2),r0

		ld		r1,(r7+1)	; escape: (zr2 + zi2) > (4<<11)
		add		r1,r1,r0
		ldpc	r6
		word	4<<11
		sub		r6,r1,r6
		jc		mitr9

		ld		r1,(r7+1)
		sub		r0,r1,r0
		add		r2,r0,r4	; Zr = Zr2 - Zi2 + Cr

		ld		r0,(r7+3)
		add		r3,r0,r5	; Zi = 2Zri + Ci

		ld		r0,(r7)		; i++
		addi	r0,1
		andi	r0,255		; while (i!=256)
		st		(r7),r0
		jnz		mitr1

mitr9:	ld		r0,(r7)		; return i
		ld		r3,(r7+4)
		ld		r4,(r7+5)
		ld		r5,(r7+6)
		ld		r6,(r7+7)
		addi	r7,8
		jind	r6
pend:

