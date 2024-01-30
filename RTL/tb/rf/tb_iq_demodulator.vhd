library ieee;

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.math_real.all;

use work.dds_generator_pgk.all;
use work.iq_demodulator_pkg.all;

use std.textio.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_iq_demodulator is 
 generic ( runner_cfg : string; output_path : string; target_freq : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity tb_iq_demodulator;

architecture tb of tb_iq_demodulator is
    constant C_OUTPUT_COUNT : integer          := 1;
    constant C_PHASE_WIDTH : integer           := 10;
    constant C_PHASE_FRACTIONAL_BITS : integer := 11;
    constant C_SIGNAL_WIDTH : integer          := 16;
    
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    
    signal s_cfg_phase_step : std_logic_vector(C_PHASE_WIDTH + C_PHASE_FRACTIONAL_BITS - 1  downto 0);
    
    signal s_input : signed(C_SIGNAL_WIDTH - 1 downto 0);
    signal s_input_ready : std_logic;
    signal s_input_valid : std_logic;
    
    signal s_output_valid : std_logic_vector(C_OUTPUT_COUNT - 1 downto 0);
    signal s_output_i : t_sfixed_array(C_OUTPUT_COUNT - 1 downto 0)(C_SIGNAL_WIDTH - 1 downto 0);
    signal s_output_q : t_sfixed_array(C_OUTPUT_COUNT - 1 downto 0)(C_SIGNAL_WIDTH - 1 downto 0);
    signal s_enable_output : std_logic;
    
begin
    
    CreateClock(s_clk, 10 ns);
    
    proc_read_stimuli : process is
        -- Variables: used for TEXTIO input
        
        file     finput : text;
        variable fstatus : file_open_status;
        variable input  : line;
        
        -- Variables: used to read from the line
        
        variable data   : integer;
        
        -- Constants

        constant C_FILE_NAME :  string := output_path & "/input.txt";        
    begin
        test_runner_setup(runner, runner_cfg);
        
        while test_suite loop
            set_timeout(runner, 100 ms);

            -- reset peripheral
            s_rst <= '1';
            WaitForClock(s_clk, 1);
            s_cfg_phase_step <= to_phase_increment(C_PHASE_WIDTH, C_PHASE_FRACTIONAL_BITS, 100.0e6, real'value(target_freq));
            s_rst <= '0';

            if run("import_export_data") then
                
                -- open output file for reading
                file_open(fstatus, finput, C_FILE_NAME, read_mode);
                if fstatus /= OPEN_OK then
                    report "File " & C_FILE_NAME & " cannot be opened for reading!" severity error;    
                end if;
                
                -- this signal is used to communicate with the writing process that 
                -- outputs the sample data
                s_enable_output <= '1';
                
                while not endfile(finput) loop
                    
                    -- read input from file
                    readline(finput, input);
                    if input.all'length = 0 or input.all(1) = '#' then
                        next;
                    end if;
                    
                    -- read data from file
                    read(input, data);
                    
                    -- present input to demodulator
                    s_input_valid <= '1';
                    s_input <= to_signed(data, s_input);
                    WaitForClock(s_clk, s_input_ready);
                end loop;   
                
                s_enable_output <= '0';             
            end if;              
        end loop;
        
        test_runner_cleanup(runner);  
    end process proc_read_stimuli;
    
    proc_write_output : process is
        file     foutput : text;
        variable fstatus : file_open_status;
        variable output  : line;
        
        -- output file name
        constant C_FILE_NAME :  string := output_path & "/baseband.txt";
    begin
        
        -- this process is only active once output writing is enabled
        wait until s_enable_output = '1';
        
        -- open file that contains the resulting baseband signal
        file_open(fstatus, foutput, C_FILE_NAME, write_mode);
        if fstatus /= OPEN_OK then
            report "File " & C_FILE_NAME & " cannot be opened for writing! (Error:" & file_open_status'image(fstatus) & ")" severity error;    
        end if;
        
        -- write inphase and quadrature samples to file while output is enabled
        while s_enable_output = '1' loop
            WaitForClock(s_clk, s_output_valid(0));
            write(output, to_integer(s_output_i(0)), RIGHT, 8);
            write(output, to_integer(s_output_q(0)), RIGHT,16);
            writeline(foutput, output);
        end loop;
        
    end process proc_write_output;
    
    test_runner_watchdog(runner, 10 ms);
    
    
    inst_UUT : entity work.iq_demodulator
        generic map(
            G_DATA_WIDTH                    => C_SIGNAL_WIDTH,
            G_OUTPUT_FRACTIONAL_BITS        => 0,
            G_CARRIER_PHASE_WIDTH           => C_PHASE_WIDTH,
            G_CARRIER_PHASE_FRACTIONAL_BITS => C_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                     => 4,
            G_CIC_DECIMATION                => 8,
            G_OUTPUT_COUNT                  => C_OUTPUT_COUNT
        )
        port map(
            i_clk            => s_clk,
            i_rst            => s_rst,
            i_cfg_phase_step => s_cfg_phase_step,
            i_input          => s_input,
            o_input_ready    => s_input_ready,
            i_input_valid    => s_input_valid,
            o_output_i       => s_output_i,
            o_output_q       => s_output_q,
            o_output_valid   => s_output_valid,
            i_output_ready   => (others => '1')
        );
    
    
end architecture tb;