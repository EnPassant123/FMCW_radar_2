**FMCW Radar Project**

Contains design files, Verilog code for FPGA, and C code for computer.

Can be easily modified to act as a data streaming board (just disable sweep)

Code is still very buggy and does not pass timing. Use at your own risk!

Untested PCB changes: Added LDO to cut down on power supply noise (from USB) more.

The C code is based on libftdi1, and some changes need to be made to ftdi_stream.c
