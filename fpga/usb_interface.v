module usb_int (
  input clkadc,
  input clkusb,
  input[7:0] adc_data,
  inout [7:0] io_usbdata ,
  input data_ready,
  output [31:0] o_data_rd ,
  input rxf, //High = do not read
  input txe, //High = do not write
  output o_wr, //Low = write
  output rd, //Low = read
  output siwu,
  output oe,
  input wr_en,
  input start_read,
  output o_busy  
);
  
  
  wire adc_wr;
  wire [7:0] usb_data;
  reg [31:0] data_rd;
  assign o_data_rd = data_rd;
  
  adc_usb ADC_USB 
  (.clkadc (clkadc),
   .clkusb (clkusb),
   .datain (adc_data),
   .data_ready(data_ready),
   .o_dataout (usb_data),
   .o_wr (adc_wr)
  );
  
  wire canRead;
  wire canWrite;
  
  reg [2:0] read_state = 0;
  reg write_state = 0;
  //reg rden = 0;
  
  assign io_usbdata = ~write_state ? 8'bz : usb_data;
  assign oe =  !read_state ;
  assign o_wr = ~write_state;
  assign siwu = 1;
  assign rd = (read_state <= 1 || read_state >= 6);
  assign o_busy = write_state || read_state;
  
  
  assign canRead = ~wr_en & ~o_busy  & ~rxf;
  assign canWrite = wr_en & ~o_busy & ~txe;
  
  always @(negedge clkusb) begin
    if(start_read == 1 & read_state == 0 & canRead) begin
      read_state <= 1;
    end
    else if (read_state >= 1) begin
      data_rd <= (data_rd << 8) | io_usbdata;
      if (read_state >= 5 ) read_state <= 0;
      else read_state <= read_state + 1;
  end
    else if (adc_wr == 0 & write_state == 0 & canWrite) begin
      write_state <= 1;
    end
    else if (write_state == 1) begin
      write_state <= 0;
    end
  end
endmodule