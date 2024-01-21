library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

use work.dds_generator_pgk.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_dds_generator is
  generic (runner_cfg : string; tb_path : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity;

architecture tb of tb_dds_generator is
    constant C_OUTPUT_FREQUENCY : real     := 25.0e6;
    constant C_NUMBER_OF_SAMPLES : integer := 100e3;
    
    constant C_PHASE_WIDTH : integer           := 11;
    constant C_PHASE_FRACTIONAL_BITS : integer := 16;
    
    constant C_SIGNAL_WIDTH : integer := 16;
    
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    
    signal s_phase_step : std_logic_vector(C_PHASE_WIDTH + C_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    signal s_sin : std_logic_vector(C_SIGNAL_WIDTH - 1 downto 0);
    signal s_cos : std_logic_vector(C_SIGNAL_WIDTH - 1 downto 0);
begin
    -- generate clock signal
    CreateClock(s_clk, 10 ns);
    
    proc_main : process
        file     fresult : text;
        variable fstatus : file_open_status;
        variable output  : line;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            set_timeout(runner, 20 ms);

            -- reset peripheral
            s_rst <= '1';
            WaitForClock(s_clk, 1);
            s_phase_step <= to_phase_increment(C_PHASE_WIDTH, C_PHASE_FRACTIONAL_BITS, 100.0e6, C_OUTPUT_FREQUENCY);
            s_rst <= '0';
            
            if run("export_data") then
                -- open output file for writing
                file_open(fstatus, fresult, tb_path & "../../../Matlab/carrier.txt", write_mode);
                
                for i in 0 to C_NUMBER_OF_SAMPLES loop
                    write(output, to_integer(signed(s_cos)), RIGHT, 6  );
                    write(output, to_integer(signed(s_sin)), RIGHT, 12 );
                    writeline(fresult, output);
                
                    WaitForClock(s_clk);
                end loop;
                
                flush(fresult);
            end if;
                
        end loop;
        
        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 10 ms);
    
    inst_UUT : entity work.dds_generator
        generic map(
            G_PHASE_WIDTH           => C_PHASE_WIDTH,
            G_PHASE_FRACTIONAL_BITS => C_PHASE_FRACTIONAL_BITS,
            G_SIGNAL_WIDTH          => C_SIGNAL_WIDTH,
            
            G_ENABLE_INTERPOLATION  => true,
            G_INVERT_OUTPUT         => true,
            G_ENABLE_SHIFTED_OUTPUT => true,
            G_INVERT_SHIFTED_OUTPUT => false
        )
        port map(
            i_clk    => s_clk,
            i_clk_en => '1',
            i_rst    => s_rst,
            i_phase_step => s_phase_step,
            o_output => s_sin,
            o_output_shifted => s_cos
        );
    
    
end architecture;