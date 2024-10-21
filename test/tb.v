//-------------------------------------------------------------------
//-------------------------------------------------------------------

//`include "project.v"


module tb();

parameter FCLK=24000000;
parameter BAUD=1500000;
localparam DIVI=(FCLK*10+(BAUD/2))/BAUD; 

//-- Registros con señales de entrada
reg clk;
reg reset;
reg rxd;
wire txd;
wire pwmout;

//-- Instanciamos
wire [7:0]xd;
wire xweb,xoeb,xbh,xlal,xlah;

tt_um_gus16 #(.FCLK(FCLK), .BAUD(BAUD)) sys0 ( .clk(clk), .rst_n(~reset),
	.ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe) 
 );

wire [7:0] ui_in;
wire [7:0] uo_out;
wire [7:0] uio_in;
wire [7:0] uio_out;
wire [7:0] uio_oe;

assign {xlah,xlal,xbh}=uo_out[2:0];
assign {txd,pwmout}=uo_out[4:3];
assign {xweb,xoeb}=uo_out[7:6];

// EXT RAM + latches
reg [15:0]la=0;
always @(posedge clk) if (xlal) la[7:0]<=uio_out;
always @(posedge clk) if (xlah) la[15:8]<=uio_out;

//latches transparentes tipo '373 (requiere --ignore-loops en nextpnr)
//always @* if (xlal) la[7:0]<=xd;
//always @* if (xlah) la[15:8]<=xd;

wire [15:0]xa={la[14:0],xbh};

reg [7:0]sram[0:65535];
always @(negedge xweb) sram[xa]<=uio_out;
assign uio_in=sram[xa];

// Reloj periódico
always #5 clk=~clk;

//-- Proceso al inicio
initial begin
	//-- Fichero donde almacenar los resultados
	$dumpfile("tb.vcd");
	$dumpvars(0, tb);
	reset = 1; clk=0; rxd=1;
	#80 reset = 0;
	
	// 0xFF
	#DIVI	rxd=0; // start
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1; // Stop

	// L (0x4C)
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop
	// 0x40
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop
	// 0x00
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop

	// 0x1
	#DIVI	rxd=0; // start
	#DIVI	rxd=1;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop
	// 0x00
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop

	// 0x40
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop
	// 0x00
	#DIVI	rxd=0; // start
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=0;
	#DIVI	rxd=1; // Stop
	
	// 0xFF
	#DIVI	rxd=0; // start
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1; // Stop
	// 0xFF
	#DIVI	rxd=0; // start
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1;
	#DIVI	rxd=1; // Stop

	//# 319 $display("FIN de la simulacion");
	# 100000 $finish;
	//# 1000 $finish;
end



endmodule


