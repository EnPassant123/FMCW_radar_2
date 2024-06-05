`define MAX(v1, v2) ((v1) > (v2) ? (v1) : (v2))
`define CRC_DATA_WIDTH 56

module spi_adc (
  input start,
  input[39:0] data,   
  input clk,
  input init,
  
  output o_cs,
  output o_busy,
  output o_sclk,
  output o_mosi
);

  reg cs = 0;
  reg sclk = 0;
  reg mosi = 0;
  reg mosi_r = 0;

    
  assign o_cs = ~cs;
  assign o_sclk = sclk;
  assign o_mosi = mosi;
  reg is_init = 0;
  localparam crc_disable = 56'h02fd0000013307;
  localparam DB = $clog2(`MAX(40, `CRC_DATA_WIDTH));
  
  reg [4:0] state = 0;
  reg [DB-1:0] counter = 0; 
  assign o_busy = (state != 0);

  wire [DB-1:0] DW = is_init ? `CRC_DATA_WIDTH : 40;
  
    
  always @(negedge clk) begin    
    case (state)
      0: begin
        if (start && (state == 0)) begin
          counter = 0;
          state = 1;
          sclk = 0;
          cs = 0;
          is_init = init;
        end
      end
      
      1,2,3: state = state + 1;
      
      4: begin
        cs = 1;
        state = state + 1;
      end
      
      5: state = state + 1;
      
      6: begin
        state = 7;
	 // offload some computation
        mosi_r = is_init ? crc_disable[DW - counter - 1] : data[DW - counter - 1];
      end

      7: begin
        sclk = 0;
        if (counter >= DW) begin
          state = 0;
          mosi = 0;
          counter = 0;
        end
        else begin
          mosi = mosi_r;
          counter = counter + 1;
          state = state + 1;
        end
      end
      
      8,9: state = state + 1;
      
      10: begin
        sclk = 1;
        state = 5;       
      end
    endcase
  end
endmodule
