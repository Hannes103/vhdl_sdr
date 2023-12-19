# VHDL SDR
This repository contains my VHDL project that I did as part of my digital electronics design laboratory. 

It tries to implement a simple (none reconfigurable) direct conversion SDR that decodes a simple QPSK signal using an external ADC.  
The [Digilent Eclipse-Z7](https://digilent.com/reference/programmable-logic/eclypse-z7/start) board is used as the final hardware platform.

## Repository structure
- `RTL/`  
  Contains the VHDL source code and all associated test-benches required for the design.  
  Source code is written using VHDL-2008 and the [Sigasi](https://www.sigasi.com)-IDE.   
  Simulation is done using [GHDL](https://github.com/ghdl/ghdl) with [VUnit](https://vunit.github.io/index.html) as a testing framework.  

- `FPGA/`  
  Contains the [Xilinx Vivado](https://www.xilinx.com/products/design-tools/vivado.html)-2023.1 project for the physical board.

- `MATLAB/`  
  Contains associated supporting [Matlab](https://de.mathworks.com/products/matlab.html) scripts that where used for design verification/filter design
  or simulation of certain subsystems.
