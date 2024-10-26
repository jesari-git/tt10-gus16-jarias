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
bvar:

		;word	0xFFFF

xp:		word	0		; Posición de la pieza
yp:		word	0
max:	word	0
sigp:	word	0
npiezas:	word	0
nlineas:	word	0
del:	word	0
dl:		word	0
rndv:	word	0xFFFF
nint:	word	0

phase:	word	0		; tone generator phase
freq:	word	0		; tone generator frequency (65536 => 23.529kHz)
ndel:	word	0		; note delay
pnota:	word	0		; note pointer
onota:	word	0		; old note (2 notes stored on each word)

pieza:	org		.+4*4	; pieza[4][4]

fnotas:	word	1457	; 523.251 Hz DO
		word	1636	; 587,330 Hz RE
		word	1836	; 659,255 Hz MI
		word	1945	; 698,456 Hz FA
		word	2184	; 783,991 Hz SOL
		word	2451	; 880.000 Hz LA
		word	2751	; 987,767 Hz SI
		word	2915	; 1046,50 Hz DO
		word	0		; 0Hz (silencio)
		

;-------------------------------------------------------------------
; Subrutinas I/O
;-------------------------------------------------------------------

; delay 50ms	(no regs modiffied)
del50m:	subi	r7,4
		st		(r7+0),r0
		st		(r7+1),r1
		st		(r7+2),r2
		st		(r7+3),r6
		ldi		r6,nint
		ldpc	r2
		word	1176		; IRQs / 50ms
		ld		r0,(r6)
d50m:	ld		r1,(r6)
		sub		r1,r1,r0
		sub		r1,r1,r2
		jmi		d50m
		ld		r0,(r7+0)
		ld		r1,(r7+1)
		ld		r2,(r7+2)
		ld		r6,(r7+3)
		addi	r7,4
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

;----------------------------------------------------
; Envía cadena de caracteres empaquetados al terminal
; parámetros:
;	R0: puntero a la cadena de caracteres
;	R6: dirección de retorno
; retorna:
; 	

putsle: subi    r7,4
        st      (r7+0),r0
        st      (r7+1),r1
        st      (r7+2),r2
        st      (r7+3),r6
                
        or      r2,r0,r0
ptsl1:  ld      r0,(r2)
        andi    r0,255
        jz      ptsl9
        jal     putch
        ld      r0,(r2)
        rori    r0,r0,8
        andi    r0,255
        jz      ptsl9           
        jal     putch
        addi    r2,1
        jr      ptsl1
                
ptsl9:  ld      r0,(r7+0)
        ld      r1,(r7+1)
        ld      r2,(r7+2)
        ld      r6,(r7+3)
        addi    r7,4
        jind    r6

;----------------------------------------------
; Recibe caracter del terminal
; parámetros:
;	R6: dirección de retorno
; retorna:
;	R0: dato recibido
; 	R1: modificado

; getch:	ldi		r1,UARTDAT	; ahora apuntamos a registro RX
; 		ld		r0,(r1)		; leemos dato
; 		jind	r6			; y retornamos

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
; INTERRUPTS
;-------------------------------------------------------------------
		org	0x100
irq0:	
		org	0x104
irq1:	
		org	0x108
irq2:	
		org	0x10C
irq3:
pwmIRQ:
		subi	r7,3
		st		(r7),r0
		st		(r7+1),r1
		st		(r7+2),r2

		ldi		r2,bvar				; nint++
		ld		r0,(r2+nint-bvar)
		addi	r0,1
		st		(r2+nint-bvar),r0
		
		ld		r0,(r2+phase-bvar)	; phase+=freq
		ld		r1,(r2+freq-bvar)
		add		r0,r0,r1
		st		(r2+phase-bvar),r0
		jpl		ipw1				; level = (phase<0)? ~phase : phase;
		not		r0,r0
ipw1:	rori	r0,r0,7				; PWM = level>>7
		andi	r0,0xff
		ldi		r1,IOBASE			; also clear PWM IRQ
		st		(r1+PWM-IOBASE),r0
		ld		r0,(r2+ndel-bvar)	; if (ndel==0) {
		jnz		ipw2
		ld		r1,(r2+pnota-bvar)  ;   if (pnota) {
		jz		iend
		
		ld		r0,(r2+onota-bvar)  ;   if ((nota=onota)==0) {
		jnz		ipw5
		
ipw4:	ld		r0,(r1)				;     nota = *pnota
		jnz		ipw3				;     if (nota==0) {
		ldpc	r1					;       pnota = &mustab
		word	mustab
		ld		r0,(r1)				;		nota = *pnota
ipw3:	addi	r1,1				;     pnota++
		st		(r2+pnota-bvar),r1

ipw5:	rori	r1,r0,8				;   onota = nota>>8
		andi	r1,0xff
		st		(r2+onota-bvar),r1
		
		or		r1,r0,r0			;   freq = fnotas[nota&0xF]
		andi	r1,0xF
		addi	r1,fnotas
		ld		r1,(r1)
		st		(r2+freq-bvar),r1
		
		andi	r0,0xF0				;   ndel= (nota>>4)*24*128 irqs
		rori	r1,r0,1
		add		r0,r0,r1
		rori	r0,r0,16-7			;   (~128 ms/paso)
		st		(r2+ndel-bvar),r0
		
ipw2:	subi	r0,1				; } else ndel--
		st		(r2+ndel-bvar),r0
iend:	ld		r0,(r7)
		ld		r1,(r7+1)
		ld		r2,(r7+2)
		addi	r7,3
		reti

;-------------------------------------------------------------------
;
;		CODIGO PRINCIPAL
;
;-------------------------------------------------------------------

; Genera números pseudoaleatorios en rndv
rnd:	subi	r7,2
		st		(r7),r1
		st		(r7+1),r6
		ldi		r6,rndv
		ld		r0,(r6)
		add		r0,r0,r0
		jnc		rnd9
		ldpc	r1
		word	0x1021
		xor		r0,r0,r1
rnd9:	st		(r6),r0
		ld		r1,(r7)
		ld		r6,(r7+1)
		addi	r7,2
		jind	r6

; void cuadro(int x,int y, int tipo)
; R0: x
; R1: y
; R2: tipo

cuadro:	subi	r7,4
		st		(r7+3),r6
		st		(r7+2),r5
		st		(r7+1),r4
		st		(r7+0),r3

		add		r4,r0,r0
		or		r5,r1,r1
		ldi		r3,30
		add		r3,r3,r2
		; printf("\033[%d;%dH",y+1,x*2+1);
		ldi		r0,'\e'
		jal		putch
		ldi		r0,'['
		jal		putch
		or		r0,r5,r5
		addi	r0,1
		jal		prtdec
		ldi		r0,';'
		jal		putch
		or		r0,r4,r4
		addi	r0,1
		jal		prtdec
		ldi		r0,'H'
		jal		putch

		;printf("\033[01;%2dm\033[7m  \033[0m",tipo+30);
		ldpc	r0
		word	str1
		jal		putsle
		or		r0,r3,r3
		jal		prtdec
		ldpc	r0
		word	str2
		jal		putsle

		ld		r3,(r7+0)
		ld		r4,(r7+1)
		ld		r5,(r7+2)
		ld		r6,(r7+3)
		addi	r7,4
		jind	r6
str1:	asczle	"\e[01;"
str2:	asczle	"m\e[7m  \e[0m"

;void init()
init:	subi	r7,1
		st		(r7),r6
		
;	for (i=0;i<ALTO;i++) {
;		for (j=1;j<ANCHO+1;j++) campo[i][j]=0;
;		campo[i][0]=campo[i][ANCHO+1]=8;
;	}
		ldpc	r1
		word	campo
		ldi		r6,ALTO
ini1:	ldi		r0,8
		st		(r1),r0
		addi	r1,1
		ldi		r2,ANCHO
		ldi		r0,0
ini2:	st		(r1),r0
		addi	r1,1
		subi	r2,1
		jnz		ini2
		ldi		r0,8
		st		(r1),r0
		addi	r1,1
		subi	r6,1
		jnz		ini1
;	for (j=0;j<ANCHO+2;j++) campo[i][j]=8;
		ldi		r2,ANCHO+2
ini3:	st		(r1),r0
		addi	r1,1
		subi	r2,1
		jnz		ini3
;	for (i=0;i<ALTO+1;i++) for(j=0;j<ANCHO+2;j++) oldc[i][j]=0xff;
		ldpc	r1
		word	oldc
		ldi		r0,0xff
		ldi		r2,(ALTO+1)*(ANCHO+2)
ini4:	st		(r1),r0
		addi	r1,1
		subi	r2,1
		jnz		ini4
;	for (i=0;i<4;i++) for (j=0;j<4;j++) pieza[i][j]=0;
		ldi		r1,pieza
		ldi		r0,0
		ldi		r2,16
ini5:	st		(r1),r0
		addi	r1,1
		subi	r2,1
		jnz		ini5
;	xp=4; yp=-4;
		ldi		r1,bvar
		ldi		r0,4
		st		(r1+xp-bvar),r0
		neg		r0,r0
		st		(r1+yp-bvar),r0
;        printf("\0332J\033[H");
		ldpc	r0
		word	str3
		jal		putsle

		ld		r6,(r7)
		addi	r7,1
		jind	r6
str3:	asczle	"\e[2J\e[H"

;void display()
display:
;int i,j,ip,jp,ch;
		subi	r7,4
		st		(r7+3),r6
		st		(r7+2),r5
		st		(r7+1),r4
		st		(r7+0),r3
;	for (i=0;i<ALTO+1;i++) {			; i=R5
;	    for (j=0;j<ANCHO+2;j++) {		; j=R4
		ldi		r5,0
disp1:	ldi		r4,0		
;		ch=0;							; ch=R3
disp2:	ldi		r3,0
		add		r0,r5,r5				
		add		r0,r0,r0				; R0=i*4
		add		r1,r0,r0				; R1=i*8
		add		r1,r1,r0				; R1=i*12 (ANCHO+2)
		add		r1,r1,r4				; R1=i*12+j
		ldpc	r0
		word	campo
		add		r2,r1,r0				; r2=campo[i][j]
;		if (campo[i][j]) ch=campo[i][j];
		ld		r0,(r2)
		jz		disp3
		or		r3,r0,r0
;		ip=i-yp;			; ip=R2
disp3:	ldi		r2,yp
		ld		r2,(r2)
		sub		r2,r5,r2
;		if (ip>=0 && ip<4) {
		jmi		disp4
		cmpi	r2,4
		jc		disp4
;		    jp=j-xp;		; jp=R0
		ldi		r0,xp
		ld		r0,(r0)
		sub		r0,r4,r0
;		    if (jp>=0 && jp<4) 
		jmi		disp4
		cmpi	r0,4
		jc		disp4
;				if (pieza[ip][jp]) ch=pieza[ip][jp];
		add		r2,r2,r2
		add		r2,r2,r2
		add		r2,r2,r0	; R2=ip*4+jp
		ldi		r0,pieza
		add		r2,r2,r0	; R2=&pieza[ip][jp]
		ld		r0,(r2)
		jz		disp4
		or		r3,r0,r0
;		}
disp4:
;		if (oldc[i][j]!=ch) {
		ldpc	r0
		word	oldc
		add		r2,r1,r0	; R2=&oldc[i][j]
		ld		r0,(r2)
		sub		r0,r0,r3
		jz		disp5
;		    oldc[i][j]=ch;
		st		(r2),r3
;		    cuadro(j,i,ch);
		or		r0,r4,r4
		or		r1,r5,r5
		or		r2,r3,r3
		jal		cuadro
;		  }
;	    }
disp5:	addi	r4,1
		ldi		r0,ANCHO+2
		sub		r0,r4,r0
		jnz		disp2
;	}
		addi	r5,1
		ldi		r0,ALTO+1
		sub		r0,r5,r0
		jnz		disp1
;	printf("\033[%d;%dH",12,31);
		ldpc	r0
		word	str4
		jal		putsle

		ld		r3,(r7+0)
		ld		r4,(r7+1)
		ld		r5,(r7+2)
		ld		r6,(r7+3)
		addi	r7,4
		jind	r6
str4:	asczle	"\e[12;31H"

;int testpos(int x, int y)
testpos:	; R0 = x  R1 = y
		subi	r7,4
		st		(r7+3),r6
		st		(r7+2),r5
		st		(r7+1),r4
		st		(r7+0),r3
;	for (i=0;i<4;i++)
;		for (j=0;j<4;j++) {
		ldi		r6,0	; R6 = i
tpos1:	ldi		r5,0	; R5 = j
tpos2:
;			if (x+j<0) continue;
		add		r2,r0,r5
		jmi		tpos3
;			if (x+j>ANCHO+1) continue;
		cmpi	r2,ANCHO+1
		jz		tpos21
		jc		tpos3
;			if (y+i<0) continue;
tpos21:	add		r4,r1,r6
		jmi		tpos3
;			if (y+i>ALTO) continue;
		ldi		r3,ALTO
		sub		r3,r4,r3
		jz		tpos22
		jc		tpos3
;			if (campo[y+i][x+j] && pieza[i][j]) return 1;
tpos22:	add		r3,r4,r4	;
		add		r3,r3,r4	; r3 = (y+i)*3
		add		r3,r3,r3
		add		r3,r3,r3	; r3 = (y+i)*12
		add		r3,r3,r2	; r3 = (y+i)*12 + (x+j)
		ldpc	r2
		word	campo
		add		r3,r3,r2
		ld		r3,(r3)
		jz		tpos3

		add		r3,r6,r6	; r3 = i*4
		add		r3,r3,r3
		add		r3,r3,r5	; r3= i*4+j
		ldi		r2,pieza
		add		r3,r3,r2
		ld		r3,(r3)
		jz		tpos3

		ldi		r0,1
		jr		tpos9

tpos3:	addi	r5,1
		cmpi	r5,4
		jnz		tpos2
		addi	r6,1
		cmpi	r6,4
		jnz		tpos1
;		}
;	return 0;
		ldi		r0,0
tpos9:	ld		r3,(r7+0)
		ld		r4,(r7+1)
		ld		r5,(r7+2)
		ld		r6,(r7+3)
		addi	r7,4
		jind	r6

;void rota(int giro)
rota:	; R0: 0 horario,  !=0 antihorario
		subi	r7,18	; espacio para tabla en la pila
		st		(r7+17),r6
		st		(r7+16),r5
		;	int i,j; R6=i, R5=i
		;	uchar tmp[4][4];

;	if (giro>0) {		//Giro antihorario de 90º
		or		r0,r0,r0
		jz		rotah
;		for (i=0;i<4;i++)
;			for (j=0;j<4;j++) tmp[3-j][i]=pieza[i][j];
		ldi		r1,pieza
		ldi		r6,0
rota1:	ldi		r5,0
rota2:	ldi		r2,3
		sub		r2,r2,r5	; 3-j
		rori	r2,r2,16-2
		add		r2,r2,r6	; [3-j]*4+j
		add		r2,r7,r2	; &tmp[3-j][i]
		ld		r0,(r1)
		addi	r1,1
		st		(r2),r0
		addi	r5,1
		cmpi	r5,4
		jnz		rota2
		addi	r6,1
		cmpi	r6,4
		jnz		rota1
;		for (i=0;i<4;i++)
;			for (j=0;j<4;j++) pieza[i][j]=tmp[i][j];
		jr		rota4
;	}
;	if (giro<0) {		//Giro horario de 90º
;		for (i=0;i<4;i++)
;			for (j=0;j<4;j++) tmp[j][3-i]=pieza[i][j];
rotah:	ldi		r1,pieza
		ldi		r6,0
rota5:	ldi		r5,0
rota6:	rori	r2,r5,16-2 ; j*4
		addi	r2,3
		sub		r2,r2,r6	; j*4 +3 -i
		add		r2,r2,r7	; R2 = &tmp[j][3-i]
		ld		r0,(r1)
		addi	r1,1
		st		(r2),r0
		addi	r5,1
		cmpi	r5,4
		jnz		rota6
		addi	r6,1
		cmpi	r6,4
		jnz		rota5
;		for (i=0;i<4;i++)
;			for (j=0;j<4;j++) pieza[i][j]=tmp[i][j];
rota4:	ldi		r1,pieza
		ldi		r6,16
rota3:	ld		r0,(r7)
		st		(r1),r0
		addi	r1,1
		addi	r7,1		; Aprovechamos para reajustar pila
		subi	r6,1
		jnz		rota3
;	}

		ld		r5,(r7+0)
		ld		r6,(r7+1)
		addi	r7,2
		jind	r6

;-------------------------------------------------------------------
;
;		MAIN
;
;-------------------------------------------------------------------
pstart:	
start:	
		ldpc	r7			; Puntero de Pila al final de RAM
		word	0x8000
		ldi		r1,IOBASE	
		ldi		r0,8		; Enable PWM IRQ
		st		(r1+IRQEN-IOBASE),r0
		
;	max=0;
		ldi		r0,0
		ldi		r1,bvar
		st		(r1+max-bvar),r0
		jal		init
		jal		display
		jr		mbuc100
mbuc0:
;	init();
		jal		init
;	display();
		jal		display

;	sigp=rand()%7;
mbuc01:	jal		rnd
		jal		rnd
		jal		rnd
		andi	r0,7
		cmpi	r0,7
		jz		mbuc01
		
		ldi		r1,bvar
		st		(r1+sigp-bvar),r0
;	npiezas=nlineas=0;
		ldi		r0,0
		st		(r1+npiezas-bvar),r0
		st		(r1+nlineas-bvar),r0
;	printf("\033[%d;%dH",12,28);
;	printf("MAX");
;	printf("\033[%d;%dH",13,28);
		ldpc	r0
		word	str5
		jal		putsle
;	printf("%d",max); fflush(stdout);
		ldi		r1,bvar
		ld		r0,(r1+max-bvar)
		jal		prtdec
;	for(;;) {
mbuc1:

;		npiezas++;
		ldi		r1,bvar
		ld		r0,(r1+npiezas-bvar)
		addi	r0,1
		st		(r1),r0
;		np=sigp;
		ldi		r2,sigp
		ld		r3,(r2)		; np=R3
;		sigp=rand()%7;
mbuc20:	jal		rnd
		jal		rnd
		jal		rnd
		andi	r0,7
		cmpi	r0,7
		jz		mbuc20
		ldi		r2,sigp
		st		(r2),r0
;		// Dibujamos la siguiente pieza
;		for (i=0;i<2;i++)
;		    for(j=0;j<4;j++)
;		    	cuadro(ANCHO+3+j,i,piezas[sigp][i][j]);
		ldi		r5,0
		ldpc	r4			; R4=&piezas[sigp][0][0]
		word	piezas
		ldi		r1,sigp
		ld		r0,(r1)
		rori	r0,r0,16-3
		add		r4,r0,r4
mbuc2:	or		r0,r5,r5
		andi	r0,3
		addi	r0,ANCHO+3
		shr		r1,r5
		shr		r1,r1
		add		r2,r5,r4
		ld		r2,(r2)
		jal		cuadro
		addi	r5,1
		cmpi	r5,8
		jnz		mbuc2
;		// Copiamos pieza actual a su bitmap
;		for (i=0;i<4;i++)
;		    for (j=0;j<4;j++)
;			pieza[i][j]=(i==0 || i==3)?0:piezas[np][i-1][j];
		ldpc	r4			; R4=&piezas[np][0][0]
		word	piezas
		rori	r0,r3,16-3
		add		r4,r0,r4
		ldi		r2,pieza
		ldi		r5,0		; i
mbuc5:	ldi		r6,0		; j
mbuc3:	ldi		r0,0
		cmpi	r5,0
		jz		mbuc4
		cmpi	r5,3
		jz		mbuc4
		or		r1,r5,r5
		subi	r1,1
		add		r1,r1,r1
		add		r1,r1,r1	; R1=(i-1)*4
		add		r1,r1,r6	; R1=(i-1)*4+j
		add		r1,r1,r4	; R1=&piezas[np][i-1][j];
		ld		r0,(r1)
mbuc4:	add		r1,r5,r5
		add		r1,r1,r1	; R1=i*4
		add		r1,r1,r6	; R1=(i*4)+j
		ldi		r2,pieza
		add		r1,r1,r2	; R1=&pieza[i][j]
		st		(r1),r0
		addi	r6,1
		cmpi	r6,4
		jnz		mbuc3
		addi	r5,1
		cmpi	r5,4
		jnz		mbuc5
;		// Posiciones iniciales
;		xp=4; yp=-2;
		ldi		r1,bvar
		ldi		r0,4
		st		(r1+xp-bvar),r0
		ldi		r0,2
		neg		r0,r0
		st		(r1+yp-bvar),r0
;		// Si no se puede ni empezar a caer: Game Over
;		if (testpos(xp,yp)) break;
		ld		r0,(r1+xp-bvar)
		ld		r1,(r1+yp-bvar)
		jal		testpos
		or		r0,r0,r0
		jnz		mbuc100
;		del=INIDEL-nlineas/DELSTEP; 
		ldi		r1,bvar
		ld		r0,(r1+nlineas-bvar)
		shr		r0,r0
		shr		r0,r0
		shr		r0,r0
		ldi		r1,15
		sub		r0,r1,r0
;		if (del<1) del=1; dl=del;
		jmi		mbuc41
		jnz		mbuc42
mbuc41:	ldi		r0,1
mbuc42:	ldi		r1,bvar
		st		(r1+del-bvar),r0
		st		(r1+dl-bvar),r0
ibuc0:	; bucle de caida
;		jal		rnd

;			np=0;
		ldi		r3,0
;			switch(getch_vt()) {
		ldi		r1,IOBASE
		ld		r0,(r1+PFLAGS-IOBASE)
		andi	r0,1
		jz		ibuc1
		ld		r0,(r1+UARTDAT-IOBASE)
;case K_L:	if (!testpos(xp-1,yp)) xp--;
;					np=1;
;					break;
		ldi		r3,1
		cmpi	r0,'j'
		jnz		ibuc2
		ldi		r4,bvar
		ld		r5,(r4+xp-bvar)
		or		r0,r5,r5
		subi	r0,1
		ld		r1,(r4+yp-bvar)
		jal		testpos
		or		r0,r0,r0
		jnz		ibuc1
		or		r0,r5,r5
		subi	r0,1
		st		(r4+xp-bvar),r0
		jr		ibuc1
;case K_R:	if (!testpos(xp+1,yp)) xp++;
ibuc2:	ldi		r3,1
		cmpi	r0,'l'
		jnz		ibuc3
		ldi		r4,bvar
		ld		r5,(r4+xp-bvar)
		or		r0,r5,r5
		addi	r0,1
		ld		r1,(r4+yp-bvar)
		jal		testpos
		or		r0,r0,r0
		jnz		ibuc1
		or		r0,r5,r5
		addi	r0,1
		st		(r4+xp-bvar),r0
		jr		ibuc1
;case K_U:	rota(1);
ibuc3:	ldi		r3,1
		cmpi	r0,'k'
		jnz		ibuc4
		ldi		r0,1
		jal		rota
;if(testpos(xp,yp)) rota(-1);
		ldi		r1,bvar
		ld		r0,(r1+xp-bvar)
		ld		r1,(r1+yp-bvar)
		jal		testpos
		or		r0,r0,r0
		jz		ibuc1
		ldi		r0,0
		jal		rota
;case K_D:	while (!testpos(xp,yp+1)) {
ibuc4:	cmpi	r0,' '
		jnz		ibuc5
ibuc45:	ldi		r4,bvar
		ld		r0,(r4+xp-bvar)
		ld		r1,(r4+yp-bvar)
		addi	r1,1
		jal		testpos
		or		r0,r0,r0
		jnz		nuevapieza
;						yp++;
		ld		r0,(r4+yp-bvar)
		addi	r0,1
		st		(r4+yp-bvar),r0
;						display();
		jal		display
;						usleep(50000);
		jal		del50m
		jr		ibuc45
ibuc5:
ibuc1:
;			if (!(--dl)) {	// ABAJO
		ldi		r1,bvar
		ld		r0,(r1+dl-bvar)
		subi	r0,1
		st		(r1+dl-bvar),r0
		jnz		ibuc20
;				dl=del;
		ld		r0,(r1+del-bvar)
		st		(r1+dl-bvar),r0
;			if (testpos(xp,yp+1)) break;
		ld		r0,(r1+xp-bvar)
		ld		r1,(r1+yp-bvar)
		addi	r1,1
		jal		testpos
		or		r0,r0,r0
		jnz		nuevapieza
;				yp++;
		ldi		r1,yp
		ld		r0,(r1)
		addi	r0,1
		st		(r1),r0
;				np=1;
		ldi		r3,1
;			}
ibuc20:
;			if (np) display();
		or		r3,r3,r3
		jz		ibuc21
		jal		display
ibuc21:
;			usleep(50000);
		jal		del50m

		jr		ibuc0

nuevapieza:	;// Añadimos la pieza al campo
;		for (i=0;i<4;i++)
;		    for (j=0;j<4;j++)
;		    	if (yp+i>=0 && yp+i<ALTO && xp+j>0 && xp+j<ANCHO+1)
;		    	    campo[yp+i][xp+j]|=pieza[i][j];
		ldi		r6,0		; R6 = i
mbuc6:	ldi		r5,0		; R5 = j
mbuc7:	ldi		r1,yp
		ld		r0,(r1)
		add		r0,r0,r6	; R0 = yp+i
		jmi		mbuc8
		cmpi	r0,ALTO
		jc		mbuc8
		ldi		r1,xp
		ld		r1,(r1)
		add		r1,r1,r5	; R1 = xp+j
		jmi		mbuc8
		cmpi	r1,ANCHO+1
		jc		mbuc8
		rori	r2,r6,16-2
		add		r2,r2,r5	; R2 = i*4+j
		ldi		r4,pieza
		add		r2,r2,r4
		ld		r4,(r2)		; R4=pieza[i][j]; 
		add		r2,r0,r0
		add		r2,r2,r0
		rori	r2,r2,16-2
		add		r2,r2,r1	; R2 = [yp+i]*12 + [xp+j]
		ldpc	r1
		word	campo
		add		r1,r1,r2	; R1 = &campo[yp+i][xp+j]
		ld		r2,(r1)
		or		r4,r4,r2
		st		(r1),r4
mbuc8:	addi	r5,1
		cmpi	r5,4
		jnz		mbuc7
		addi	r6,1
		cmpi	r6,4
		jnz		mbuc6

;		// Comprobamos si hay que "quemar" alguna línea
;		xp=yp=-4;
		ldi		r0,4
		neg		r0,r0
		ldi		r1,bvar
		st		(r1+xp-bvar),r0
		st		(r1+yp-bvar),r0
;		for (i=0;i<ALTO;i++) {
		ldi		r6,0	; R6 = i
mbuc10:
;		    for (j=1;j<ANCHO+1;j++) if (!campo[i][j]) break;
		add		r2,r6,r6
		add		r2,r2,r6
		rori	r2,r2,16-2	; R2 = k*12
		ldpc	r1
		word	campo
		add		r1,r1,r2
		addi	r1,1
		ldi		r5,ANCHO
mbuc11:	ld		r0,(r1)
		jz		mbuc30
		addi	r1,1
		subi	r5,1
		jnz		mbuc11
;		    if (j==ANCHO+1) {	// Linea completa: Scroll hacia abajo
;			for (j=1;j<ANCHO+1;j++)
;			    for (k=i;k>=0;k--)
;				campo[k][j]=(k)?campo[k-1][j]:0;
		ldi		r5,1
mbuc12:	or		r4,r6,r6	; R4 = k
mbuc13:	add		r2,r4,r4
		add		r2,r2,r4
		rori	r2,r2,16-2	; R2 = k*12
		add		r2,r2,r5	; R2 = k*12 + j	
		ldpc	r0
		word	campo
		add		r2,r2,r0	; R2 = &campo[k][j]
		or		r3,r2,r2
		subi	r3,12	; R3 = &campo[k-1][j]
		ldi		r0,0
		or		r4,r4,r4
		jz		mbuc14
		ld		r0,(r3)
mbuc14:	st		(r2),r0
		subi	r4,1
		jpl		mbuc13
		addi	r5,1
		cmpi	r5,ANCHO+1
		jnz		mbuc12		

;			nlineas++;
		ldi		r1,nlineas
		ld		r0,(r1)
		addi	r0,1
		st		(r1),r0
		or		r5,r6,r6	; Copia temporal
;			printf("\033[%d;%dH",10,28);
;			printf("%d",nlineas);
		ldpc	r0
		word	str6
		jal		putsle
		ldi		r1,nlineas
		ld		r0,(r1)
		jal		prtdec
;			if (nlineas>max) {
;				max=nlineas;
;				printf("\033[%d;%dH",13,28);
;				printf("%d",max);
;			}
		ldi		r2,bvar
		ld		r3,(r2+nlineas-bvar)
		ld		r1,(r2+max-bvar)
		sub		r1,r3,r1
		jnc		mbuc15
		st		(r2+max-bvar),r3
		ldpc	r0
		word	str5
		jal		putsle
		or		r0,r3,r3
		jal		prtdec
;			display();
mbuc15:	jal		display
;			usleep(100000);
		jal		del50m
		jal		del50m

;		    }
;		}
		or		r6,r5,r5
mbuc30:	
		addi	r6,1
		cmpi	r6,ALTO
		jnz		mbuc10


		jr	mbuc1

mbuc100:
		ldpc	r0
		word	str7
		jal		putsle
		
		; stop music
		ldi		r0,0
		ldi		r1,bvar
		st		(r1+freq-bvar),r0
		st		(r1+pnota-bvar),r0
		
mbuc101:
		jal		rnd
		ldi		r1,IOBASE	; repite mientras no hay datos en UART RX
		ld		r0,(r1+PFLAGS-IOBASE)
		andi	r0,1
		jz		mbuc101
		; Borra flag de dato recibido
		ld		r0,(r1+UARTDAT-IOBASE)
		; start music
		ldpc	r0
		word	mustab
		ldi		r1,bvar
		st		(r1+pnota-bvar),r0

		jr		mbuc0


str7:	asczle "\e[10;8HGAME OVER\e[12;2HPress any key to start"
str5:	asczle "\e[12;28HMAX\e[13;28H"
str6:	asczle "\e[10;28H"

;-------------------------------------------------------------------
; Constantes
;-------------------------------------------------------------------

piezas:	;piezas[7][2][4]
	word 1	; 0 Barra ####
	word 1	;         .... 
    word 1
    word 1
	word 0
	word 0
	word 0
	word 0

	word 2	; 1 /L    ###.
	word 2	;         ..#.
	word 2
	word 0
	word 0
	word 0
	word 2
	word 0

	word 0	; 2 L     .###
	word 3  ;         .#..
	word 3
	word 3
	word 0
	word 3
	word 0
	word 0

	word 0	; 3 S     ..##
	word 0	;         .##.
	word 4
	word 4
	word 0
	word 4
	word 4
	word 0

	word 5	; 4 /S    ##..
	word 5	;         .##.
	word 0
	word 0
	word 0
	word 5
	word 5
	word 0

	word 0	; 5 T     .###
	word 6	;         ..#.
	word 6
	word 6
	word 0
	word 0
	word 6
	word 0

	word 0	; 6 Cuadr .##.
	word 7	;         .##.
	word 7
	word 0
	word 0
	word 7
	word 7
	word 0

; Melodias: Cada nota consta de 4 bits de duración (MSB)
; y de 4 bits de selección de nota (LSB) 0=DO, 1=RE, ...
; 2 notas por dato, LSB: primera nota
; La melodía termina en 0
mustab:	
		word	0x1110
		word	0x1422
		word	0x3418
		word	0x2415
		word	0x3022
		word	0x1211
		word	0x2218
		word	0x2021
		word	0x1851
		word	0x1110
		word	0x1422
		word	0x3418
		word	0x2415
		word	0x3022
		word	0x1211
		word	0x2218
		word	0x1811
		word	0x6021
		word	0x3328
		word	0x4318
		word	0x1815
		word	0x1835
		word	0x3425
		word	0x2415
		word	0x5122
		word	0x1018
		word	0x2211
		word	0x1814
		word	0x1534
		word	0x2224
		word	0x1130
		word	0x1812
		word	0x1122
		word	0x2118
		word	0xF850
		word	0

pend:
;-------------------------------------------------------------------
; Variables y tablas
;-------------------------------------------------------------------

campo:	; campo[ALTO+1][ANCHO+2]
oldc= campo+(ALTO+1)*(ANCHO+2)
	


