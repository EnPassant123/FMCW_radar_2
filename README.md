**FMCW Radar Project**
Contains design files, Verilog code for FPGA, and C code for computer.

Can be easily modified to act as a data streaming board (just disable sweep)

Code is still very buggy and does not pass timing. Use at your own risk!

Suggested PCB changes: Use a separate LDO to power the single ended to differential amplifiers. Can probably reduce the noise floor a little.
