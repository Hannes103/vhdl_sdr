import os
from vunit import VUnit

from scripts import dds_checker
from scripts import iq_checker

# ============================= CONFIG =============================

# set default environment variables, we use GHDL with the VHDL-2008 language standard.
os.environ["VUNIT_SIMULATOR"] = "ghdl"
os.environ["VUNIT_VHDL_STANDARD"] = "2008"

# ============================= SETUP =============================

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv(compile_builtins=False)

# Add bultin vhdl libraries
vu.add_vhdl_builtins()
vu.add_verification_components();
vu.add_osvvm()

# ============================= SOURCES =============================

# Create library 'src' that holds all source files and test benches
lib_src = vu.add_library("src")
lib_src.add_source_files("src/**/*.vhd")
lib_src.add_source_files("tb/**/*.vhd")

# ============================= VIVADO LIBRARIES =============================

# add xilinx libraries (VHDL-2008)
vivado_lib_path = os.path.abspath(os.path.join(os.environ["VUNIT_GHDL_PATH"], "../lib/ghdl/vendors/xilinx-vivado"))
vivado_libs = [ "unisim", "unimacro" ]
vivado_lang_path = "v08" if os.environ.get("VUNIT_VHDL_STANDARD", "2008") else "v93";

for name in vivado_libs:
    vu.add_external_library(name, os.path.join(vivado_lib_path, name, vivado_lang_path))

# in order for the xilinx libraries to be usable the -frelaxed option is required
# otherwise the vital library is not compatible! (must be done after every source file has been added)
vu.add_compile_option("ghdl.a_flags", ["-frelaxed"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed"])

# ============================= TEST-BENCH: tb_dds_generator.vhd =============================
tb_dds_generator = lib_src.test_bench("tb_dds_generator")

#for freq in [2.05,4.125,10.0,14.41, 20.01, 22.00]:
for freq in [14.41]:
    config = {
        "target_frequency": freq * 1e6,      # center frequency is given by loop index in MHz
        "target_frequency_tollerance": 1000, # twice the smallest frequency deviation we can detect with 20kSamples 
        "SFDR_min": 44.24,                   # theoretical maximum achievable with 8 bits phase accumulator
        "amplitude_tollerance": 1.5,         # dBFS
        "expected_phase": -90,               # expected phase depends on which carrier is inverted, (in degrees)
        "expected_phase_tollerance": 0.01    # phase tollerance in degrees
    }
    
    checker = dds_checker.dds_checker(config)
    tb_dds_generator.add_config(name=f"freq_{freq}MHz", generics=dict(target_freq=freq*1e6, samples=100e3), post_check=checker.post_check);

# ============================= TEST-BENCH: tb_iq_demodulator.vhd =============================
tb_iq_demodulator = lib_src.test_bench("tb_iq_demodulator")

for freq in [10, 12, 15, 20]:
    config = {
        "samples": 100e3,                           # number of samples
        "freq": freq * 1e6,                         # frequency in Hz
        "ampl": 0.2,                                # maximum amplitude in percent
        "offset": 0.0,                              # dc offset
        "SNR": 3,                                   # signal to noise ratio in dB
        "data": [1 + 1j, -1 + 1j, -1 - 1j, +1 - 1j] # data to send
    }
    
    checker = iq_checker.iq_checker(config, False)
    tb_iq_demodulator.add_config(
        name=f"freq_{freq}MHz", 
        generics=dict(target_freq=freq*1e6), 
        pre_config=checker.pre_config,
        post_check=checker.post_check
    );

# ============================= TEST-BENCH: tb_rf_reciever.vhd =============================
tb_rf_reciever = lib_src.test_bench("tb_rf_reciever")

for freq in [20.00]:
    freq_error = -800; # frequency error in ppm
    config = {
        "samples": 100e3,                              # number of samples
        "freq": freq * 1e6 * (1 + freq_error/1e6),     # frequency in Hz
        "ampl": 0.5,                                   # maximum amplitude in percent,
        "offset": 0.1,                                 # dc offset
        "SNR":  3,                                     # signal to noise ratio in dB
        "data": [1 + 1j, -1 + 1j, 0, -1 - 1j, +1 - 1j] # data to send
    }
    
    checker = iq_checker.iq_checker(config, True)
    tb_rf_reciever.add_config(
        name=f"freq_{freq}MHz", 
        generics=dict(target_freq=freq*1e6), 
        pre_config=checker.pre_config,
        post_check=checker.post_check
    );
    
# ============================= FINAL =============================

# run script
vu.main()