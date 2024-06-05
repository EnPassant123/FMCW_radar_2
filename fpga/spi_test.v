`ifdef SIMULATION

`define STARTUP_RESET_TIME 10

`else

`define STARTUP_RESET_TIME 262143

`endif

`define START_COMMAND 32'hf00dbabe
`define DELAY_TIME 2000

// Code your testbench here
// or browse Examples




module spi_test(
  input clk,
  input clkadc,
  input [7:0] adc_data,
  inout [7:0] io_usb,
  input rxf,
  input txe,
  input data_ready,
  output o_wr,
  output rd,
  output oe,
  output o_siwu,
  output mosi,
  output sclk,
  output cs,
  output lat,
  output o_conv_start,
  output o_adc_reset
  );

  wire lock;
  wire o_pll_reset;
  wire clkmult;

  reg start_adc = 0;
  reg start_dac = 0;
  wire spi_busy;
  reg [39:0] data = 0;
  reg init = 0 ;
  reg adc_en = 0;
  reg [19:0] delay_counter = 0;
  reg [11:0] delay_counter_2 = 0;

  reg[3:0] state = 0;
  reg [12:0] counter = 0;
  reg adc_reset = 0;
  wire [31:0] o_data_rd;
  reg wr = 0;
  wire wr_en;
  assign wr_en = wr ;
  reg start_read = 0;
  reg [6:0] debugCounter = 0;
  reg startup_done = 0;
  reg [4:0] siwu_counter = 0;
  reg pll_reset = 0;
  assign o_pll_reset = pll_reset;


  assign o_siwu = ~(siwu_counter > 1);
  wire usb_busy;
 
  assign o_adc_reset = adc_reset;
  reg [31:0] SWEEP_DIFF = 0;
  reg [31:0] SWEEP_START = 0;
  reg [31:0] SWEEP_STOP = 0;
  wire driver_cs;
  reg cs_enable = 0;
  assign cs = cs_enable && driver_cs;
  reg conv_start = 0;
  assign o_conv_start = conv_start;   

  wire data_valid;               
                                
  spi_test_pll spi_test_pll_inst(.REFERENCECLK(clkadc),
                               .PLLOUTCORE(),
                               .PLLOUTGLOBAL(clkmult),
                               .RESET(o_pll_reset),
                               .LOCK(lock));

  
  spi_driver DUT (
    .busy(spi_busy),
    .start_adc(start_adc),
    .start_dac(start_dac),
    .sclk(sclk),
    .mosi(mosi),
    .data(data),
    .clk(clk),
    .cs(driver_cs),
    .init (init),
    .data_valid(data_valid),
    .clkmult(clkmult),
    .SWEEP_DIFF(SWEEP_DIFF),
    .SWEEP_START(SWEEP_START),
    .SWEEP_STOP(SWEEP_STOP)
  );
 
  usb_int DUT2(
    .clkadc(clkadc),
    .clkusb(clk),
    .adc_data(adc_data),
    .io_usbdata(io_usb),
    .o_data_rd(o_data_rd) ,
    .rxf(rxf), //High = do not read
    .txe(txe), //High = do not write
    .o_wr(o_wr), //Low = write
    .rd(rd), //Low = read
    .oe(oe),
    .wr_en(wr_en),
    .start_read(start_read),
    .o_busy( usb_busy),
    .data_ready (data_valid)
  );  

                                   
  reg init_done = 0;
  assign lat = lock ;

  reg get_command = 0;  
  reg get_command_2 = 0;
  reg [4:0] offset = 0;
  reg init_done_2 = 0;
  reg [2:0] state2 = 0;
  reg data_ready_2 = 0;

  always @(negedge clk) begin
    
    if (!startup_done) begin
      //Initialize ADC by toggling reset pin and waiting for device to settle
      SWEEP_DIFF <= 3095815;
      SWEEP_START <= 1775837915;
      SWEEP_STOP <= 4291372423;
      cs_enable <= 1;
      conv_start <= (delay_counter > 1);
      if (delay_counter < `STARTUP_RESET_TIME ) begin
        adc_reset <= (delay_counter >= 1000);
        delay_counter <= delay_counter +1;
      end
      else startup_done <= 1;
    end
    else begin
      case(state)
        0: begin
          //State zero: Wait for data to get received at USB
          //When rxf goes high -> go to state 1
          delay_counter <= 0;
          if (!rxf) begin
            state <= 1;
            wr <= 0;
            start_read <= 1;
          end
        end
        1: begin
          //State 1: Read 4 bytes and compare to magic number
          //Success -> state 2
          if(!usb_busy && !start_read) begin
            if (o_data_rd != `START_COMMAND) state <= 0;
            else state <= 2;
          end
          else
            start_read <= 0;
        
        end
        2: begin
          //State 2: Begin ADC initialization
          start_adc <= 1;
          init <= 1;
          state <= 3;
          cs_enable <= 1;
        end
        3: begin
          //Wait for ADC initialization to finish
          if (!spi_busy && !start_adc) begin
            
            //Enable PLL
            pll_reset <= 1;
            if (lock) begin
              state <= 4;
              init_done <= 1;
              conv_start <= 0;
            end
          end
          else begin
            init <= 0;
            start_adc <= 0;
          end
        end
        
        4: begin
          get_command_2 <= get_command;
          if (get_command_2) begin
            if(siwu_counter == 0) begin
              siwu_counter <= 21;
            end
            else if (siwu_counter == 1) begin
              cs_enable <= 0;
              wr <= 0;
              if (!usb_busy && !rxf) begin
                start_read <= 1;
                state <= 5;
              end
            end
            else begin
              siwu_counter <= siwu_counter - 1;
            end
          end
          else begin
            wr <= 1;
            siwu_counter <= 0;
            cs_enable <= 1;
          end
        end
        5: begin
          start_read <= 0;
          if (!usb_busy) begin
            if (o_data_rd[31:30] == 1) begin
              cs_enable <= 1;
              start_adc <= 1;
              data <= {8'h02, 32'h3FFFFFFF & o_data_rd};
              state <= 6;
            end
            if (o_data_rd[31:30] == 2) begin
              case (o_data_rd[29:24])
                0: SWEEP_DIFF <= o_data_rd[15:0];
                1: SWEEP_START <= o_data_rd[15:0];
                2: SWEEP_STOP <= o_data_rd[15:0];
              endcase
            end
          end
        end
        6: begin
          start_adc <= 0;
          if(!spi_busy) begin
            state <= 4;
          end
        end
      endcase
    end
  end

                                   
                                 
  always @(posedge clkmult) begin
    init_done_2 <= init_done;
    data_ready_2 <= data_ready;
    if(init_done_2 && data_ready_2) begin
      case (state2)
        0: begin
          start_dac <= 1;
          state2 <= 1;
        end
        1: begin
          if (!spi_busy && !start_dac) begin
            state2 <= 2;
          end
          else
            start_dac <= 0;
        end
        2: begin
          if (delay_counter_2 == 0) begin
            delay_counter_2 <= `DELAY_TIME;
            get_command <= 1;
          end
          else if(delay_counter_2 == 1) begin
            if (offset == 0) begin
              state2 <= 0;
              delay_counter_2 <= 0;

            end
          end
          else if (delay_counter_2 < 700) begin
            get_command <= 0;
            delay_counter_2 <= delay_counter_2 - 1;
          end
          else begin
            delay_counter_2 <= delay_counter_2 - 1;
          end   
        end
      endcase
      offset <= offset + 1;
    end
  end
endmodule
