
//Skip most of ADC initialization if simulating



`ifdef SIMULATION
`include "spi_adc.v"
`include "spi_dac.v"

`define ADC_INIT_COUNT 5
`define PLL_WAIT 100

`else

`define ADC_INIT_COUNT conf_len
`define PLL_WAIT 131071
`endif


module spi_driver (
  //clk: 60MHz - used for ADC
  input clk,
  //clkmult: 57.6 MHz - used for DAC
  input clkmult,
  
  //SPI outputs
  output sclk,  
  output cs,
  output mosi,
  
  //HIGH = run ADC initalization sequence
  //LOW = write 40 bits to ADC
  input init,
  input [39:0] data,
  
  //HIGH = write to ADC  
  input start_adc,
  //HIGH = start sweep
  input start_dac,
  
  //Do not enable ADC/DAC when busy
  output busy,
  
  //Synchronization signal for ADC
  output data_valid,
  
  //Sweep parameters for DAC
  input [31:0] SWEEP_START,
  input [31:0] SWEEP_DIFF,
  input [31:0] SWEEP_STOP
  
);
  
  //ADC configuration: command list
  
  localparam conf_len = 22;
  localparam [40 * conf_len - 1: 0] adc_conf = 
  {40'h0200000000, 40'h0200033001, 40'hffffffffff, 40'hffffffffff,
// 40'h0201021111, 
40'h02010000AA,
  40'h0201C20001, 40'h0201400002,
  40'h0201C10004, 40'h0202840003, 40'h0202860003, 40'h0202880003,
  40'h0202890003, 40'h02028A0003, 40'h02028B0003, 40'h02028C0003,
  40'h02028D0003, 40'h02028E0003, 40'h0202910003, 40'h02030a0001,
  40'h0203080013, 40'h0203010306, 40'h0200400001};
  
  //Keeps track of if we're doing ADC initialization
  reg is_init = 0;

  //Busy signal for both ADC and DAC
  wire busy_dac;
  wire busy_adc;
  
  //Start signal for ADC and DAC driver
  reg dac_start = 0;
  reg adc_start = 0;
  
  wire adc_cs;
  
  //Signal for starting special 56 bit command for turning off CRC
  reg adc_init=0;
  
  //Counter for initalization
  reg [$clog2(conf_len)-1:0] counter=0; 
  
  //Delay (to wait for ADC PLL to lock)
  reg [16:0] delay=0;
  
  
  wire sclk_dac;
  wire mosi_dac;
  
  wire sclk_adc;
  wire mosi_adc;
  
  
  wire [39:0] data_adc;
  
  reg [39:0] data_adc_init =0;
  
  reg [31:0] sweep_count = 0;
  reg [31:0] diff = 0;
  reg [31:0] diff2 = 0;

  
  reg reset_sweep = 0;
  
  wire [23:0] data_dac;
  
  //Switch all outputs
  assign sclk = busy_adc ? sclk_adc : sclk_dac;
  assign mosi = busy_adc ? mosi_adc : mosi_dac;
  assign cs = busy_adc ? adc_cs : 1;
  
  //Switch between initialization data
  assign data_adc = is_init ? data_adc_init : data;
  
  //Data going into DAC (most significant 12 bits of sweep counter)
  assign data_dac = {12'b0, sweep_count[31:20]};
  
  
  assign busy = is_init | busy_dac | busy_adc | reset_sweep | dac_start;
  assign data_valid = (busy_dac | dac_start | reset_sweep);
  wire load_data_dac;

  
  spi_dac SPI_DAC(
    .o_busy(busy_dac),
    .start(dac_start),
    .o_sclk(sclk_dac),
    .o_mosi(mosi_dac),
    .data(data_dac),
    .clk(clkmult),
    .load_data_o(load_data_dac)
  );
  
  spi_adc SPI_ADC (
    .o_busy(busy_adc),
    .start(adc_start),
    .o_sclk(sclk_adc),
    .o_mosi(mosi_adc),
    .data(data_adc),
    .clk(clk),
    .o_cs(adc_cs),
    .init(adc_init)
  );
  
  always @(negedge clk) begin

    if (start_adc && !(busy_adc || is_init) && counter == 0) begin
      if (init) begin
        counter = 0;
        is_init = 1;
        adc_init = 1;
        //Start a 7 clock cycle delay
        delay = 7;
      end
      adc_start = 1;
    end
    //Special case when counter = 2: wait for PLL to lock first
    else if (counter == 3) begin
      delay = `PLL_WAIT;
      adc_start = 0;
      counter = 4;
    end
    else if (delay == 0 && is_init) begin
      

      
      //Wait for previous command to finish sending
      if (!busy_adc) begin
        //Stop initialization if we reach end of configuration sequence
        if (counter == `ADC_INIT_COUNT) is_init = 0;
        else begin
          //Load next data and start ADC
          data_adc_init = adc_conf[(conf_len - counter-1)*40 +: 40];
          adc_start = (counter != 2);
          delay = 7;
        end
        counter = counter + 1;
      end
    end  
    else if (delay == 1) begin
      //Reset init and start after delay
      adc_init = 0;
      adc_start = 0;
      delay = 0;
    end
    else begin
      adc_start = 0;
      if (delay > 0) delay = delay - 1; 
    end
  end
  
  always @(posedge clkmult) begin
    if (start_dac && !busy) begin
      sweep_count = SWEEP_START;
      dac_start = 1;
      reset_sweep = 0;
      diff = 3594873;
      diff2 = -32'H78B;
    end
    else if (dac_start && !reset_sweep) begin
      if(load_data_dac) begin
        if (sweep_count < SWEEP_STOP) begin
          sweep_count = sweep_count + diff; //not overflow safe
          diff = diff + diff2;
          diff2 = diff2 + 3;
        end
        else begin
          //Reset DAC back to starting value
          sweep_count = SWEEP_START;
          reset_sweep = 1;
        end
      end
    end
    else if (reset_sweep && load_data_dac) begin
      reset_sweep = 0;
      dac_start = 0;
      
    end
  end
endmodule
      
