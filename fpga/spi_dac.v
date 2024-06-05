module spi_dac (
  output o_busy,
  input start,
  output o_sclk,
  output o_mosi,
  input[23:0] data,
  input clk,
  output load_data_o
);
  reg mosi = 0;
  assign o_mosi = mosi;
  reg [2:0] state = 0;
  assign o_busy = (state != 0);
  reg [$clog2(24)-1:0] counter=0;
  reg sclkpos=0;
  reg sclkneg=0;
  reg [23:0] data_r = 0;
  assign load_data_o = (counter == 1) && (state == 3);

  
  assign o_sclk = (sclkpos || sclkneg);
  
  always @(negedge clk) begin
    if (state == 3) begin
      sclkneg = 1;
    end
    else begin
      sclkneg = 0;
  	end
  end
    
  always @(posedge clk) begin
    if (start && (state == 0)) begin
      counter = 0;
      state = 4;
      sclkpos = 0;
      mosi = 0;
      data_r = data;
    end
    else if (state == 4) 
      state = 1; //Add one delay cycle to meet timing
    else begin
      if (counter >= 24) begin
        if(start) begin
          state = 2;
          data_r = data;
          mosi = data[23];
        end
        else begin
          state = 0;
          mosi = 0;
        end
        counter = 0;
      end
      
      else begin
        if (state == 1) begin
          mosi = data_r[24 - counter - 1];
          state = 2;
        end
        else if (state == 2) begin 
          sclkpos = 1;
          state = 3;
        end
        else if (state == 3) begin
          sclkpos = 0;
          counter = counter + 1;
          state = 1;
        end
      end
    end
  end
endmodule
