#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include "opcodes.h"

// Lista de etiquetas
#define MAXL 100000
struct {
   unsigned int dir;
   char name[64];
} labtab[MAXL];
int nlabel=0;

// variables globales:
FILE *fp;		// fichero de entrada
#define MAXINC (8)	// máximo nivel de anidamiento en "include"
FILE *fpin[MAXINC]; // pila de include
int ninc=0;		// nivel actual de include

FILE *fpo;		// fichero de salida hexadecimal
FILE *fplst;	// fichero de listado
int cdir;		// dirección de memoria actual
int optipo;		// tipo de op-code
int nlin[MAXINC]; // pila de nº de línea
int nl;			// número de línea

char fnin[MAXINC][256];	// pila de nombres


int chkexpr(char *p);

// valor de número
int checknum(char *p)
{
    int i;
    // Primer caracter debe ser [0-9]
    if (*p<'0' || *p>'9') return -1;
    // Si "0X.." entonces es hexadecimal
    if (p[0]=='0' && p[1]=='X') {
    	p=&p[2]; i=0;
		while ((*p>='0' && *p<='9') || (*p>='A' && *p<='F')) {
	    	i<<=4;
	    	if (*p>='0' && *p<='9') i+=*p-'0';
	    	else i+=*p-'A'+10;
	    	p++;
		}
		return i;
    } else return atoi(p);
}

// busca mnemónico
int inststat[128];

int checknemo(char *p)
{
    int i;
    for (i=0;instr[i].tipo;i++) {
		if (strcmp(instr[i].nemo,p)==0) {
			optipo=instr[i].tipo;
			inststat[i]++;
			return instr[i].opcode;
		}
    }
    return -1;
}

// busca registro. Si pointer !=0 el registro debe estar entre paréntesis
int regdesp;
int checkreg(char *p,int pointer)
{
    int i,j;
    char buf[32],*p0,*p1;
    const char *reg[]={ "R0","R1","R2","R3","R4","R5","R6","R7"}; 
    for (i=0;i<8;i++) {
       if (pointer==0 && strcmp(reg[i],p)==0) return i;
       if (pointer==1) {
       		sprintf(buf,"(%s)",reg[i]);
       		if (strcmp(buf,p)==0) {regdesp=0; return i;}
       		sprintf(buf,"(%s+",reg[i]);
       		if (strstr(p,buf)) {
       			//printf(">%s<  ",p);
       			p0=p; while (*p0!='+') p0++;
       			p1=p0; j=1;
       			do {
       				p1++;
       				if (*p1==0) {regdesp=-1; return -1;}
       				if (*p1=='(') j++;
       				if (*p1==')') j--;
       				//printf("%c (%d)\n",*p1,j);
       			} while (j);
       			*p1=0; p0++;
       			//printf(">%s<  ",p0); 
       			regdesp=chkexpr(p0);
       			return i;
       		}
       }
    }
    return -1;
}

///////////////////////////////////////////////////////////////////////
// busca el primer token de la cadena apuntada por ptok (var. global)
// eliminando los caracteres de 'delim1' por delante del token
// y terminando el token cuando encuentra algún caracter de 'delim2'
///////////////////////////////////////////////////////////////////////
char delim;		// delimitador encontrado
char *ptok;		// punteto al tokem. Queda apuntando al siguiente tokem
char tok[256];	// buffer en el que se copia el tokem

int scantok()
{
    const char *delim1=" \t";
    const char *delim2="\n; \t:=,";
    char *pp;
    
    while (strchr(delim1,*ptok) && *ptok) ptok++;
    pp=ptok;

	comascii:
	while (!strchr(delim2,*ptok) && *ptok) ptok++;
	// el terminador puede ser un ascii entre comillas:
	if (*(ptok-1)=='\'' && *(ptok+1)=='\'') {ptok++; goto comascii;}

    delim=*ptok;
    *ptok++=0;
    strcpy(tok,pp);
    //printf(">%s< delim:>%c<\n",tok,delim);
}

////////////////////////
// valor de etiquetas
////////////////////////
int etival(char *peti)
{
	int i;
	for (i=0;i<nlabel;i++) {
		if (strcmp(labtab[i].name,peti)==0) return labtab[i].dir;
	}
	return -1;
}

////////////////////////////////////////////////
// cambia + por - o * por / en una subexpresión

void opone(char *p, int tipo)
{
	char a;
	while(1) {
		a=*p;
		if (tipo==0) {
			if (a=='-') *p='+';
			if (a=='+') *p='-';
		} else {
			if (a=='*') *p='/';
			if (a=='/') *p='*';
		}
		p++;
		if (a=='(' || a==')' || a=='\n' || a=='\r' || a==0) return; 
	}
}
/////////////////////////////////
//   Evaluador de expresiones
//   (función recursiva)
/////////////////////////////////

int chkexpr(char *p)
{
	int i,una=0,a,b;
	char *pp,*pq;
	static int interix=0, interbuf[16];

	//printf(">%s<\n",p);

	// operadores unarios: se procesan después de evaluar el resto de la expresión
	if (*p=='>') {una=1; p++;}		// byte alto
	if (*p=='<') {una=2; p++;}		// byte bajo
	if (*p=='~') {una=3; p++;}		// complemento a 1
	if (*p=='-') {una=4; p++;}		// complemento a 2
	// dirección actual
	if (*p=='.' && !p[1]) {
		i=cdir;	
		goto ckxpsh;
	}
	// pseudovariable (resultado de paréntesis)
	if (*p=='?' && !p[2]) {
		i=p[1]-'A';
		i=interbuf[i];
		goto ckxpsh;
	}
	// caracter ASCII
	if (*p=='\'') {
		i=*++p;
		if (i=='\\') {
			switch (*++p){
			case 'r': i=0x0d; break;
			case 'n': i=0x0a; break;
			case 't': i=0x09; break;
			case 'b': i=0x08; break;
			case 'd': i=0x7f; break;
			case '"': i=0x22; break;
			case '\'': i=0x27; break;
			case '\\': i=0x5c; break;
			case 'e': i=0x1b; break;
			}
		}
		if (p[1]!='\'') {fprintf(stderr,"(%d) Error: Unmatched single quote: %s\n",nl,tok); exit(1);}
		// Creamos pseudovariable para el caracter y seguimos evaluando
		p[0]='?'; p[1]='A'+interix;
		interbuf[interix]=i; interix=(interix+1)&15;
		i=chkexpr(p);
		goto ckxpsh;
	}
	// Paréntesis: sustituirlos de forma recursiva por pseudovariables
	while(1) {
		if (!(pp=strrchr(p,'(') ) ) break;
		if (!(pq=strchr(pp,')') )) {fprintf(stderr,"(%d) Error: Unmatched parenthesis: %s\n",nl,tok); exit(1);}
		*pq=0;
		i=chkexpr(&pp[1]);
		interbuf[interix]=i;
		// condensa parentesís a pseudovariable '(...)' -> '?A'
		*pp++='?'; *pp++='A'+interix;
		pq++;
		do { i=*pq++; *pp++=i;} while (i);
		interix=(interix+1)&15;	// nueva pseudovariable
	}

	// operadores binarios (primero los de menor prioridad)
	if (pp=strchr(p,'<'))
		if (pp[1]=='<') {*pp++=0; *pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a<<b; goto ckxpsh; }
		else {fprintf(stderr,"(%d) Error: '<' not unary: %s\n",nl,p); exit(1);}
	if (pp=strchr(p,'>'))
		if (pp[1]=='>') {*pp++=0; *pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a>>b; goto ckxpsh; }
		else {fprintf(stderr,"(%d) Error: '>' not unary: %s\n",nl,p); exit(1);}
	if (pp=strchr(p,'^')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a^b; goto ckxpsh; }
	if (pp=strchr(p,'|')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a|b; goto ckxpsh; }
	if (pp=strchr(p,'&')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a&b; goto ckxpsh; }
	if (pp=strchr(p,'-')) {*pp++=0; a=chkexpr(p); opone(pp,0); b=chkexpr(pp); i=a-b; goto ckxpsh; }
	if (pp=strchr(p,'+')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a+b; goto ckxpsh; }
	if (pp=strchr(p,'*')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a*b; goto ckxpsh; }
	if (pp=strchr(p,'/')) {*pp++=0; a=chkexpr(p); opone(pp,1); b=chkexpr(pp); i=a/b; goto ckxpsh; }
	if (pp=strchr(p,'%')) {*pp++=0; a=chkexpr(p); b=chkexpr(pp); i=a%b; goto ckxpsh; }

	// números o etiquetas
	if (*p=='?' && !p[2]) { // pseudovariable (de paréntesis)
		i=p[1]-'A';
		i=interbuf[i];
	} else if ((i=checknum(p))<0)	// número
		if ((i=etival(p))<0) {	// etiqueta
	    	fprintf(stderr,"(%d) Error: Unknown label: %s\n",nl,tok);
	    	exit(1);
		}
ckxpsh:
	// operadores unarios
	switch(una) {
		case 1:	i=(i>>8)&0xff; break;	// byte alto
		case 2:	i&=0xff; break;			// byte bajo
		case 3:	i=~i; break;	// complemento a 1
		case 4:	i=-i; break;	// complemento a 2
	}
	return i; 
}

///////////////////////////////////////////
// Cadenas ASCII
///////////////////////////////////////////

// Pasa cadena a mayúsculas, evitando el texto entre comillas
void upcase(char *p)
{
	int fl=0;
	char a;

	while (a=*p) {
		if (a=='\\') {p+=2; continue;} 	// caracteres con escape
		if (a=='\'' || a=='"') fl^=1;	// entre comillas no se pasa a mayúsculas
		if (!fl) *p=toupper(a);
		p++;
	}
}

// Calcula tamaño en palabas de cadena entre comillas
int ascizlen(char *p)
{
	int i;
	unsigned char a;
	//printf(">%s<",p);
	while (*p && *p!='"') p++;
	i=0; p++;
	while (a=*p) {
		p++;
		if (a=='\\') {
			i++; 
			if (*p=='x' || *p=='X') p=&p[2];
			p++;
			continue;
		} // caracteres con escape
		if (a=='"') break;
		i++;
	}
	i++; // por el cero terminador

	//printf("ascii len=%d\n",i);
	return (i+1)>>1;	// redondeo hacia arriba
}

///////////////////////////////////////////
// PASO 1
// Buscamos los valores de las etiquetas
///////////////////////////////////////////
#define BLEN (1023)
void pass1(char *fname)
{
    //FILE *fp;
    int i,op;
    char *p,*pp,buf[BLEN+1];
    
    if ((fp=fopen(fname,"r"))==NULL) exit(0);
    
	cdir=nl=0;
    for (;;) {
		// lee línea
        fgets(buf,BLEN,fp);
		if (feof(fp)) {
			if (!ninc) break;
		    else {fp=fpin[--ninc]; nl=nlin[ninc];}
		}
		nl++;
		// a mayúsculas salvo caracteres ascii entre comillas simples
		//p=buf; while (*p) {if (*p=='\'') p+=2; else {*p=toupper(*p); p++;}}
		upcase(buf);
		
		ptok=buf;
uno:	scantok();	
		if (strlen(tok)==0) continue;
		if (delim==':' || delim=='=') {
		    // etiqueta
			if (etival(tok)>=0) {
				fprintf(stderr,"Error: duplicate label: %s\n",tok);
				exit(1);
			}			
		    strcpy(labtab[nlabel].name,tok);
		    if (delim==':') labtab[nlabel++].dir=cdir;
			else {
				scantok();
				labtab[nlabel++].dir=chkexpr(tok)&0xFFFF;
				continue;
			}
		    goto uno; // seguimos buscando mnemonico
		}
	 
		if(strcmp(tok,"INCLUDE")==0) {
		    scantok();
		    for (i=1;i<BLEN;i++) if (tok[i]=='\"') break;
		    if (i==BLEN) {
		    	if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]);
		    	fprintf(stderr,"(%d) Error: include\n",nl); exit(1);
		    }
		    tok[i]=0;
			//printf("include >%s<\n",&tok[1]);
			nlin[ninc]=nl;
			strncpy(&fnin[ninc][0], &tok[1], BLEN);
			fpin[ninc++]=fp;
			if (ninc>=MAXINC) {
				fprintf(stderr,"%s (%d) Error: include stack overflow\n",&fnin[ninc-1][0],nl); 
				exit(1);
			}
			nl=0;
			if ((fp=fopen(&tok[1],"r"))==NULL){
				if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
				fprintf(stderr,"(%d) Error: include \"%s\"\n",nl,&tok[1]); exit(1);
			}
	    	continue;
		}

		if(strcmp(tok,"ORG")==0) {
		    scantok();
			i=chkexpr(tok)&0xFFFF;
	    	cdir=i;
	    	continue;
		}
		if(strcmp(tok,"WORD")==0){
		    cdir++;
		    continue;
		} 
		if(strcmp(tok,"ASCZBE")==0 || strcmp(tok,"ASCZLE")==0){
		    cdir+=ascizlen(ptok);
		    continue;
		} 
		if(checknemo(tok)>=0) {
		    cdir++;
		    continue;
		}
		
		if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
		fprintf(stderr,"(%d) Error: >%s<\n",nl,tok);
		exit(1);

    }
    
    fprintf(fplst,"; Label listing -----------------------------------\n\n");
    for (i=0;i<nlabel;i++) {
         fprintf(fplst,"%04X   (%5d)   %s\n",labtab[i].dir,labtab[i].dir,labtab[i].name);
    }
    fprintf(fplst,"\n; Program listing ----------------------------------\n\n");

}

///////////////////////////////////
// PASO 2
// generación de código
///////////////////////////////////

// salida hexadecimal y listado
void emit(int dir, int dato, char *orig)
{
    static int bdir=0;
    int i,j;

    if (dir>=0) fprintf(fplst,"%04X  -  %04X   %s",dir,dato,orig);

    if (dir==bdir+1) {
        bdir=dir;
		fprintf(fpo,"%04X\n",dato);
    }else {
        bdir=dir;
        fprintf(fpo,"@%04X\n",bdir);
        fprintf(fpo,"%04X\n",dato);
    }
}

// byte hexadecimal (para escapes \xDD)
int hexbyte(char *p)
{
	int i,d,a;
	char *p0=p;
	for (i=d=0;i<2;i++) {
		d<<=4;
		a=*p++;
		if (a>='a') a-=32;	// mayusculas
		if ((a>='0' && a<='9') || (a>='A' && a<='F')) {
			if (a>='A') a-=7;
			a-='0';
			d+=a;
		} else {
			if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
		    fprintf(stderr,"(%d) Error, not Hex value : %c%c\n",nl,p0[0],p0[1]);
		    exit(1);
		}
	}
	return d;
}

// Cadenas de caracteres empaquetadas: 2 caracteres/palabra
// endian=0: Big endian, endian=1: little endian
void ascizemit(char *p, char *orig, int endian)
{
	int i,d,esc;
	unsigned char a;

	while (*p && *p!='"') p++;
	i=d=esc=0; p++;
	while (1) {
		a=*p++; 
		// caracteres con escape
		if (a=='\\' && !esc) {esc=1; continue;}
		if (esc) {
			esc=0;
			switch (a) {
			case 'n':	a='\n'; break;
			case 'r':	a='\r'; break;
			case 'b':	a='\b'; break;
			case 'd':	a=0x7F; break;
			case 't':	a='\t'; break;
			case '"':	goto shchar;
			case 'e':	a=0x1b; break;
			case 'x': 	a=hexbyte(p); p=&p[2]; break;
			}
		}
		if ((!a) || (a==0x22)) break;	
shchar:	if (endian) {	// Little endian
			d>>=8;
			d|=a<<8;			
		}else{
			d<<=8;		// Big endian
			d|=a;
		}
		if (++i==2) {
			emit(cdir++,d,orig);
			orig="\n";
			i=d=0;
		}
	}
	if (i) if (endian) d>>=8; else d<<=8;
	emit(cdir++,d,orig);
}

// PASO 2
void pass2(char *fname)
{
    //FILE *fp,*fpo;
    int i,op,ra,rb,rd,n,disp;
    char *p,*pp,buf[BLEN+1],bf[BLEN+1];
    
    bzero (inststat,sizeof(inststat));
    
    if ((fp=fopen(fname,"r"))==NULL) exit(0);

	cdir=0;  
    for (nl=0;;) {
        fgets(buf,BLEN,fp);
		nl++;
		//printf(">%s<\n",buf);
		if (feof(fp)) {
			if (!ninc) break;
		    else {
		    	fp=fpin[--ninc]; nl=nlin[ninc];
		    	fprintf(fplst,"%04X  -         ; END of INCLUDE\n",cdir);
			}
		}

		// a mayúsculas salvo caracteres ascii entre comillas simples
		//p=buf; while (*p) {if (*p=='\'') p+=2; else {*p=toupper(*p); p++;}}
		upcase(buf);
	
		strcpy(bf,buf);	// guardamos original para el listado
		ptok=bf;
dos:
		scantok();
		if (delim=='=') {	// asignación de símbolo: ignorar
			fprintf(fplst,"%04X  -         %s",cdir,buf);
			continue;
		}
	
		switch(delim){
		  case ':':	// etiqueta: ignorar en esta fase
		  	goto dos;
		  case '\n':    
		  case ';':
		  case 0:
			if ((op=checknemo(tok))>=0) {
				if (optipo!=TIPO_RETI) {
				    fprintf(stderr,"(%d) Error, too few operands: %s\n",nl,tok);
				    exit(1);
				} else {
					emit(cdir,op,buf);
					cdir++;
					continue;
				}
			}
			fprintf(fplst,"%04X  -         %s",cdir,buf);
			continue;	  
		  
		  case ' ':
		  case '\t':	// instruccion/directiva
			if(strcmp(tok,"INCLUDE")==0) {
			    scantok();
			    for (i=1;i<BLEN;i++) if (tok[i]=='\"') break;
			    if (i==BLEN) {
			    	if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]);
			    	fprintf(stderr,"(%d) Error: include\n",nl); exit(1);
			    }
			    tok[i]=0;
				//printf("include >%s<\n",&tok[1]);
				nlin[ninc]=nl;
				strncpy(&fnin[ninc][0], &tok[1], BLEN);
				fpin[ninc++]=fp;
				if (ninc>=MAXINC) {
					fprintf(stderr,"%s (%d) Error: include stack overflow\n",&fnin[ninc-1][0],nl);
					exit(1);
				}
				nl=0;
				if ((fp=fopen(&tok[1],"r"))==NULL){
					if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					fprintf(stderr,"(%d) Error: include \"%s\"\n",nl,&tok[1]); exit(1);
				}
				fprintf(fplst,"%04X  -         %s",cdir,buf);
		    	continue;
			}

		 	if (strcmp(tok,"ORG")==0) {
			    scantok();
			    i=chkexpr(tok)&0xFFFF;
				fprintf(fplst,"%04X  -         %s",cdir,buf);
				cdir=i;
			    break;
			}
		  	if (strcmp(tok,"WORD")==0) {
			    scantok();
				i=chkexpr(tok)&0xFFFF;
			    emit(cdir,i,buf);
			    cdir++;
			    break;	    
			}
			if(strcmp(tok,"ASCZBE")==0){
		    	ascizemit(ptok,buf,0);
		    	break;
			} 
			if(strcmp(tok,"ASCZLE")==0){
		    	ascizemit(ptok,buf,1);
		    	break;
			} 
		
			op=checknemo(tok);
			if (op<0) {
				if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
			    fprintf(stderr,"(%d) Error, Unknown mnemonic : %s\n",nl,tok);
			    exit(1);
			} else {
			    switch(optipo) {
			    case TIPO_3REG:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					scantok();
					if ((ra=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					scantok();
					if ((rb=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					emit(cdir,op|(rd<<8)|(ra<<5)|(rb<<2),buf);
					break;
	
				case TIPO_IMM:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					scantok();
					i=chkexpr(tok)&0xFFFF;
					if (i>255) {if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
						fprintf(stderr,"(%d) Error: Value out of range: %s\n",nl,tok); exit(1);}
					emit(cdir,op|(rd<<8)|i,buf);
					break;
				case TIPO_RORI:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					scantok();
					if ((rb=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					scantok();
					i=chkexpr(tok)&0xFFFF;
					if (i>15) {if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
						fprintf(stderr,"(%d) Error: Value out of range: %s\n",nl,tok); exit(1);}
					emit(cdir,op|(rd<<8)|((i>>2)<<5)|(rb<<2)|(i&3),buf);
					break;	
				case TIPO_2REG:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					scantok();
					if ((rb=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					emit(cdir,op|(rd<<8)|(rb<<2),buf);
					break;
		
				case TIPO_LD:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					scantok();
					if ((ra=checkreg(tok,1))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					if (regdesp>31) {
						if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
						fprintf(stderr,"(%d) Error, too big offset %s)\n",nl,tok);
					  	exit(1);
					}
					emit(cdir,op|(rd<<8)|(ra<<5)|regdesp,buf);
					break;
	
				case TIPO_ST:
					scantok();
					if ((ra=checkreg(tok,1))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					if (regdesp>31) {
						if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
						fprintf(stderr,"(%d) Error, too big offset %s)\n",nl,tok);
					  	exit(1);
					}
					scantok();
					if ((rb=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok);
					   exit(1); 
					}
					emit(cdir,op|(ra<<5)|(rb<<8)|regdesp,buf);
					break;
		
				case TIPO_JIND:
					scantok();
					if ((rb=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					emit(cdir,op|(rb<<2),buf);
					break;

				case TIPO_RETI:
					emit(cdir,op,buf);
					break;
	
				case TIPO_LDPC:
					scantok();
					if ((rd=checkreg(tok,0))<0) {
					   if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					   fprintf(stderr,"(%d) Error, invalid register: %s\n",nl,tok); 
					   exit(1);
					}
					emit(cdir,op|(rd<<8),buf);
					//i=chkexpr(tok)&0xFFFF;
					//if (i>255) {fprintf(stderr,"(%d) Error: Valor fuera de rango: %s\n",nl,tok); exit(1);}
					//emit(cdir,op|i,buf);
					
					break;
		
				case TIPO_JR:
					scantok();
					i=chkexpr(tok)&0xFFFF;
					disp=i-(cdir+1);	// con pipeline el PC va una posición por delante
					if (disp>2047 || disp<-2048){
					    if (ninc) fprintf(stderr,"%s ",&fnin[ninc-1][0]); 
					    fprintf(stderr,"(%d) Error: Jump offset out of range %s\n",nl,tok);
					    exit(1);
					}
					disp&=0xFFF;
					emit(cdir,op|disp,buf);
					break;					
			    }
			    cdir++;
			}
		}
    }
    fclose (fp);
    
    //emit(-1,0,"\n"); // Vaciamos el buffer
}
 
int main(int argc, char **argv)
{
	int i,w,n;
	uint16_t dir,op;
	FILE *fp;
	char *fni,*fno="out.hex", *fnl="out.lst", *fns=NULL;

	for (i=1;i<argc;i++) {
		if (argv[i][0]=='-' && argv[i][1]=='o') {fno=argv[++i]; continue;}
		if (argv[i][0]=='-' && argv[i][1]=='l') {fnl=argv[++i]; continue;}
		if (argv[i][0]=='-' && argv[i][1]=='s') {fns=argv[++i]; continue;}
		fni=argv[i];
	}

	if ((fpo=fopen(fno,"w"))==NULL) exit(0);
	if ((fplst=fopen(fnl,"w"))==NULL) exit(0);
	printf("\nassembling: %s...\n",fni);
	fprintf(fplst,"\nProcessor: GUS16 v6\n\n");
	

	// etiqueta predefinida con el modelo de CPU
	labtab[0].dir=6;
	strcpy(labtab[0].name,"CPUMODEL");
	nlabel=1;

	pass1(fni);
	pass2(fni);
	
	fclose(fpo);
	fclose(fplst);
	printf("OK,  object: %s,  listing: %s\n\n",fno,fnl);
	
	if (fns) {
		if ((fp=fopen(fns,"w"))==NULL) exit(0);
		for (i=0;instr[i].tipo;i++) {
			fprintf(fp,"%4d %s\n",inststat[i],instr[i].nemo);
		}
		fclose(fp);
		printf("Instruction statistics: %s\n\n",fns);
	}
	
	return 0;
}
