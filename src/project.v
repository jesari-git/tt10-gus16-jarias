/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`define EN_PWM

//`include "cpuV6.v"
//`include "uart_simple.v"

module tt_um_gus16 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

/*
  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};
*/  
wire reset = ~rst_n;
assign uo_out={xweb,xoeb,gpo,txd,pwmout,xlah,xlal,xbh};
assign rxd=ui_in[3];
wire _unused = &{ ena, 1'b0};

/////////////////////////////// MEMORY ////////////////////////////////
//

parameter FCLK=24000000;
parameter BAUD=115200;

//////////////////////// BUSSES ////////////////////////
wire [15:0]cdi;	// CPU Data bus, Input
wire [15:0]cdo;	// CPU Data bus, Output
wire [15:0]ca;	// CPU Address bus
wire we;		// Write Enable

/////////////////////////////// MEMORY ////////////////////////////////
// Internal boot ROM (32 words), Combinational

wire iromcs = (ca[15:5]==0);

reg [15:0]irom[0:31];
wire [15:0]romdo = irom[ca[4:0]];

//initial $readmemh("rom_boot.hex", irom);
initial begin
irom[ 0]=16'h5722;
irom[ 1]=16'h60E0;
irom[ 2]=16'h484C;
irom[ 3]=16'h9FFD;
irom[ 4]=16'h68E0;
irom[ 5]=16'h700B;
irom[ 6]=16'h0A01;
irom[ 7]=16'h7009;
irom[ 8]=16'h0B01;
irom[ 9]=16'h7007;
irom[10]=16'h0C01;
irom[11]=16'h7005;
irom[12]=16'h6840;
irom[13]=16'h1201;
irom[14]=16'h1B01;
irom[15]=16'h9FFB;
irom[16]=16'h58F2;
irom[17]=16'h60E0;
irom[18]=16'h61E0;
irom[19]=16'h5944;
irom[20]=16'h0805;
irom[21]=16'h58FA;
end
	
////////////////////////////////////////////////
// External SRAM (8bit + address latches)

reg [1:0]ckd=0;
always @(posedge clk or posedge reset) if (reset) ckd<=0; else ckd<=ckd+1;

wire cksys = ~ckd[1];			// System clock

wire enx = 1'b1; //(~iocs)&(~iromcs);	// External memory selected

wire xlal = (ckd==2'b00) & enx;				// latch address low  (for '373)
wire xlah = (ckd==2'b01) & enx;				// latch address high (for '373)
wire xbh  = ckd[0] & enx;						// high byte (A[0] in SRAM)
wire xoeb = ~((~we) & ckd[1] & enx);			// /OE for SRAM
wire xweb = clk | (~ckd[1]) | (~we) | (~enx);	// /WE for SRAM

// 8-bit BUS mux
wire [7:0]d8o[0:3];
assign d8o[0]= ca[7:0];
assign d8o[1]= ca[15:8];
assign d8o[2]=cdo[7:0];
assign d8o[3]=cdo[15:8];
assign uio_out=d8o[ckd];
wire xnoe=(ckd[1]&(~we))|(~enx);
assign uio_oe=xnoe ? 8'h00 : 8'hff;

// input register for low byte
reg [7:0]xdl;
always @(posedge clk) if (ckd==2'b10) xdl<=uio_in;

wire [15:0]xdi = {uio_in,xdl}; // data input (word) from external RAM

//////////////////////////////////////////////////
//////					CPU					//////
//////////////////////////////////////////////////

assign cdi = iocs ? iodo : (iromcs ? romdo : xdi);

wire stopcpu; // stop CPU if 1
wire cclk = cksys | stopcpu;

`ifdef SIM
CPU_GUSV6 #(.VECTORBASE(16'h0000)) GUScpu0( 
`else
CPU_GUSV6 #(.VECTORBASE(16'h0100)) GUScpu0( 
`endif
	.clk(cclk), .we(we), .ca(ca), .cdo(cdo), .cdi(cdi), 
	.reset(reset), .irq(irq), .ivector(ivector)
);

///////////////////////////////
// Interrupts

// IRQS
wire [3:0]irqs={pwmirq&irqen[3] ,tflag& irqen[2], uflags[1] & irqen[1], uflags[0] & irqen[0]};
wire irq = |irqs;
wire [2:0]ivector = irqs[0] ? 3'd0 : (irqs[1]? 3'd1 : ( irqs[2]? 3'd2: 3'd3) );

/////////////////////////////////////////////////////////
///////////////////// Peripherals ///////////////////////
/////////////////////////////////////////////////////////

wire iocs;		// IO select ($0020 to $003F)

assign iocs=(ca[15:5]==11'b00000000001);
// Write strobes
wire iowe0=(we)&(iocs)&(ca[2:0]==0);
wire iowe1=(we)&(iocs)&(ca[2:0]==1);
wire iowe2=(we)&(iocs)&(ca[2:0]==2);
wire iowe3=(~stopcpu)&(we)&(iocs)&(ca[2:0]==3);
wire iowe4=(we)&(iocs)&(ca[2:0]==4);
//wire iowe5=(we)&(iocs)&(ca[2:0]==5);
//wire iowe6=(we)&(iocs)&(ca[2:0]==6);
//wire iowe7=(we)&(iocs)&(ca[2:0]==7);
// Read strobes
wire iore2=(~we)&(iocs)&(ca[2:0]==2);
wire iore3=(~stopcpu)&(~we)&(iocs)&(ca[2:0]==3);

///////////////////////////////
// IRQEN reg
reg [3:0]irqen=0;	
always @(posedge cclk or posedge reset ) 
	if (reset) irqen<=0;
	else irqen <= iowe0 ? cdo[3:0] : irqen;

///////////////////////////////
// Timer
`ifdef EN_TIMER
// prescaler for 1MHz timer clk
localparam PRESC=FCLK/4/1000000;
localparam NBPRE=$clog2(PRESC);
reg [NBPRE-1:0]presc=0;
wire prestc = &(presc | (~(PRESC-1)) );

reg [15:0]tmax;
reg [15:0]timer;
reg tflag;
wire timetc = (timer==tmax);
always @(posedge cksys or posedge reset) begin
	if (reset) begin 
		presc<=0;
		timer<=0;
		tmax<=16'hffff;
		tflag<=0;
	end else begin
		presc <= (iowe3 |prestc) ? 0 : presc+1;
		timer <= (iowe3 | (timetc & prestc)) ? 0 : timer + prestc;
		tmax  <=  iowe3 ? cdo : tmax;
		tflag <= (timetc & prestc) ? 1 : ((iowe3 | iore3)? 0 : tflag);
	end 
end
`else
wire tflag=0;
wire [15:0]timer=16'hxxxx;
`endif

/////////////////////////////
// PWM
`ifdef EN_PWM
parameter PWMBITS=8;
reg [PWMBITS-1:0]pwmhold;
always @(posedge cclk) if (iowe1) pwmhold<=cdo[PWMBITS-1:0];

reg [PWMBITS-1:0]pwmc;
reg [PWMBITS-1:0]pwmbuf;
reg pwmout;
reg pwmirq;
wire pwmtc = &pwmc[PWMBITS-1:1];	// terminal count: 2^n - 2
wire pwmzc = (pwmc==0);				// zero count

always @(posedge cksys or posedge reset) begin
	if (reset) begin
		pwmc<=0;
		pwmout<=0;
		pwmirq<=0;
	end else begin
		pwmc<=pwmtc ? 0 : pwmc+1;
		if (pwmzc) pwmbuf<=pwmhold;
		pwmout<= (pwmc==pwmbuf) ? 0 : (pwmzc ? 1 : pwmout);
		pwmirq<= pwmzc ? 1 : (iowe1  ? 0 : pwmirq);
	end
end
`else
wire pwmout=0;
wire pwmirq=0;
`endif

/////////////////////////////
// GPOUT

reg gpo;
always @(posedge cclk ) gpo <= iowe4 ? cdo[0] : gpo; 


/////////////////////////////
// I/O data to CPU MUX
reg [15:0]iodo;
always@*
  case (ca[2:0])
     0 : iodo <=  {15'h0,irqen}; // IRQ Enable
     1 : iodo <=  {tflag,10'h0,pwmirq,uflags}; // PFLAGS
     2 : iodo <=  {8'h0,urxdata}; // UART data
     3 : iodo <=  timer;
     4 : iodo <=  {8'b0,ui_in[7:4],ui_in[2:0],gpo};
     default : iodo <= 16'hxxxx;
  endcase

assign stopcpu = (iore2 & (~uflags[0])) | (iowe2&(~uflags[1]));

/////////////////////////////
// UART
localparam DIVIDER=(FCLK/4+(BAUD/2))/BAUD; 

wire [7:0]urxdata;
wire [3:0]uflags;
wire txd,rxd;

UART_core #(.DIVIDER(DIVIDER)) uart0 
	( .clk(cksys), .reset(reset), .d(cdo[7:0]), .wr(iowe2&(~stopcpu)),
		.rd(iore2&(~stopcpu)), .q(urxdata),
		.rxvalid(uflags[0]), .txrdy(uflags[1]),
		.rxoverr(uflags[2]), .rxframeer(uflags[3]),
		.nstop(1'b0),
		.txd(txd), .rxd(rxd)
	);

endmodule


//------------------------------------------------------------------------------------------
//------------------------------------------------------------------------------------------
// CPU GUS16 v6 (new instruction set) 						Jesús Arias (2023)
//------------------------------------------------------------------------------------------
//------------------------------------------------------------------------------------------
module CPU_GUSV6(
output [15:0]ca,	// Core Address
output [15:0]cdo,	// Core Data Output
output we,			// Write Enable
input  [15:0]cdi,	// Core Data Input
input  clk,			// Clock
input  reset,		// async. Reset (ative high)
input  irq,			// Interrupt Request
input  [2:0]ivector	// Interrupt vector
);

parameter VECTORBASE = 16'h0000;
parameter REGLINK = 3'd6;
assign we = st;

//------------------------------------------
//------------ REGISTER BANK ---------------
//------------------------------------------

wire [15:0]rega;	// output A
wire [15:0]regb;	// output B
wire [15:0]busd;	// input D (destination)
wire [2:0]aa;		// A address
wire [2:0]ba;		// B address
wire [2:0]da;		// Dest address
wire dwr;			// Write register if 1

reg [15:0]regs[0:7];
always @(posedge clk) if (dwr) regs[da]<= jal ? regpc : busd;
assign rega=regs[aa];
assign regb=regs[ba];

assign cdo = regb;

wire [15:0]R0=regs[0];
wire [15:0]R1=regs[1];
wire [15:0]R2=regs[2];
wire [15:0]R3=regs[3];
wire [15:0]R4=regs[4];
wire [15:0]R5=regs[5];
wire [15:0]R6=regs[6];
wire [15:0]R7=regs[7];

//---------------------------
// ----------- PC -----------
//---------------------------

wire [15:0]regpc;
wire pcinc,jmp,irqstart;
wire [15:0]vector;

assign vector = VECTORBASE+{ivector,2'b00};
assign pcinc = ~(ld|st|(irqstart&(~ldpc))); // Incrementa PC

wire [15:0]li= jmp ? busd : regpc + pcinc;		// entrada a PC (normal o IRQ)

reg [15:0]PC0;
always @(posedge clk or posedge reset )
	if (reset) PC0<=16'h0000;
	else PC0<= mode ? PC0 : li;
// registro PC modo IRQ
reg [15:0]PC1;
always @(posedge clk ) 
	PC1<= (mode&(~reti)) ? li : vector;

assign regpc=mode ? PC1 : PC0;

//------------------------------------------------------------------------------------------
// ALU
//------------------------------------------------------------------------------------------
wire [15:0]alua;
wire [15:0]alub;
wire cd,vd,zd,nd;
wire [1:0]aluop;

assign ca = (ld | st) ? aluf: regpc;	// Address bus

assign alua = pca ? regpc : rega;
assign alub = (imm ? busimm : regb);

wire c0= xa ? cf : ib;		// input carry
// data inputs to adder
wire [15:0]sa= zab ? alua  : 16'b0;		// Zero input A if zab is low
wire [15:0]sb= ib  ? (~alub) : alub;	// invert input B if ib is high
// Basic ALU
reg [15:0]aluf;	// not regs
reg c15;
always@*
  case (aluop)
     0 : {c15,aluf} = sa+sb+c0;			// ADD
     1 : {c15,aluf} = {1'bx,sa ^ sb};	// XOR
     2 : {c15,aluf} = {1'bx,sa | sb};	// OR
     3 : {c15,aluf} = {1'bx,sa & sb};	// AND
  endcase
// Overflow flag
assign vd = ((~sb[15])&(~sa[15])&aluf[15]) | (sb[15]&sa[15]&(~aluf[15]));

//------  BARREL shifter ------ 

wire [3:0]bsi0mux = {cf,aluf[15],1'b0,aluf[0]};	// LSB select
wire bsi0 = bsi0mux[ror];
wire [15:0]bsi = {aluf[15:1],bsi0};

wire [3:0]bssel = rori ? {IR[6:5],IR[1:0]} : {3'b0,|ror};
wire [15:0]bsl1 = bssel[3] ? { bsi[7:0], bsi[15:8]} : bsi;
wire [15:0]bsl2 = bssel[2] ? {bsl1[3:0],bsl1[15:4]} : bsl1;
wire [15:0]bsl3 = bssel[1] ? {bsl2[1:0],bsl2[15:2]} : bsl2;
wire [15:0]y    = bssel[0] ? {  bsl3[0],bsl3[15:1]} : bsl3;

// result data selection
assign busd = (ld | ldpc) ? cdi : y;

// Carry flag
assign cd = (|ror) ? alub[0] : c15;

// Flags Z, N
assign zd = (busd==0);
assign nd = busd[15];

//---------------------------
//------ Flag register ------
//---------------------------

wire cf,vf,zf,nf;
wire wrcv,wrzn;
reg [1:0]zn[0:1];
reg [1:0]cv[0:1];
assign {zf,nf}=zn[mode];
assign {cf,vf}=cv[mode];
always @(posedge clk) if (wrzn) zn[mode]<={zd,nd};
always @(posedge clk) if (wrcv) cv[mode]<={cd,vd};

//---------------------------
// Instruction register
//---------------------------

wire opvali= ~(ld | ldpc | st | jmp | irqstart);	// Entrada de IR-code válido

reg [15:0]IR;
reg opval;
always @(posedge clk) IR<= cdi;
always @(posedge clk or posedge reset) 
	if (reset) 	opval<=1'b0;
	else 		opval<= opvali;

//---------------------------
// Immediate opperands
//---------------------------

wire [15:0]busimm;
assign busimm[4:0]=IR[4:0];
assign busimm[7:5]=(IR[15]|jal|opimm) ? IR[7:5] : 3'b000;
assign busimm[15:8]=(IR[15]|jal) ? {IR[11],IR[11],IR[11],IR[11],IR[11:8]} : 8'h0;

//---------------------------
// Interrupts
//---------------------------
reg irqq0, mode;
wire ireti=reti&(~irq);
always @(posedge clk or posedge reset ) 
	begin
	if (reset) begin 
		irqq0<=1'b0;
		mode<=1'b0;
	end
	else begin
		irqq0 <= (~ireti) & (irqq0 | irq);
		mode <= (~ireti) & irqq0;
	end
	end
assign irqstart = (~mode) & irqq0;

//---------------------------
// DECODING
//---------------------------

// 8 to 1 mux for conditional jumps
wire [7:0]ccond={1'b1,vf,~nf,nf,~cf,cf,~zf,zf};
wire jr = ccond[IR[14:12]];

// Some op-codes get decoded directly...
wire jal  = opval & (IR[15:12]==4'b0111);
wire rori = opval & (IR[15:11]==5'b01011) & (~IR[7]);
wire ldpc = opval & (IR[15:11]==5'b01011) & (IR[7:5]==3'b111) & (IR[1:0]==2'b00);
wire jind = opval & (IR[15:11]==5'b01011) & (IR[7:5]==3'b111) & IR[1];
wire reti = opval & (IR[15:11]==5'b01011) & (IR[7:5]==3'b111) & (IR[1:0]==2'b11);
wire ld   = opval & (IR[15:11]==5'b01100);
wire st   = opval & (IR[15:11]==5'b01101); 

wire opimm = opval & imm & (~(ld | st | jal | IR[15]));

assign jmp = (opval & IR[15] & jr) | jal | jind;

// register bank selection
assign aa = opimm ? IR[10:8]: IR[7:5];
assign ba = st ? IR[10:8] : IR[4:2];
assign da = jal ? REGLINK : IR[10:8];

wire swap=0;

// Truth table for the rest of control lines...
reg [1:0]fs;		// ALU function, not reg
assign aluop=fs;
reg [1:0]ror;		// shift select (0: none/RORI, 1: ASR, 2: ASRA, 3: RORC)
reg zab, ib, xa, imm, wd, wc, wz, pca; // control lines, not regs
always@*
 casex ({IR[15:11],IR[7:5],IR[1:0]})
                                                       //  fs  zab   ib   xa   ror   imm   wd   wc   wz  pca
 10'b00000_xxx_00:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b0,1'b1,1'b1,1'b1,1'b0}; // ADD
 10'b00000_xxx_01:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b1,1'b0,2'b00, 1'b0,1'b1,1'b1,1'b1,1'b0}; // SUB
 10'b00000_xxx_10:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b1,2'b00, 1'b0,1'b1,1'b1,1'b1,1'b0}; // ADC
 10'b00000_xxx_11:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b1,1'b1,2'b00, 1'b0,1'b1,1'b1,1'b1,1'b0}; // SBC
 
 10'b00001_xxx_00:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b11,1'b1,1'b0,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b1,1'b0}; // AND
 10'b00001_xxx_01:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b1,1'b0,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b1,1'b0}; // OR
 10'b00001_xxx_10:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b01,1'b1,1'b0,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b1,1'b0}; // XOR
 10'b00001_xxx_11:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b11,1'b1,1'b1,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b1,1'b0}; // BIC
 
 10'b00010_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b1,1'b1,1'b1,1'b1,1'b0}; // ADDI
 10'b00011_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b1,1'b0,2'b00, 1'b1,1'b1,1'b1,1'b1,1'b0}; // SUBI
 10'b00100_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b1,2'b00, 1'b1,1'b1,1'b1,1'b1,1'b0}; // ADCI
 10'b00101_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b1,1'b1,2'b00, 1'b1,1'b1,1'b1,1'b1,1'b0}; // SBCI
 10'b00110_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b11,1'b1,1'b0,1'bx,2'b00, 1'b1,1'b1,1'b0,1'b1,1'b0}; // ANDI
 10'b00111_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b1,1'b0,1'bx,2'b00, 1'b1,1'b1,1'b0,1'b1,1'b0}; // ORI
 10'b01000_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b01,1'b1,1'b0,1'bx,2'b00, 1'b1,1'b1,1'b0,1'b1,1'b0}; // XORI
 10'b01001_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b1,1'b0,2'b00, 1'b1,1'b0,1'b1,1'b1,1'b0}; // CMPI
 10'b01010_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'bx,2'b00, 1'b1,1'b1,1'b0,1'b0,1'bx}; // LDI
 
 10'b01011_0xx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'b0,2'b00, 1'b0,1'b1,1'b0,1'b1,1'b0}; // RORI 
 10'b01011_100_00:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'b1,2'b11, 1'b0,1'b1,1'b1,1'b1,1'b0}; // RORC
 10'b01011_100_01:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'b0,2'b01, 1'b0,1'b1,1'b1,1'b1,1'b0}; // SHR
 10'b01011_100_10:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'b0,2'b10, 1'b0,1'b1,1'b1,1'b1,1'b0}; // SHRA
 
 10'b01011_101_00:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b1,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b1,1'bx}; // NOT
 10'b01011_101_01:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b0,1'b1,1'b0,2'b00, 1'b0,1'b1,1'b0,1'b1,1'bx}; // NEG
 10'b01011_111_00:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'bx,2'b00, 1'b0,1'b1,1'b0,1'b0,1'bx}; // LDPC
 10'b01011_111_1x:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b10,1'b0,1'b0,1'bx,2'b00, 1'b0,1'b0,1'b0,1'b0,1'bx}; // JIND

 10'b01100_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b1,1'b1,1'b0,1'b1,1'b0}; // LD
 10'b01101_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b1,1'b0,1'b0,1'b0,1'b0}; // ST

 10'b0111x_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b1,1'b1,1'b0,1'b0,1'b1}; // JAL
 10'b1xxxx_xxx_xx:{fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'b00,1'b1,1'b0,1'b0,2'b00, 1'b1,1'b0,1'b0,1'b0,1'b1}; // JRx
 
 default:         {fs,zab,ib,xa,ror,imm,wd,wc,wz,pca}<={2'bxx,1'bx,1'bx,1'bx,2'bxx, 1'bx,1'bx,1'bx,1'bx,1'bx}; // ILEG
 endcase
// Writing to regs
assign dwr  = opval & wd;	// register bank write
assign wrcv = opval & wc;	// C and V flags write
assign wrzn = opval & wz;	// Z and N flags write



endmodule
//------------------------------------------------------------------------------------------

///////////////////////////////////////////////////////////////////////////////
// Simple UART: data formats: 8N1, 8N2. Fixed baud rate (selected by DIVIDER)
// by J. Arias
///////////////////////////////////////////////////////////////////////////////
module UART_core (
	input	clk,		// System clock
	input   reset,
	input	[7:0]d,		// Input bus for TX
	input	wr,			// write strobe: starts TX
	input	rd,			// read strobe: clears RX flags
	output	[7:0]q,		// Output bus for RX
	output	txrdy,		// TX ready flag
	output	rxvalid,	// RX valid data flag
	output	rxoverr,	// RX overrun error flag
	output	rxframeer,	// RX framing error flag
	input   nstop,		// Set to 1 for two stop bits
	input 	rxd,		// serial data input
	output 	txd			// serial data output
);
parameter DIVIDER= 217;	// BAUD = f_clk / DIVIDER
localparam DBITS = $clog2(DIVIDER);	// number of bits for clock counters

///////////////////// UART TX ////////////////////
reg [DBITS-1:0]txdiv;
wire txdivmax=(txdiv==(DIVIDER-1));
always @(posedge clk) 
	if (wr | txdivmax) txdiv<=0; // Reset if max or on writes
	else txdiv<=txdiv+1;

reg [8:0]txsh;	// 9-bit shift register
always @(posedge clk or posedge reset)
	if (reset) txsh<=9'h1FF; 
	else begin
		if (wr) begin 
			`ifdef SIMULATION
		        $write ("%c",d); $fflush ( );
			`endif
			 txsh<={d,1'b0}; // Load data plus START bit
		end	else if (txdivmax) txsh<={1'b1,txsh[8:1]}; // shift 1'b1 in for future STOP bit
	end
	
assign txd = txsh[0];

reg [3:0]txbitcnt;	// Bit counter (0000 means idle)
wire utxbusy=|txbitcnt;
always @(posedge clk or posedge reset)
	if (reset) txbitcnt<=0;
	else
		if (wr) txbitcnt<={3'b101,nstop}; // set to eleven for 2 STOP bits, ten for 1 STOP bit
		else if (utxbusy&txdivmax) txbitcnt<=txbitcnt-1;
	
assign txrdy=~utxbusy;
	
///////////////////// UART RX ////////////////////
reg [1:0]rxreg; // two samples of RXD
always @(posedge clk) rxreg<={rxreg[0],rxd};
reg [DBITS-1:0]rxdiv;
always @(posedge clk)
	if ((rxreg[1]^rxreg[0])|(rxdiv==(DIVIDER-1))) rxdiv<=0; // Reset if max or on any RXD edge
	else rxdiv<=rxdiv+1;
wire rxsample = (rxdiv==(DIVIDER/2-1)); // sample at the middle of the bit

reg [9:0]urxsh; // 10-bit shift register
reg [8:0]urxbuffer;		// 9-bit buffer: data + STOP
always @(posedge clk or posedge reset) begin
	if (reset)  urxsh<=10'h3FF; 
	else begin
		if (~urxsh[0]) urxsh<=10'h3FF;  // if START bit at LSB set to all ones and copy results
		else if (rxsample) urxsh<={rxreg[1],urxsh[9:1]};
	end
end

always @(posedge clk) 
	if (~urxsh[0]) urxbuffer<=urxsh[9:1]; 	  // store the received data plus STOP

reg [1:0]urxval;		// received data flags (00: no data, 01: data available, 11: overrun)
always @(posedge clk or posedge reset)
	if (reset) urxval<=0;
	else if (~urxsh[0]) urxval<={urxval[0],1'b1};  // set data valid and (maybe) overrun
	else if (rd) urxval<=0;  // clear data valid and overrun flags on reads

assign q = urxbuffer[7:0];	
assign rxframeer = ~urxbuffer[8];	// STOP bit in 0 means Frame error
assign rxvalid = urxval[0];
assign rxoverr = urxval[1];

endmodule


