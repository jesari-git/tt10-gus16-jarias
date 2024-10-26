#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "opcodes.h"

int muestra_instr(uint16_t cop, int pc)
{
	int ra,rb,rd,op,n,nof,nrori;
	int16_t desp;
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

void loadhex(char *fn,int modo)
{
    int i,j,dir,ddir=-1,w=0;
    short dato;
    char *p,*pp,buf[256];
    FILE *fp;
    
    if ((fp=fopen(fn,"r"))==NULL) exit(0);
    
	j=0;
    for (dir=0;;) {
        fgets(buf,255,fp);
		if (feof(fp)) break;
		p=buf;
		if (*p=='@') {
		   dir=strtol(++p,&pp,16);
		   putchar('\n');
		   if (modo==0) printf("     ");
		   printf ("        ORG   0x%04X\n",dir);
		   continue;
		}
	
		dato=strtol(p,&pp,16);
	
		if (modo==0) printf("%04X - %04X  ",dir,dato&0xffff);
		else printf("        ");
		muestra_instr(dato,dir);
		printf("\n");
		dir++;	
    }
}


main(int argc, char **argv)
{
	int i,modo=0;
	char *fn;

	if (argc<2) {
		printf("Uso: %s <-p 1/2> <-n> fichero.hex\n",argv[0]);
		exit(1);
	}
	for (i=1;i<argc;i++) {
		if (argv[i][0]=='-' && argv[i][1]=='n') { modo=1; continue;}
		if (argv[i][0]=='-' && argv[i][1]=='h') { 
			printf("Uso: %s <-n> fichero.hex\n",argv[0]);
			exit(0);
		}
		fn=argv[i];
	}
	printf("    ; CPUMODEL = 6\n");
    loadhex(fn,modo);  
	return 0;  
}

