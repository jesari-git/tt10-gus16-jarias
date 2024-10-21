///////////////////////////////////////////////////////////////////////////////
// Simple UART: data formats: 8N1, 8N2. Fixed baud rate (selected by DIVIDER)
// by J. Arias
///////////////////////////////////////////////////////////////////////////////
module UART_core (
	input	clk,		// System clock
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
reg [DBITS-1:0]txdiv=0;
wire txdivmax=(txdiv==(DIVIDER-1));
always @(posedge clk) 
	if (wr | txdivmax) txdiv<=0; // Reset if max or on writes
	else txdiv<=txdiv+1;

reg [8:0]txsh=10'h1FF;	// 9-bit shift register
always @(posedge clk)
	if (wr) begin 
		`ifdef SIMULATION
	        $write ("%c",d); $fflush ( );
		`endif
		 txsh<={d,1'b0}; // Load data plus START bit
	end	else if (txdivmax) txsh<={1'b1,txsh[8:1]}; // shift 1'b1 in for future STOP bit
assign txd = txsh[0];

reg [3:0]txbitcnt=0;	// Bit counter (0000 means idle)
wire utxbusy=|txbitcnt;
always @(posedge clk) 
	if (wr) txbitcnt<={3'b101,nstop}; // set to eleven for 2 STOP bits, ten for 1 STOP bit
	else if (utxbusy&txdivmax) txbitcnt<=txbitcnt-1;
	
assign txrdy=~utxbusy;
	
///////////////////// UART RX ////////////////////
reg [1:0]rxreg=0; // two samples of RXD
always @(posedge clk) rxreg<={rxreg[0],rxd};
reg [DBITS-1:0]rxdiv=0;
always @(posedge clk)
	if ((rxreg[1]^rxreg[0])|(rxdiv==(DIVIDER-1))) rxdiv<=0; // Reset if max or on any RXD edge
	else rxdiv<=rxdiv+1;
wire rxsample = (rxdiv==(DIVIDER/2-1)); // sample at the middle of the bit

reg [9:0]urxsh=10'h3FF; // 10-bit shift register
reg [8:0]urxbuffer;		// 9-bit buffer: data + STOP
reg [1:0]urxval=0;		// received data flags (00: no data, 01: data available, 11: overrun)
always @(posedge clk) begin
	if (~urxsh[0]) urxsh<=10'h3FF;  // if START bit at LSB set to all ones and copy results
	else if (rxsample) urxsh<={rxreg[1],urxsh[9:1]};
	
	if (~urxsh[0]) urxbuffer<=urxsh[9:1]; 	  // store the received data plus STOP
	
	if (~urxsh[0]) urxval<={urxval[0],1'b1};  // set data valid and (maybe) overrun
	else if (rd) urxval<=0;  // clear data valid and overrun flags on reads
end
assign q = urxbuffer[7:0];	
assign rxframeer = ~urxbuffer[8];	// STOP bit in 0 means Frame error
assign rxvalid = urxval[0];
assign rxoverr = urxval[1];

endmodule


