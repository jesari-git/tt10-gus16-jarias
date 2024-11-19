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
GPO=		0x24

FLAG0=		0x26	; user-mode flags
PC0=		0x27	; user-mode PC

;--------- Interrupt enable --------
IRQRXEN=	1
IRQTXEN=	2
IRQTIMEN=	4
IRQPWMEN=	8
IRQSSTEPEN=	16		; Single-step IRQ
;--------- PFLAGS register bits -----------
UARTDV=		1		; Data valid (UART RX)
UARTRDY=	2		; Transmitter ready (UART TX)
UARTOVER=	4		; RX overrun Error
UARTFER=	8		; RX Frame Error
PWMF=		16		; PWM interrupt
TIMOV=		0x8000	; Timer overflow (sign bit)

;--------------------------------------
;------- HEADER for bootloader --------
;--------------------------------------

		org		0xFC00-4
		
		word	0x4CFF			; mark
		word	pinit			; destination address
		word	pend-pinit		; size (words)
		word	pstart			; execution address

;--------------------------------------
;------------- CODE -----------------
;--------------------------------------
pinit:

;-------------------------------------------------------------------
; INTERRUPTS
;-------------------------------------------------------------------
		
SSTEPIRQ:

JMPIRQ= ~(0x10110-SSTEPIRQ)		; opcode of: JR from 0x110 to here

		subi	r7,7
		st		(r7+1),r1
		st		(r7+3),r3
		st		(r7+4),r4
		st		(r7+5),r5

db00:	ldi		r5,IOBASE
		ldpc	r3
		word	bvar
		
		ld		r4,(r5+PC0-IOBASE)		; R4: PC normal mode
		ld		r1,(r5+PFLAGS-IOBASE)
		andi	r1,0x40					; Ctrl-C flag set?
		jz		db001
		ld		r1,(r5+UARTDAT-IOBASE)	; flush RX
		jr		db002
db001:	ld		r1,(r3+break-bvar)	; if(break==PC) set_trace
		xor		r1,r4,r1			; check for breakpoint
		jnz		db01
db002:	st		(r3+trace-bvar),r5	
db01:		
		ld		r1,(r3+trace-bvar)	; if (!trace) return
		jz		iend2
		st		(r7+0),r0			; save rest of registers
		st		(r7+2),r2
		st		(r7+6),r6
		jpl		db03				; if (trace<0) wait for return (JIND R6)
		ld		r0,(r4)
		ldpc	r2
		JIND R6
		xor		r0,r0,r2
		jnz		iend
		andi	r1,1
		jz		db02
		ld		r1,(r3+rutsp-bvar)	; higher stack level?
		sub		r1,r1,r7
		jpl		iend
db02:	ldi		r1,2
		st		(r3+trace-bvar),r1	; trace positive

db03:	ld		r0,(r5+PFLAGS-IOBASE)
		andi	r0,0x20				; screen dirty?
		jz		db04
		ldpc	r0
		word	msgpause
		jal		putsbe
		ld		r0,(r5+UARTDAT-IOBASE)	; getch

dbupd:	ld		r4,(r5+PC0-IOBASE)
db04:	ldi		r1,0
		st		(r3+ldpcf-bvar),r1	; clear ldpc flag

		ldpc	r0					; clear screen
		word	msgcls ;+2
		jal		putsbe
		
		; Print code @ PC0
		jal		disablk		
		; Print Flags0
		ldpc	r0
		word	msgflg
		jal		putsbe
		ld		r4,(r5+FLAG0-IOBASE)
		rori	r4,r4,4
		ldi		r3,4
		ldpc	r2
		word	flgtbl
db2:	ldi		r0,'_'
		add		r4,r4,r4		
		jnc		db3
		ld		r0,(r2)	
db3:	st		(r5+UARTDAT-IOBASE),r0
		addi	r2,1
		subi	r3,1
		jnz		db2
		
		; Print registers
		ldi		r3,0
db4:	ldpc	r0
		word	msgpos
		jal		putsbe
		ldi		r0,3
		add		r0,r3,r0
		jal		prtdec
		ldpc	r0
		word	msgreg
		jal		putsbe
		ldi		r0,'0'
		add		r0,r3,r0
		st		(r5+UARTDAT-IOBASE),r0
		ldi		r0,':'
		st		(r5+UARTDAT-IOBASE),r0
		ldi		r0,' '
		st		(r5+UARTDAT-IOBASE),r0
		or		r0,r3,r3
		add		r0,r0,r7
		ld		r0,(r0)
		cmpi	r3,7
		jnz		db5
		ldi		r0,7
		add		r0,r0,r7
db5:	jal		prthex
		addi	r3,1
		cmpi	r3,8
		jnz		db4

		; Print BRK
		ldpc	r0
		word	msgbrk
		jal		putsbe
		ldpc	r0
		word	bvar
		ld		r0,(r0+break-bvar)
		jal		prthex
		ldpc	r0
		word	msgebrk
dbprom:	jal		putsbe
		;------------------
		; User commands
		;------------------
dbkey:	ld		r0,(r5+UARTDAT-IOBASE)
		cmpi	r0,'c'		; continue
		jnz		db10
		ld		r0,(r5)		; disable single-step IRQ
		andi	r0,0xEF
		st		(r5),r0
db51:	ldpc	r0
		word	msgcls
		jal		putsbe
		st		(r5+FLAG0-IOBASE),r0	; clear dirty
		jr		iend
		
db10:	cmpi	r0,'n'		; break on next instr
		jnz		db20
		ld		r0,(r5+PC0-IOBASE)
		addi	r0,1
		ldpc	r3
		word	bvar
		st		(r3+break-bvar),r0
db15:	ldi		r0,0
		st		(r3+trace-bvar),r0
		jr		db51

db20:	cmpi	r0,'e'		; Exec with breakpoint (slow)
		jnz		db30
		ldpc	r3
		word	bvar
		jr		db15
		
db30:	cmpi	r0,'r'		; Exec until return
		jnz		db35
		ldi		r0,1
db31:	ldpc	r3
		word	bvar
		rori	r0,r0,1
		st		(r3+trace-bvar),r0	; trace<0 means stop on returns
		st		(r3+rutsp-bvar),r7	; stack level
		jr		db51
db35:	cmpi	r0,'R'	; Exec until return (higher stack)
		jnz		db40
		ldi		r0,3	; trace<0 && (trace&1) => stop on returns if stack is higher
		jr		db31

db40:	cmpi	r0,'s'		; Step
		jz		iend0
		;cmpi	r0,'\n'
		;jz		db00
		cmpi	r0,' '
		jz		db00
		
		cmpi	r0,'d'		; disassemble
		jnz		db50
		jal		gethex
		or		r4,r0,r0
		jal		disablk
db45:	ldpc	r3
		word	bvar
		st		(r3+caddr-bvar),r4
db44:	ldpc	r0
		word	msgebrk+4
		jr		dbprom
			
db50:	cmpi	r0,'b'		; set breakpoint
		jnz		db60
		jal		gethex	
		ldpc	r3
		word	bvar
		st		(r3+break-bvar),r0
		jr		dbupd

db60:	cmpi	r0,'m'		; dump memory
		jnz		db70
		jal		gethex
		or		r4,r0,r0
		jal		mdump
		jr		db45
		
db70:	cmpi	r0,'h'		; print help
		jnz		dbkey
		ldpc	r0
		word	msghelp
		jal		putsbe
		jr		db44

iend0:	st		(r5+FLAG0-IOBASE),r0	; clear dirty
iend:	ld		r0,(r7+0)
		ld		r2,(r7+2)
		ld		r6,(r7+6)

iend2:	ld		r1,(r7+1)
		ld		r3,(r7+3)
		ld		r4,(r7+4)
		ld		r5,(r7+5)
		addi	r7,7
		reti

msgcls:	asczbe "\e[2J\e[H"
msgflg:	asczbe "\e[1;32H<- PC\e[1;39HFlags: "
flgtbl: word 'V'
		word 'N'
		word 'C'
		word 'Z'
msgpos:	asczbe "\e["
msgreg:	asczbe ";42HR"
msgbrk:	asczbe "\e[13;39HBreak: "
msgebrk:	asczbe "\e[22;01HhcesnrRbdm>"
msgpause:	asczbe "<paused>"

;------------------------------------------------------
; dissasemble 20 instr at (R4)
disablk:
		subi	r7,1
		st		(r7),r6

		ldi		r3,20
disa1:	or		r0,r4,r4
		jal		prthex
		ldi		r0,':'
		st		(r5+UARTDAT-IOBASE),r0
		ldi		r0,' '
		st		(r5+UARTDAT-IOBASE),r0
		ld		r0,(r4)
		jal		prthex
		ldpc	r1
		word	ldpcf
		ld		r1,(r1)
		jnz		disa2
		jal		disassemble
		jr		disa3
disa2:	ldi		r0,0
		st		(r1),r0
disa3:	ldi		r0,'\n'
		st		(r5+UARTDAT-IOBASE),r0
		addi	r4,1
		subi	r3,1
		jnz		disa1

		ld		r6,(r7)
		addi	r7,1
		jind	r6

;------------------------------------------------------
; dissasemble single instruction at (R4)
disassemble:
		subi	r7,4
		st		(r7+0),r0
		st		(r7+1),r1
		st		(r7+2),r5
		st		(r7+3),r6
		
		ldi		r0,0
		ldpc	r1
		word	ldpcf
		st		(r1),r0
		ldi		r0,' '
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,12
		andi	r0,0xf
		cmpi	r0,7
		jmi		dis1
		addi	r0,28-7
		jal		prnemo
		ld		r1,(r4)
		ldpc	r5
		word	0xfff
		and		r5,r5,r1
		rori	r5,r5,12
		jpl		dis01
		ori		r5,0xf
dis01:	rori	r5,r5,4	
		add		r0,r5,r4
		addi	r0,1
		jal		prthex
		jr		dis99

dis1:	cmpi	r0,6
		jnz		dis2
		ld		r1,(r4)
		rori	r0,r1,11
		andi	r0,1
		addi	r0,26
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,12
		jmi		dis11
		rori	r0,r0,12	; LD
		jal		prreg
		ldi		r0,','
		jal		putch
		ldi		r0,'('
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,5
		jal		prreg
		ld		r0,(r4)
		andi	r0,31
		jz		dis13
		ldi		r0,'+'
		jal		putch
		ld		r0,(r4)
		andi	r0,31
		jal		prtdec
dis13:	ldi		r0,')'
		jal		putch
		jr		dis99
dis11:	ldi		r0,'('	; ST
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,5
		jal		prreg
		ld		r0,(r4)
		andi	r0,31
		jz		dis12
		ldi		r0,'+'
		jal		putch
		ld		r0,(r4)
		andi	r0,31
		jal		prtdec		
dis12:	ldi		r0,')'
		jal		putch
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		jr		dis99
		
dis2:	cmpi	r0,5
		jnz		dis3
		ld		r0,(r4)
		rori	r1,r0,3
		andi	r1,0x1c
		rori	r2,r0,6
		andi	r2,0x20
		andi	r0,3
		or		r0,r0,r1
		or		r0,r0,r2
		cmpi	r0,0x3f
		jnz		dis20
		ldi		r0,25		; RETI
		jal		prnemo
		jr		dis99
dis20:	cmpi	r0,0x3E
		jnz		dis21
		ldi		r0,24		; JIND
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,2
		jal		prreg
		jr		dis99
dis21:	cmpi	r0,0x3C
		jnz		dis22
		ldi		r0,23		; LDPC
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		ldpc	r0
		word	ldpcf
		st		(r0),r0
		jr		dis99
dis22:	cmpi	r0,0x30
		jmi		dis23
		subi	r0,48-18	; RORC - NEG
		cmpi	r0,22
		jmi		dis221
		subi	r0,1
dis221:	jal		prnemo	
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,2
		jal		prreg	
		jr		dis99
dis23:	rori	r0,r0,4
		andi	r0,3
		cmpi	r0,2
		jnz		dis24
		ldi		r0,17		; RORI
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,2
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r1,r0,3
		andi	r0,3
		andi	r1,0xc
		or		r0,r0,r1
		ldi		r2,10
		jal		prtdec
		jr		dis99
dis24:	; LDI
dis3:	ld		r0,(r4)		; immediate instrs
		rori	r0,r0,11
		andi	r0,0xF
		subi	r0,2
		jmi		dis4
		addi	r0,8
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		andi	r0,0xff
		ldi		r2,10
		jal		prthex8
		jr		dis99

dis4:	ld		r0,(r4)		; 3-operand instrs
		rori	r1,r0,9
		andi	r0,3
		andi	r1,4
		or		r0,r0,r1
		jal		prnemo
		ld		r0,(r4)
		rori	r0,r0,8
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,5
		jal		prreg
		ldi		r0,','
		jal		putch
		ld		r0,(r4)
		rori	r0,r0,2
		jal		prreg
		

dis99:	
		ld		r0,(r7+0)
		ld		r1,(r7+1)
		ld		r5,(r7+2)
		ld		r6,(r7+3)
		addi	r7,4
		jind	r6
		

prnemo:	ldi		r1,UARTDAT
		ldi		r5,' '
		st		(r1),r5
		st		(r1),r5		
		ldpc	r5
		word	nmtab
		add		r0,r0,r0
		add		r5,r5,r0
		ld		r0,(r5)
		rori	r0,r0,8
		st		(r1),r0
		rori	r0,r0,8
		st		(r1),r0
		ld		r0,(r5+1)
		rori	r0,r0,8
		st		(r1),r0
		rori	r0,r0,8
		st		(r1),r0
		ldi		r5,' '
		st		(r1),r5
		st		(r1),r5
		jind	r6

prreg:	ldi		r1,UARTDAT
		ldi		r2,'R'
		st		(r1),r2
		andi	r0,7
		addi	r0,'0'
		st		(r1),r0
		jind	r6
		

				
nmtab:	word ('A'<<8)|'D'	; 0: ADD
		word ('D'<<8)|' '
		word ('S'<<8)|'U'	; 1: SUB
		word ('B'<<8)|' '				
		word ('A'<<8)|'D'	; 2: ADC
		word ('C'<<8)|' '				
		word ('S'<<8)|'B'	; 3: SBC
		word ('C'<<8)|' '				
		word ('A'<<8)|'N'	; 4: AND
		word ('D'<<8)|' '				
		word ('O'<<8)|'R'	; 5: OR
		word (' '<<8)|' '				
		word ('X'<<8)|'O'	; 6: XOR
		word ('R'<<8)|' '				
		word ('B'<<8)|'I'	; 7: BIC
		word ('C'<<8)|' '				
		word ('A'<<8)|'D'	; 8: ADDI
		word ('D'<<8)|'I'				
		word ('S'<<8)|'U'	; 9: SUBI
		word ('B'<<8)|'I'				
		word ('A'<<8)|'D'	; 10: ADCI
		word ('C'<<8)|'I'				
		word ('S'<<8)|'B'	; 11: SBCI
		word ('C'<<8)|'I'				
		word ('A'<<8)|'N'	; 12: ANDI
		word ('D'<<8)|'I'				
		word ('O'<<8)|'R'	; 13: ORI
		word ('I'<<8)|' '				
		word ('X'<<8)|'O'	; 14: XORI
		word ('R'<<8)|'I'				
		word ('C'<<8)|'M'	; 15: CMPI
		word ('P'<<8)|'I'				
		word ('L'<<8)|'D'	; 16: LDI
		word ('I'<<8)|' '				
		word ('R'<<8)|'O'	; 17: RORI
		word ('R'<<8)|'I'				
		word ('R'<<8)|'O'	; 18: RORC
		word ('R'<<8)|'C'				
		word ('S'<<8)|'H'	; 19: SHR
		word ('R'<<8)|' '				
		word ('S'<<8)|'H'	; 20: SHRA
		word ('R'<<8)|'A'				
		word ('N'<<8)|'O'	; 21: NOT
		word ('T'<<8)|' '				
		word ('N'<<8)|'E'	; 22: NEG
		word ('G'<<8)|' '				
		word ('L'<<8)|'D'	; 23: LDPC
		word ('P'<<8)|'C'				
		word ('J'<<8)|'I'	; 24: JIND
		word ('N'<<8)|'D'				
		word ('R'<<8)|'E'	; 25: RETI
		word ('T'<<8)|'I'				
		word ('L'<<8)|'D'	; 26: LD
		word (' '<<8)|' '				
		word ('S'<<8)|'T'	; 27: ST
		word (' '<<8)|' '				
		word ('J'<<8)|'A'	; 28: JAL
		word ('L'<<8)|' '				
		word ('J'<<8)|'Z'	; 29: JZ
		word (' '<<8)|' '				
		word ('J'<<8)|'N'	; 30: JNZ
		word ('Z'<<8)|' '				
		word ('J'<<8)|'C'	; 31: JC
		word (' '<<8)|' '				
		word ('J'<<8)|'N'	; 32: JNC
		word ('C'<<8)|' '				
		word ('J'<<8)|'M'	; 33: JMI
		word ('I'<<8)|' '				
		word ('J'<<8)|'P'	; 34: JPL
		word ('L'<<8)|' '				
		word ('J'<<8)|'V'	; 35: JV
		word (' '<<8)|' '		
		word ('J'<<8)|'R'	; 36: JR
		word (' '<<8)|' '				

;-------------------------------------------------------------------
; 	get an hex value from UART, with editing
;     caddr holds the initial value
;     R0 contents are printed as char in front to the hex value
;     R0 returns the edited value
;   hex digits are shifted to the left until an new-line is received
gethex:	subi	r7,1
		st		(r7),r6
		jal		putch
		ldi		r0,' '
		jal		putch
		ldpc	r3
		word	bvar
		ld		r0,(r3+caddr-bvar)
ghex1:	jal		prthex
		ld		r1,(r5+UARTDAT-IOBASE)
		cmpi	r1,'\n'
		jz		ghex95
		cmpi	r1,'0'
		jmi		ghex9
		cmpi	r1,'a'-1
		jmi		ghex2
		subi	r1,32
ghex2:	cmpi	r1,'9'+1
		jmi		ghex3
		cmpi	r1,'A'-1
		jmi		ghex9
		cmpi	r1,'F'+1
		jpl		ghex9
		subi	r1,7
ghex3:	subi	r1,'0'
		rori	r0,r0,12
		ori		r0,0xf
		xori	r0,0xf
		add		r0,r0,r1
		
ghex9:	ldi		r1,'\b'
		st		(r5+UARTDAT-IOBASE),r1
		st		(r5+UARTDAT-IOBASE),r1
		st		(r5+UARTDAT-IOBASE),r1
		st		(r5+UARTDAT-IOBASE),r1
		jr		ghex1			

ghex95:	st		(r5+UARTDAT-IOBASE),r1
		ld		r6,(r7)
		addi	r7,1
		jind	r6
;-------------------------------------------------------------------
; hex dump of the memory block pointed by R4
mdump:	subi	r7,1
		st		(r7),r6
		ldi		r3,16
md1:	or		r0,r4,r4
		jal		prthex			; address
		ldi		r1,':'
		st		(r5+UARTDAT-IOBASE),r1
		ldi		r1,' '
		st		(r5+UARTDAT-IOBASE),r1
		ldi		r2,8
md2:	ld		r0,(r4)			; data
		jal		prthex
		ldi		r1,' '
		st		(r5+UARTDAT-IOBASE),r1
		addi	r4,1
		subi	r2,1
		jnz		md2
		ldi		r1,' '
		st		(r5+UARTDAT-IOBASE),r1
		st		(r5+UARTDAT-IOBASE),r1
		
		subi	r4,8
		ldi		r2,8
md3:	ld		r0,(r4)
		rori	r1,r0,8
		jal		goodch
		st		(r5+UARTDAT-IOBASE),r1
		or		r1,r0,r0
		jal		goodch
		st		(r5+UARTDAT-IOBASE),r1
		ldi		r1,' '
		st		(r5+UARTDAT-IOBASE),r1
		addi	r4,1
		subi	r2,1
		jnz		md3
		ldi		r1,'\n'
		st		(r5+UARTDAT-IOBASE),r1
		subi	r3,1
		jnz		md1
		
		ld		r6,(r7)
		addi	r7,1
		jind	r6

;--------------------------------------
; 		forces a good ASCII char in R1
goodch:	andi	r1,0xff
		cmpi	r1,127
		jpl		goch1
		cmpi	r1,' '
		jpl		goch2
goch1:	ldi		r1,'.'
goch2:	jind	r6

;-------------------------------------------------------------------
; I/O subroutines
;-------------------------------------------------------------------

;------------------------------------------------------------
; Prints ASCIIZ (16-bit packed, big endian) string on UART 
; parameters:
;	R0: pointer to string
;	R6: return address (JAL)
; returs:
; 	R0-R2: modified

putsbe:	ldi		r2,UARTDAT
putsbe1:
		ld		r1,(r0)
		rori	r1,r1,8
		andi	r1,0xff
		jz		putsbe3
		st		(r2),r1
		
		ld		r1,(r0)
		andi	r1,0xff
		jz		putsbe3
		st		(r2),r1
		addi	r0,1
		jr		putsbe1

putsbe3:
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
; Prints decimal number (or hex, octal,...)
; parameters:
;	R0: number to print
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
		subi	r1,10
		jnc		prtd2
		addi	r0,1
		jr		prtd5
prtd2:	addi	r1,10
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

;-------------------------------------------
; print lower 8 bits of R0 as hex (2 digits)
prthex8:
		subi	r7,2
		st		(r7),r2
		st		(r7+1),r6
		ldi		r6,UARTDAT
		ldi		r2,2
		rori	r0,r0,8
		jr		ptx1

;--------------------------------------
; print 16 bits of R0 as hex (4 digits)
prthex:	subi	r7,2
		st		(r7),r2
		st		(r7+1),r6
		ldi		r6,UARTDAT
		ldi		r2,4
ptx1:	rori	r0,r0,12
		or		r1,r0,r0
		andi	r1,15
		cmpi	r1,10
		jmi		ptx2
		addi	r1,7
ptx2:	addi	r1,'0'
		st		(r6),r1
		subi	r2,1
		jnz		ptx1
		ld		r2,(r7)
		ld		r6,(r7+1)
		addi	r7,2
		jind	r6

;-------------------------------------------------------------------
; variables
;-------------------------------------------------------------------
bvar:
ldpcf:	word	0
trace:	word	0
break:	word 	0
rutsp:	word	0
caddr:	word	0x100

;-------------------------------------------------------------------
; text (overwritable by the stack...maybe)
;-------------------------------------------------------------------
msghelp:	asczbe "\n<space>\tredraw screen\nc\tContinue (no stop)\ne\tExecute (w breakpoint)\ns\tSingle step\nn\texec until Next instr\nr\texec until return (JIND R6)\nR\texec until return at higher stack level\nb [adr]\tset Breakpoint\nd [adr]\tDissasemble\nm [adr]\tMemory dump\n"
txtload:	asczbe "\nUpload program to debug\n"
;-------------------------------------------------------------------
;
;		MAIN (overwritable by the stack)
;
;-------------------------------------------------------------------
pstart:	
start:	
		ldi		r7,0

		ldpc	r0
		word	txtload
		jal		putsbe

		; bootloader-like code
		ldi		r5,IOBASE
buc1:	ld		r0,(r5+UARTDAT-IOBASE)
		cmpi	r0,'L'
		jnz		buc1
		st		(r5+UARTDAT-IOBASE),r0
		jal		getw
		or		r2,r0,r0		; address
		jal		getw
		or		r3,r0,r0		; count
		jal		getw
		or		r4,r0,r0		; entry point

buc2:	jal		getw
		st		(r2),r0
		addi	r2,1
		subi	r3,1
		jnz		buc2

		; set IRQ jump 
		ldi		r1,0xff
		ldpc	r0
		word	JMPIRQ
		st		(r1+0x110-0xff),r0
		; set Trace, break, clear dirty
		ldpc	r2
		word	bvar
		ldi		r0,0
		st		(r2+trace-bvar),r1
		st		(r2+break-bvar),r0
		st		(r5+FLAG0-IOBASE),r0

		; enable SSTEP IRQ
		ld		r0,(r5+IRQEN-IOBASE)
		ori		r0,0x10
		st		(r5+IRQEN-IOBASE),r0
		; and jump to code
		jind	r4

;-------------------------------------------------------------------
; get 16-bit word from UART (two bytes)
getw:	ld		r0,(r5+UARTDAT-IOBASE)	; LSB
		ld		r1,(r5+UARTDAT-IOBASE)	; MSB
		rori	r1,r1,8
		or		r0,r0,r1
		jind	r6


pend:



