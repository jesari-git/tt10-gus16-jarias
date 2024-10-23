#include <stdlib.h>
#include <stdio.h>

#define NW (65536+4)
unsigned int mem[NW];

main(int argc, char **argv)
{
	int i,dir,dato;
	char buf[256];
	FILE *fp;
	
	for (i=0;i<NW;i++) mem[i]=-1;
	
	if ((fp=fopen(argv[1],"r"))==NULL) exit(1);
	dir=0;
	while(1){
		fgets(buf,256, fp);
		if (feof(fp)) break;
		//printf("%s",buf);
		if (buf[0]=='@') {
			dir = strtoul(&buf[1],NULL,16);
			printf("dir=0x%04X\n",dir);
		} else {
			dato=strtoul(buf,NULL,16);
			mem[dir++]=dato;
		}
	}
	fclose(fp);
	
	if ((fp=fopen(argv[2],"wb"))==NULL) exit(1);
	for (i=0;i<NW;i++) if (mem[i]!=-1) break;
	for (dir=NW-1;dir;dir--) if (mem[dir]!=-1) break;
	for (;i<=dir;i++) {
		fwrite(&mem[i],2,1,fp);
	}
	fclose(fp);

}
