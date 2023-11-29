import os
from vunit import VUnit

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

# ============================= FINAL =============================

# run script
vu.main()