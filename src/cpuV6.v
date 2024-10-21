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

reg [15:0]PC [0:1];
always @(posedge clk or posedge reset )
	if (reset) PC[0]<=16'h0000;
	else PC[0]<= mode ? PC[0] : li;
// registro PC modo IRQ
always @(posedge clk ) 
	PC[1]<= (mode&(~reti)) ? li : vector;

assign regpc=PC[mode];

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
reg opval=0;
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
reg irqq0=0, mode=0;
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


