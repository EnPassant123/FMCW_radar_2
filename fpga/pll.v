module spi_test_pll(REFERENCECLK,
                    PLLOUTCORE,
                    PLLOUTGLOBAL,
                    RESET,
                    LOCK);

input REFERENCECLK;
input RESET;    /* To initialize the simulation properly, the RESET signal (Active Low) must be asserted at the beginning of the simulation */ 
output PLLOUTCORE;
output PLLOUTGLOBAL;
output LOCK;

SB_PLL40_CORE spi_test_pll_inst(.REFERENCECLK(REFERENCECLK),
                                .PLLOUTCORE(PLLOUTCORE),
                                .PLLOUTGLOBAL(PLLOUTGLOBAL),
                                .EXTFEEDBACK(),
                                .DYNAMICDELAY(),
                                .RESETB(RESET),
                                .BYPASS(1'b0),
                                .LATCHINPUTVALUE(),
                                .LOCK(LOCK),
                                .SDI(),
                                .SDO(),
                                .SCLK());

//\\ Fin=14.4, Fout=57.6;
defparam spi_test_pll_inst.DIVR = 4'b0000;
defparam spi_test_pll_inst.DIVF = 7'b0000011;
defparam spi_test_pll_inst.DIVQ = 3'b010;
defparam spi_test_pll_inst.FILTER_RANGE = 3'b001;
defparam spi_test_pll_inst.FEEDBACK_PATH = "PHASE_AND_DELAY";
defparam spi_test_pll_inst.DELAY_ADJUSTMENT_MODE_FEEDBACK = "FIXED";
defparam spi_test_pll_inst.FDA_FEEDBACK = 4'b0000;
defparam spi_test_pll_inst.DELAY_ADJUSTMENT_MODE_RELATIVE = "FIXED";
defparam spi_test_pll_inst.FDA_RELATIVE = 4'b0000;
defparam spi_test_pll_inst.SHIFTREG_DIV_MODE = 2'b00;
defparam spi_test_pll_inst.PLLOUT_SELECT = "SHIFTREG_0deg";
defparam spi_test_pll_inst.ENABLE_ICEGATE = 1'b0;

endmodule
