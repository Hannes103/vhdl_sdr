library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

use std.textio.all;

use work.dds_generator_pgk.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_iq_demod is
  generic (runner_cfg : string; tb_path : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity;

architecture tb of tb_iq_demod is
    constant C_SAMPLE_FREQ : real := 100.0e6;
    constant C_TARGET_FREQ : real :=  5.01e6;
    
    constant C_DATA_WIDTH : integer                     := 16;
    constant C_CARRIER_PHASE_WIDTH : integer            := 5;
    constant C_CARRIER_PHASE_FRACTIONAL_BITS : integer  := 10;
    constant C_CIC_ORDER : integer                      := 4;
    constant C_CIC_DECIMATION : integer                 := 8;
    
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    signal s_phase_step : std_logic_vector(C_CARRIER_PHASE_WIDTH + C_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    signal s_data : signed(C_DATA_WIDTH - 1 downto 0);
    signal s_data_i : sfixed(C_DATA_WIDTH - 1 downto 0);
    signal s_data_q : sfixed(C_DATA_WIDTH - 1 downto 0);
    signal s_out_data_valid : std_logic;
    signal s_in_data_valid : std_logic := '0';
    signal s_error_unfiltered : sfixed(C_DATA_WIDTH - 1 downto 0);
    
    signal s_cfg_target_frequency : std_logic_vector(C_CARRIER_PHASE_WIDTH + C_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
    signal s_cfg_enable_threshold : sfixed(C_DATA_WIDTH - 1 downto 0);
begin
    -- generate clock signal
    CreateClock(s_clk, 10 ns);
    
    proc_main : process
        file fin : text open read_mode is tb_path & "../../../Matlab/iq_data.txt";
        file fout : text;
        variable fstatus : file_open_status;
        
        variable line_in : line;
        variable line_out : line;
        variable input_data : integer;
        
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            set_timeout(runner, 20 ms);
            
            -- reset peripheral
            s_rst <= '1';
            WaitForClock(s_clk, 1);
            
            s_cfg_target_frequency <= to_phase_increment(C_CARRIER_PHASE_WIDTH, C_CARRIER_PHASE_FRACTIONAL_BITS, C_SAMPLE_FREQ, C_TARGET_FREQ);
            s_cfg_enable_threshold <= to_sfixed(1000, s_cfg_enable_threshold);
            
            s_rst <= '0';
            
            if run("manual_verification") then
                
                file_open(fstatus, fout, tb_path & "../../../Matlab/result.txt", write_mode);
                
                while not endfile(fin) loop
                    WaitForClock(s_clk);
                    
                    readline(fin, line_in);  
                    read(line_in, input_data);
                    
                    s_in_data_valid <= '1';
                    s_data <= to_signed(input_data, s_data);
                
                    if s_out_data_valid = '1' then
                        write(line_out, to_integer(s_data_i), RIGHT, 6);
                        write(line_out, to_integer(s_data_q), RIGHT, 12 );
                        write(line_out, to_integer(s_error_unfiltered), RIGHT, 16 );
                        writeline(fout, line_out);
                    end if;
                
                end loop;
                
                flush(fout);
                
            end if;
                
        end loop;
        
        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 10 ms);
    
    inst_UUT : entity work.iq_demod
        generic map(
            G_DATA_WIDTH                    => C_DATA_WIDTH,
            G_OUTPUT_FRACTIONAL_BITS        => 0,
            G_CARRIER_PHASE_WIDTH           => C_CARRIER_PHASE_WIDTH,
            G_CARRIER_PHASE_FRACTIONAL_BITS => C_CARRIER_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                     => C_CIC_ORDER,
            G_CIC_DECIMATION                => C_CIC_DECIMATION
        )
        port map(
            i_clk        => s_clk,
            i_rst        => s_rst,
            i_phase_step => s_phase_step,
            i_data       => s_data,
            i_data_valid => s_in_data_valid,
            o_data_i     => s_data_i,
            o_data_q     => s_data_q,
            o_data_valid => s_out_data_valid
        );
    
    inst_COSTA : entity work.costas_loop
        generic map(
            G_INPUT_DATA_WIDTH              => C_DATA_WIDTH,
            G_INPUT_FRACTIONAL_BITS         => 0,
            G_CARRIER_PHASE_WIDTH           => C_CARRIER_PHASE_WIDTH,
            G_CARRIER_PHASE_FRACTIONAL_BITS => C_CARRIER_PHASE_FRACTIONAL_BITS,
            G_MODULATION_TYPE               => "QAM-4"
        )
        port map(
            i_clk                  => s_clk,
            i_rst                  => s_rst,
            
            i_cfg_target_frequency => s_cfg_target_frequency,
            i_cfg_enable_threshold => s_cfg_enable_threshold,
            
            i_data_i           => s_data_i,
            i_data_q           => s_data_q,
            i_data_valid           => s_out_data_valid,
            
            o_phase_step       => s_phase_step,
            o_error_unfiltered => s_error_unfiltered
        );
    
    
    
end architecture;