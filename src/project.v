/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "cpuV6.v"
`include "uart_simple.v"

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
assign uo_out={xweb,xoeb,1'b0,txd,pwmout,xlah,xlal,xbh};
assign rxd=ui_in[3];
wire _unused = &{ui_in[7:4],ui_in[2:0], ena, 1'b0};

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

initial begin
`ifdef SIM
  $readmemh("rom_prueba.hex", irom);
`else
  $readmemh("rom_boot.hex", irom);
`endif
end

	
////////////////////////////////////////////////
// External SRAM (8bit + address latches)

reg [1:0]ckd=0;
always @(posedge clk) ckd<=ckd+1;

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
//wire iowe4=(we)&(iocs)&(ca[2:0]==4);
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
// prescaler for 1MHz timer clk
localparam PRESC=FCLK/4/1000000;
localparam NBPRE=$clog2(PRESC);
reg [NBPRE-1:0]presc=0;
wire prestc = &(presc | (~(PRESC-1)) );

reg [15:0]tmax=16'hffff;
reg [15:0]timer=0;
reg tflag=0;
wire timetc = (timer==tmax);
always @(posedge cksys) begin
	presc <= (iowe3 |prestc) ? 0 : presc+1;
	timer <= (iowe3 | (timetc & prestc)) ? 0 : timer + prestc;
	tmax  <=  iowe3 ? cdo : tmax;
	tflag <= (timetc & prestc) ? 1 : ((iowe3 | iore3)? 0 : tflag);
end

/////////////////////////////
// PWM

parameter PWMBITS=8;
reg [PWMBITS-1:0]pwmhold;
always @(posedge cclk) if (iowe1) pwmhold<=cdo[PWMBITS-1:0];

reg [PWMBITS-1:0]pwmc=0;
reg [PWMBITS-1:0]pwmbuf;
reg pwmout;
reg pwmirq;
wire pwmtc = &pwmc[PWMBITS-1:1];	// terminal count: 2^n - 2
wire pwmzc = (pwmc==0);				// zero count

always @(posedge clk) begin
	pwmc<=pwmtc ? 0 : pwmc+1;
	if (pwmzc) pwmbuf<=pwmhold;
	pwmout<= (pwmc==pwmbuf) ? 0 : (pwmzc ? 1 : pwmout);
	pwmirq<= pwmzc ? 1 : (iowe1  ? 0 : pwmirq);
end

/////////////////////////////
// I/O data to CPU MUX
reg [15:0]iodo;
always@*
  case (ca[2:0])
     0 : iodo <=  {15'h0,irqen}; // IRQ Enable
     1 : iodo <=  {tflag,10'h0,pwmirq,uflags}; // PFLAGS
     2 : iodo <=  {8'h0,urxdata}; // UART data
     3 : iodo <=  timer;
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
	( .clk(cksys), .d(cdo[7:0]), .wr(iowe2&(~stopcpu)), .rd(iore2&(~stopcpu)), .q(urxdata),
		.rxvalid(uflags[0]), .txrdy(uflags[1]),
		.rxoverr(uflags[2]), .rxframeer(uflags[3]),
		.nstop(1'b0),
		.txd(txd), .rxd(rxd)
	);

endmodule
