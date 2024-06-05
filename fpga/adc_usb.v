module adc_usb (
  input clkadc,
  input clkusb,
  input [7:0] datain,
  input data_ready,
  output [7:0] o_dataout,
  output o_wr
);
  
  reg state = 0;
  reg[7:0] data = 0;
  reg[7:0] data_buf = 0;
  reg clkadc_2 = 0;
  reg clkadc_3 = 0;
  reg wr = 0;
  reg [7:0] dataout = 0;
  reg data_valid = 0;
  
  assign o_wr = ~wr;
  assign o_dataout = dataout;

  
  always @(posedge clkadc) begin
    data_valid = data_ready;
    data_buf = datain;
  end
  
  always @(negedge clkusb) begin
    clkadc_2 <= clkadc;
    clkadc_3 <= clkadc_2;
    if (state == 0 & clkadc_2 == 1 & clkadc_3 == 0 & data_valid) begin
      state = 1;
      dataout = data_buf;
      wr = 1;
    end
    else if (state == 1) begin
      state = 0;
      wr = 0;
    end
  end

endmodule