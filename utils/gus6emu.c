#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <termio.h>

#include "dtypes.h"
#include "opcodes.h"

/*********************************************************************
	Emulador de la CPU Von Neumann de 1 ciclo de la asignatura S.E.M.

	Versión con interrupciones y más periféricos.

	por Jesus Arias.

**********************************************************************/

#define FCLK 36000000	// frecuencia de reloj de la CPU (Hz)
#define BAUD 115200		// velocidad de la UART (bps)

/*********************************************************************
	Funciones para control de stdin
**********************************************************************/
int stdinflags;

// Set canonical mode for stdin (line editing)
void setcanon(void)
{
        static struct termios term;
        tcgetattr(0,&term);
        term.c_lflag|=ICANON;
        term.c_lflag|=ECHO;
        if (tcsetattr(0,TCSANOW,&term)) {
                fprintf(stderr,"tcsetattr failed\n");
                exit(0);
        }
}

// Set NOcanonical mode for stdin (single character input)
// gcc-2.95.3(i386) generates buggy code for this function
// (uncontrolled stack pointer)

void setnocanon(void)
{
        static struct termios term;
        tcgetattr(0,&term);
        term.c_lflag&=~ICANON;
        term.c_lflag&=~ECHO;
        // Solaris is a bit stupid fetching 4 chars at a time by default.
        // It tries to be "more efficient". But I think noncanonical mode
        // is used for reading 1 char at a time 99.9(period) % of times
        term.c_cc[VMIN]=1;      // Force 1 char at a time (too smart Sunos)
        term.c_cc[VTIME]=0;
        if (tcsetattr(0,TCSANOW,&term)) {
                fprintf(stderr,"tcsetattr failed\n");
                exit(0);
        }
}

/*********************************************************************
**********************************************************************/

int Trace;
int Trap=-1;

#define ZF 1
#define CF 2
#define NF 4
#define VF 8

struct {
    /* Registros. Tamaño entero para marcar valor no usado como -1 */
    int	r[8];	/* Banco de registros PC=r[0] */
	int	pc;		/* contadores de programa */
	int	flags;	/* bit 0: Z, bit 1: C, bit 2: N, bit3: V */
    int modo;	/* bit 0: entrada IRQ, bit 1: preIRQ, bit 2: modo */
	int pc0;	/* copia del PC (IRQ) */
	int	flags0;	/* copia de flags (IRQ) */
	int	vector;	/* vector de interrupción */
    /* Otras variables */
    uint32 nciclos;	/* Contador de ciclos de reloj */
} cpu;

uint16 MEM[0x10000];

/*--------------------------------------------------------------------*/

void reset_cpu();	// prototipo (usado en Debug...)

/*--------------------------------------------------------------------*/

int muestra_instr(uint16 cop, int pc)
{
	int ra,rb,rd,op,n,nof,nrori;
	int16 desp;
	int i,j;

	if ((cop&0xF8E3)==0x58E3) {printf("RETI"); return 0;}

	rb=(cop>>2)&7;  
	n =cop&255;
	nof=cop&31;
	nrori=(((cop>>5)&3)<<2)|(cop&3);
	desp=cop & 0xfff; if (desp & 0x800) desp |=0xf000;
	ra=(cop>>5) & 7;
	rd=(cop>>8) & 7;

	if ((cop>>12)==0) op=cop&0xF803;
	else {
		if ((cop>>11)<0xB) op=cop&0xF800;
		else {
			if ((cop>>11)==0xB) {
				op=cop&0xF8E3;
				if (!(op&0x80)) op=cop&0xF800;	
			}else {
				if ((cop>>12)<7) op=cop&0xF800;
				else op=cop&0xF000;
			}
		}
	}

	for (i=0;instr[i].tipo;i++) {
		if (op==instr[i].opcode) break;
	}
	if (!instr[i].tipo) printf("ILEG");
	else {
		printf("%s",instr[i].nemo);
		for (j=6-strlen(instr[i].nemo);j;j--) putchar(' ');
	}
	switch(instr[i].tipo) {
		case TIPO_3REG:	printf("R%d,R%d,R%d",rd,ra,rb); break;
		case TIPO_IMM:	printf("R%d,0x%X",rd,n); break;
		case TIPO_RORI:	printf("R%d,R%d,0x%X",rd,rb,nrori); break;
		case TIPO_2REG:	printf("R%d,R%d",rd,rb); break;
		case TIPO_LDPC:	printf("R%d",rd); return 1;
		case TIPO_JIND:	printf("R%d",rb); break;

		case TIPO_LD:	if (nof) printf("R%d,(R%d+%d)",rd,ra,nof); 
						else printf("R%d,(R%d)",rd,ra); 
						break;
		case TIPO_ST:	if (nof) printf("(R%d+%d),R%d",ra,nof,rd);
						else printf("(R%d),R%d",ra,rb);
						break;

		case TIPO_JR:	printf("0x%04X",pc+desp+1); break;
	}
	return 0;
}

/*--------------------------------------------------------------------*/

int videomod;	// Flag de pantalla modificada

// Variables de los periféricos
#define UART_DEL ((FCLK/BAUD)*10)	// 10 bits/caracter, 
unsigned char uart_tx, uart_rx;
unsigned int uart_tx_stamp;
unsigned short pflags=0x0006;
unsigned short irqen;
unsigned short timermax,timerval,hold,curr;
unsigned short spitx, spirx, spicntl;
unsigned int spi_stamp, spi_delay;
unsigned short gpdir, gpout, gpin;


extern inline int debug()
{
    int i,j,k,n;
    uint16 dir;
    const char *fln="VNCZ";
    char buf[64];
	static unsigned int tstamp;

	// stdin en modo normal
	fcntl(0, F_SETFL, stdinflags);
	setcanon();

	// si el programa emulado ha escrito algo esperamos
	// antes de borrar la pantalla
	if (videomod) {
		printf("\n<pulsa intro>\n");
		getchar();
		videomod=0;
	}
    
dupdate:
    
    // borrar pantalla
    printf("\033[2J\033[H");
    
    // mostrar codigo actual
	dir=(cpu.pc-4)&0xffff;
	j=((MEM[dir]&0xF800)==0x7000);	//Ver si antes hay una LDPC
    for (i=0,dir=cpu.pc-3;i<18;i++,dir++) {
		dir&=0xffff;
		if (dir==cpu.pc) printf("\n>"); else putchar(' ');
        printf("%04X: %04X   ",dir,MEM[dir]);
		if (j) {printf("WORD  0x%04X",MEM[dir]); j=0;}
		else j=muestra_instr(MEM[dir],dir);
		putchar('\n');
    }
    
    // Mostrar estado de CPU (registros, modo)
	printf("\033[1;36HPC = %04X",cpu.pc+1);
	printf("\033[5;50Hmodo  = %s",(cpu.modo&4)?"IRQ":"normal");
	if (cpu.modo&4) {
		printf("\033[7;50HPC0   = %04X",cpu.pc0);
		//printf("\033[8;50HRH0   = ");
		//if (cpu.rh0<0) printf("--");	else printf("%02X",cpu.rh0);
		printf("\033[8;50HFlag0 = ");
    	j=cpu.flags0;
    	for (i=0;i<4;i++) {putchar((j&8)?fln[i]:'_'); j<<=1;}		
	}
	printf("\033[12;50HIRQEN  = %04X",irqen);
	printf("\033[13;50HTIMER  = %04X / %04X",timerval,timermax);
	printf("\033[14;50HPFLAGS = %04X",pflags);
	printf("\033[15;50HPWM    = %03X / %03X",hold,curr); 
	printf("\033[16;50HSPICTL = %04X",spicntl);
	printf("\033[17;50HGPDIR  = %04X",gpdir);
	printf("\033[18;50HGPOUT  = %04X",gpout);


    //printf("\033[3;36HRH = ");
	//if (cpu.rh<0) printf("--");	else printf("%02X",cpu.rh);
	
    for (i=0;i<8;i++) {
    	printf("\033[%d;36HR%d = ",i+5,i);
		if (cpu.r[i]<0) printf("----");
		else printf("%04X",cpu.r[i]);
    }
    
    printf("\033[14;36HFlags = ");
    j=cpu.flags;
    for (i=0;i<4;i++) {putchar((j&8)?fln[i]:'_'); j<<=1;}
    
    // Mostrar estadisticas, breakpoint
    printf("\033[1;50HCycles=%u",cpu.nciclos);
    printf("\033[1;68Hdt=%u",cpu.nciclos-tstamp);
    if (Trap>=0) printf("\033[3;50HBreak =%04X",Trap);
        
    printf("\033[21;1H");
    
    // intérprete de comandos
    while(1) {
    	printf("[Command,'?']-> ");
    	fflush(stdout);fflush(stdin);

    	fgets(buf,63,stdin);
    	for(j=0;buf[j]>=' ';j++) buf[j]=toupper(buf[j]);
		buf[j]='\0';
    	switch(buf[0]) {
	case '\0': Trace=1; 
			tstamp=cpu.nciclos;
			return;	 // paso simple
	case '?':  
			printf("\n?        This help\n");
			printf("<space>  Redraw\n");
			printf("<intro>  Single Step\n");
			printf("B <addr> Breakpoint at <addr>\n");
			printf("= <addr> Exec until <addr>\n");
			printf("N        Exec until Next instruction\n");
			printf("J <addr> Exec from <addr> (Jump)\n");
			printf("C        Continue execution without Breakpoint\n");
			printf("E        Continue execution with Breakpoint\n");
			printf("M [addr] Memory dump from [addr]\n");
			printf("M        Memory dump from next address\n");
			printf("D [addr] Disassembly from [addr]\n");
			printf("D        Disassembly from next address\n");
			printf("R        Reset CPU\n");
			printf("Q        Quit to O.S.\n\n");
			break;
	case 'B':  
			if(strlen(buf)>=2) {		// set BRK
				sscanf(buf+1,"%hX",&i);
				Trap=i;
			}
			goto dupdate;
	case '=':  
			if(strlen(buf)>=2) {		// Ejecutar hasta BRK
				sscanf(buf+1,"%hX",&i);
				Trap=i;
				goto goexe;
			}
			break;
	case 'N':  
			Trap=cpu.pc+1;		// Ejecutar hasta PC+1
			goto goexe;
	case 'J':  
			if(strlen(buf)>=2){		// Cambia PC y ejecuta
				sscanf(buf+1,"%hX",&i);
				cpu.pc=i;
				goto goexe;
			}
			break;
	case 'C':  Trap=-1;			// Continua sin BRK
goexe:		
	case 'E':  Trace=0;			// Continua con BRK
			fcntl(0, F_SETFL, stdinflags | O_NONBLOCK);
			setnocanon();
			printf("\n<Ejecutando... pulsa <ctrl>-c  para volver al depurador>\n\n");
			tstamp=cpu.nciclos;
			return;
	case 'R':
			tstamp=0;
			reset_cpu();			// RESET
			goto dupdate;
   	case 'Q':  exit(0);			// Salida del emulador
	
	case 'M':  
			if(strlen(buf)>=2) {		// Listado de Memoria de datos
				sscanf(buf+1,"%hX",&dir);
		   	}
			for (i=0;i<16;i++) {
				printf("%04X - ",dir);
				for (j=0;j<8;j++) {
					k=MEM[(dir+j)&0xffff];
					printf("%04X ",k);
				}
				putchar(' ');
				for (j=0;j<8;j++) {
					k=MEM[(dir+j)&0xffff];
					n=k>>8;
					putchar((n>=32 && n<128)?n:'.');
					n=k&0xff;
					putchar((n>=32 && n<128)?n:'.');
					putchar(' ');
				}
				putchar('\n');
				dir+=j;
			}
			break;
	case 'D':  
			if(strlen(buf)>=2) {		// Desensamblado
				sscanf(buf+1,"%hX",&dir);
			}
			for (i=j=0;i<16;i++,dir++) {
				printf("%04X: %04X   ",dir,MEM[dir]);
				//muestra_instr(MEM[dir],dir);
				if (j) {printf("WORD  0x%04X",MEM[dir]); j=0;}
				else j=muestra_instr(MEM[dir],dir);
		     putchar('\n');
			}
			break;

	case 'I':
			cpu.modo^=1;	// Irq
			printf("IRQ %s\n",(cpu.modo&1)?"ON":"Off");
			break;

	default:   goto dupdate;
		}
    }
}

/**********************************************************/
/**********************************************************/
/**************----------- EMULADOR ----------*************/
/**********************************************************/
/**********************************************************/


uint16 rd_mem(uint16 dir)
{
	if ((dir&0xffe0)!=0x0020) return MEM[dir];

	// Periféricos
	switch (dir&0x1F) {
	case 0:	return irqen;
	case 1:	pflags&=~(1<<15); return timerval;
	case 2:	// UART RXD
		pflags&=~1;	// borra flag DV
		return uart_rx;
	case 3:	// SPI RX
		return (spicntl&0x8000) ? 0xfACE : 0xfC;
	case 4:	// PFLAGS
//		if ((cpu.nciclos-uart_tx_stamp)>UART_DEL) pflags|=6; // listo para TX
//		if ((cpu.nciclos-spi_stamp)>spi_delay) pflags&=~(1<<3);	// borra SPI busy
		return pflags;
	case 6:	return gpdir;
	case 7:	return gpout;
	default:
		return 0xffff;
	}

}

void wr_mem(uint16 dir,uint16 dato)
{
    int x,y;
    unsigned char c;
	MEM[dir]=dato;

	if ((dir&0xffe0)==0x0020) {	// Periféricos
		switch (dir&0x1F) {
		case 0:	irqen=dato&0x000f; break;
		case 1: timermax=dato; timerval=0; break;
		case 2:	// UART TXD
			pflags&=~6;	// borra flag THRE
			uart_tx_stamp=cpu.nciclos; // retardo hasta siguiente caracter
			putchar(dato); fflush(stdout); // imprime en stdout
			videomod=1;		// marca para no borrar en debug
			break;
		case 3:	// SPI TX	
			pflags|=1<<3;	// SPI busy
			spi_stamp=cpu.nciclos;
			spi_delay=((spicntl&0xff)+1)*2*8;
			if (spicntl&(1<<15)) spi_delay*=2;
			break;		
		case 4: hold=dato&0x3FF; pflags&=~(1<<15); break;
		case 5:	spicntl=dato; break;
		case 6:	gpdir=dato; break;
		case 7:	gpout=dato; break;
		}
	}
}

/*--------------------------------------------------------------------*/

void doflagsZN(int dd)
{
	if (!dd) cpu.flags|=ZF; else cpu.flags&=~ZF;
	if (dd&0x8000) cpu.flags|=NF; else cpu.flags&=~NF;
}
void doflagsCV(int dd, int da, int db, int cy )
{
	int a,b,d;
	a=(da>>15)&1;
	b=(db>>15)&1;
	d=(dd>>15)&1;
	// carry
	if (cy) cpu.flags|=CF; else cpu.flags&=~CF;
	// overflow
	if ((!a && !b && d) || (a && b && !d))
		cpu.flags|=VF; else cpu.flags&=~VF;
}

///////////////////////////////////////////////////////////////////////////////
// Ejecución de una instrucción
//     retorna nº de ciclos empleados
///////////////////////////////////////////////////////////////////////////////

extern inline int una_instr()
{
	int ra,rb,rd,op,fl,n,nof,nrori,db,da;
	int16 desp;
	int i,j;
	unsigned int nc;


	nc=cpu.nciclos;

	// Actualizamos flags de periféricos
	if ((cpu.nciclos-uart_tx_stamp)>UART_DEL) pflags|=6; // listo para TX (actualiza pflags)
	if ((cpu.nciclos-spi_stamp)>spi_delay) pflags&=~(1<<3);	// borra SPI busy

	// Comprobamos IRQs
	// bits de CPU.modo:
	//  0  :  entrada IRQ
	//  1  :  FF 1
	//  2  :  FF 2 = MODO (0=normal, 1=IRQ)
	cpu.modo&=~1;	
	if ((irqen&8) && (pflags&1)) {cpu.vector=0x0010; cpu.modo|=1;} // IRQ UART_RX
	else if ((irqen&4) && (pflags&2)) {cpu.vector=0x000C; cpu.modo|=1;} // IRQ UART_TX
	else if ((irqen&2) && (pflags&(1<<15))) {cpu.vector=0x0008; cpu.modo|=1;} // IRQ TIMER
	//else if ((irqen&1) && eint) {cpu.vector=0x0004; cpu.modo|=1;} // IRQ externa

	// actualiza modo (reg. de desplazamiento)
	if (cpu.modo&6) cpu.modo|=4;
	if (cpu.modo&3) cpu.modo|=2;

	if (cpu.pc==Trap) Trace=1;
    if (Trace) debug();

	// Cambio de modo normal a IRQ
	if ((cpu.modo&6)==2) {	// Entrando en IRQ
		cpu.pc0=cpu.pc;		// Intercabio de PC
		cpu.pc=cpu.vector;	// Vector IRQ
		i=cpu.flags0; cpu.flags0=cpu.flags;	cpu.flags=i; // Intercambio de flags
		cpu.nciclos++;
		return 1;
	}

	// Ejecución de instrucción
	op  = MEM[cpu.pc];
	fl  = cpu.flags;
	rb  = (op>>2)&7; 	// registro fuente B 
	n   = op&0xFF;		// literal
	nrori =(op&3) | (((op>>5)&3)<<2);	// literal para RORI
	nof = op&31;		// literal para LD/ST
	desp =op & 0xfff; if (desp & 0x800) desp |=0xf000;	// Daplazamiento en saltos
	desp++;
	ra=(op>>5) & 7;	// registro fuente A
	rd=(op>>8) & 7;	// registro destino

	i=op>>11;		// TIPO_IMM: RA = RD
	if (i>=2 && i<=10) ra=rd;

	da=cpu.r[ra]&0xffff;
	db=cpu.r[rb]&0xffff;

    /***** contamos el ciclo ******/
    cpu.nciclos++;

	//////////////////////////////////
	if((op&0x8000) || (op>>12)==7) {	// saltos
		if ((op>>12)==7) {			// JAL
			cpu.r[6]=(cpu.pc+1)&0xFFFF;
			cpu.pc=(cpu.pc+desp)&0xFFFF;
			cpu.nciclos++;
			return 2;
		} else {
		switch((op>>12)&7) {
		case 0:	if (fl&ZF)    {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JZ
				break;
		case 1:	if (!(fl&ZF)) {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JNZ
				break;
		case 2:	if (fl&CF)    {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JC
				break;
		case 3:	if (!(fl&CF)) {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JNC
				break;
		case 4:	if (fl&NF)    {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JMI
				break;
		case 5:	if (!(fl&NF)) {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JPL
				break;
		case 6:	if (fl&VF)    {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JV
				break;
		case 7:	              {cpu.pc=(cpu.pc+desp)&0xFFFF; cpu.nciclos++; return 2;}	// JR
				break;
		}
	  }
	} else {
		op&=0xF8E3;
		if (op==0x58E3) {			// RETI
			cpu.pc=cpu.r[rb];
			if (cpu.modo&4) {		// Si estamos en modo IRQ:
				if (cpu.modo&1) {	// si IRQ sigue activa
					cpu.pc=cpu.vector;	// Concatenamos interrupciones
				}else {				// si IRQ inactiva: pasamos a modo 0
					cpu.pc=cpu.pc0;
					cpu.pc0=cpu.vector;
					i=cpu.flags; cpu.flags=cpu.flags0; cpu.flags0=i;
					cpu.modo=0;
				}
			}else cpu.pc=cpu.r[rb];	// En modo normal RETI=JIND
			cpu.nciclos++; 
			return 2;
		}
		switch(op>>11) {
		case 0:
		case 1:		// 3REG
				switch(((op>>9)|op)&7){
				case 0:	// ADD
					j=da+db; 
					i=j>>16; j&=0xFFFF;
					cpu.r[rd]=j;
					doflagsCV(j,da,db,i);
					doflagsZN(j);
					break;
				case 1:	// SUB
					j=da+(db^0xFFFF)+1; 
					i=j>>16; j&=0xFFFF;
					cpu.r[rd]=j;
					doflagsCV(j,da,~db,i);
					doflagsZN(j);
					break;
				case 2:	// ADC
					j=da+db; 
					if (cpu.flags&CF) j++;
					i=j>>16; j&=0xFFFF;
					cpu.r[rd]=j;
					doflagsCV(j,da,db,i);
					doflagsZN(j);
					break;
				case 3:	// SBC
					j=da+(db^0xFFFF); 
					if (cpu.flags&CF) j++;
					i=j>>16; j&=0xFFFF;
					cpu.r[rd]=j;
					doflagsCV(j,da,~db,i);
					doflagsZN(j);
					break;
				case 4:	// AND
					cpu.r[rd]=j=da&db;
					doflagsZN(j);
					break;
				case 5:	// OR
					j=cpu.r[rd]=da|db;
					doflagsZN(j);
					break;
				case 6:	// XOR
					j=cpu.r[rd]=da^db;
					doflagsZN(j);
					break;
				case 7:	// BIC
					cpu.r[rd]=j=da&(db^0xFFFF);
					doflagsZN(j);
					break;

				}
				break;
		case 2:	// ADDI
				j=da+n; 
				i=j>>16; j&=0xFFFF;
				cpu.r[rd]=j;
				doflagsCV(j,da,db,i);
				doflagsZN(j);
				break;
		case 3: // SUBI
				j=da+(n^0xFFFF)+1; 
				i=j>>16; j&=0xFFFF;
				cpu.r[rd]=j;
				doflagsCV(j,da,~db,i);
				doflagsZN(j);
				break;
		case 4: // ADCI
				j=da+n; 
				if (cpu.flags&CF) j++;
				i=j>>16; j&=0xFFFF;
				cpu.r[rd]=j;
				doflagsCV(j,da,db,i);
				doflagsZN(j);
				break;
		case 5: // SBCI
				j=da+(n^0xFFFF); 
				if (cpu.flags&CF) j++;
				i=j>>16; j&=0xFFFF;
				cpu.r[rd]=j;
				doflagsCV(j,da,~db,i);
				doflagsZN(j);
				break;
		case 6: // ANDI
				cpu.r[rd]=j=da&n;
				doflagsZN(j);
				break;

		case 7: // ORI
				cpu.r[rd]=j=da|n;
				doflagsZN(j);
				break;
		case 8: // XORI
				cpu.r[rd]=j=da^n;
				doflagsZN(j);
				break;
		case 9: // CMPI
				j=da+(n^0xFFFF)+1; 
				i=j>>16; j&=0xFFFF;
				doflagsCV(j,da,~db,i);
				doflagsZN(j);
				break;
		case 0xA:	// LDI
				cpu.r[rd]=n;
				break;
				
		case 0x0B:	// 2REG
			if ((op&0x80)==0) {		// RORI
				j=cpu.r[rb]&0xffff;
				j=((j>>nrori) | (j<<(16-nrori))) & 0xFFFF;
				cpu.r[rd]=j;
				doflagsZN(j);
				break;
			}
		
			switch ((op|(op>>3))&0x1F) {
			case 0x00:	// SHR
				j=cpu.r[rb]&0xffff;
				i=j&1; j>>=1;
				cpu.r[rd]=j; doflagsCV(j,0,db,i); doflagsZN(j);
				break;
			case 0x01:	// SHRA
				j=cpu.r[rb]&0xffff;
				if (j&0x8000) j|=0x10000;
				i=j&1; j>>=1;
				cpu.r[rd]=j; doflagsCV(j,0,db,i); doflagsZN(j);
				break;
			case 0x02:	// ROR
				j=cpu.r[rb]&0xffff;
				i=j&1; j>>=1; if (cpu.flags&CF) j|=0x8000;
				cpu.r[rd]=j; doflagsCV(j,0,db,i); doflagsZN(j);
				break;
			case 0x03:	// SWAP
				j=cpu.r[rb]&0xffff;
				i=j>>8; j=(j<<8)|i;
				cpu.r[rd]=j; 
				break;
			case 0x04:	// NOT
				j=cpu.r[rb]&0xffff;
				j=cpu.r[rd]=(~j)&0xffff;
				doflagsZN(j);
				break;
			case 0x05:	// NEG
				j=cpu.r[rb]&0xffff;
				j=cpu.r[rd]=((~j)+1)&0xffff;
				doflagsZN(j);
				break;

			case 0x1E:	cpu.pc=cpu.r[rb];	// JIND
						cpu.nciclos++; 
						return 2;	
			case 0x1C:	cpu.pc++;			// LDPC
						j=cpu.r[rd]=rd_mem(cpu.pc&0xffff);	
						cpu.nciclos++;
						break;
			default:	Trace=1; goto incpc;	// ILEG
			}
			break;
		case 0x0C:	j=cpu.r[rd]=rd_mem((cpu.r[ra]+nof)&0xffff);	// LD
					doflagsZN(j);  
					cpu.nciclos++; 
					break;
		case 0x0D:	wr_mem((cpu.r[ra]+nof)&0xffff,cpu.r[rd]); 	// ST
					cpu.nciclos++; 
					break;
		}
	}


incpc:
	// Incrementa PC (los saltos no llegan aquí)
	cpu.pc=(cpu.pc+1)&0xffff;	
	return cpu.nciclos-nc;
}

/*--------------------------------------------------------------------*/

void reset_cpu()
{
    int i;
    cpu.pc=0;		/* PC inicial */
	cpu.modo=0;		// Sin interrupciones
    cpu.nciclos=0;	/* Contador de ciclos */
	cpu.flags=0;
    for (i=0;i<8;i++) cpu.r[i]=-1;
	// Periféricos que también se resetean
	irqen=0;
	gpdir=0;
	pflags=0x6;
	timerval=0; timermax=0xffff;
}

/*--------------------------------------------------------------------*/


void loadhex(char *fn)
{
    int i,dir,dato;
    char *p,*pp,buf[256];
    FILE *fp;
    
    if ((fp=fopen(fn,"r"))==NULL) exit(0);
    
    for (dir=0;;) {
        fgets(buf,255,fp);
		if (feof(fp)) break;
		p=buf;
		if (*p=='@') {
	   		dir=strtol(++p,&pp,16);
		   continue;
		}
	
		MEM[dir]=strtol(p,&pp,16);
		dir++;
    }
    fclose(fp);
}

void alarma() // Se llama periodicamente cada 40 ms
{
	int i;
	unsigned char a;

	if (!Trace) {
		i=read(0,&a,1);
		if (i==1) { uart_rx=a; pflags|=1;}
	}
}

void ctrlc()
{
    Trace=1;
}

main(int argc, char **argv)
{
	unsigned int i,j,nc;	
	struct itimerval t0,t1;
    struct sigaction act0,act1;
	FILE *pfpwm;
	unsigned int npwm=0;
          
	if (argc<2) {
	   printf("Uso: %s [opciones] fichero.hex\n",argv[0]);
	   exit(0);
	}
	
	for (i=0;i<80*24;i++) MEM[i+0x1000]=' ';  // CLS
	loadhex(argv[1]);

	stdinflags=fcntl(0, F_GETFL, 0);

    t0.it_interval.tv_sec=0;
    t0.it_interval.tv_usec=40000;	// alarma cada 40 ms
    t0.it_value=t0.it_interval;

    act0.sa_handler=alarma;
    act0.sa_flags=SA_RESTART;

    sigaction(SIGALRM,&act0,&act1);
    setitimer(ITIMER_REAL,&t0,&t1);
	
	signal(SIGINT,ctrlc);

	reset_cpu();
	cpu.vector=8;	// Vector de IRQ TIMER
	
	//////////////////////////////
	// Bucle principal Emulador
	//////////////////////////////

	if((pfpwm=fopen("pwm.log","w"))==NULL) {perror("fopen pwm.log"); exit(1);}

	Trace=1;
	for (i=0;;) {
	    while ((cpu.nciclos-i)<((FCLK+12)/25)){
			nc=una_instr();
			if (cpu.nciclos<i) {i=cpu.nciclos; continue;}
			// actualiza timer
			j=timerval+nc;
			while (j>timermax) {	// Desbordamiemto 
				j-=(timermax+1);	// ajuste de timer (se ha reiniciado)
				pflags|=(1<<15);	// Activar flag de IRQ
				curr=hold;			// Copiar registro PWM_HOLD a PWM_CURR
				if (npwm<2000) {	// guardamos los valores de PWM_CURR en un archivo
					npwm++; 		// hasta un límite...
									// Formato: Tiempo (en segundos) valor PWM (en decimal)
					fprintf(pfpwm,"%g %d\n",(float)(cpu.nciclos-j)/FCLK,curr);
					fflush(pfpwm);
				}
			}
			timerval=j;
		}
		i+=((FCLK+12)/25);	// Otros 40ms de simulación
	    pause();
	}
}
