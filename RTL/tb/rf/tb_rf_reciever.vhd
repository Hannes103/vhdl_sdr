library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.vc_context;

use vunit_lib.axi_stream_pkg.all;
use vunit_lib.bus_master_pkg.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;
use ieee.math_real.all;

use work.dds_generator_pgk.all;
use work.iq_demodulator_pkg.all;

use std.textio.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_rf_reciever is 
 generic ( runner_cfg : string; output_path : string; target_freq : string ); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity tb_rf_reciever;

architecture tb of tb_rf_reciever is
    signal input_bus : axi_stream_master_t := new_axi_stream_master(16);
    signal output_bus : axi_stream_slave_t := new_axi_stream_slave(32);
    
    constant C_DATA_WIDTH      : integer                     := 16;
    constant C_ROUNDING_MODE   : fixed_round_style_type      := FIXED_TRUNCATE;
    constant C_NCO_PHASE_WIDTH : integer                     := 10;
    constant C_NCO_PHASE_FRACTIONAL_BITS : integer           := 11;
    constant C_CIC_ORDER : integer                           := 4;
    constant C_CIC_DECIMATION : integer                      := 8;
    constant C_PHASE_DETECTOR_COEF_WIDTH : integer           := 8;
    constant C_PHASE_DETECTOR_COEF_FRACTIONAL_BITS : integer := 10;
    
    signal s_clk : std_logic;
    signal s_rst : std_logic;

    signal s_input : signed(C_DATA_WIDTH - 1 downto 0);
    signal s_input_slv : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal s_input_valid : std_logic;
    signal s_input_ready : std_logic;
    
    signal s_output_i : sfixed(C_DATA_WIDTH - 1 downto 0);
    signal s_output_q : sfixed(C_DATA_WIDTH - 1 downto 0);
    signal s_output_valid : std_logic;
    signal s_output_ready : std_logic;
    
    signal s_cfg_nco_frequency : sfixed(C_NCO_PHASE_WIDTH - 1 downto -C_NCO_PHASE_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_enable : std_logic;
    signal s_cfg_phase_detector_mode : std_logic;
    signal s_cfg_phase_detector_coef_A : sfixed(C_PHASE_DETECTOR_COEF_WIDTH - 1 downto -C_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_B : sfixed(C_PHASE_DETECTOR_COEF_WIDTH - 1 downto -C_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_C : sfixed(C_PHASE_DETECTOR_COEF_WIDTH - 1 downto -C_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    
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
        
        constant K  : real :=  2.50;
        constant Tn : real := 20.50;
    begin
        test_runner_setup(runner, runner_cfg);
        
        while test_suite loop
            set_timeout(runner, 100 ms);

            -- reset peripheral
            s_rst <= '1';
            WaitForClock(s_clk, 1);
            s_rst <= '0';

            if run("import_export_data") then
                
                s_cfg_nco_frequency <= to_sfixed(to_phase_increment(C_NCO_PHASE_WIDTH, C_NCO_PHASE_FRACTIONAL_BITS, 100.0e6, real'value(target_freq)), C_NCO_PHASE_WIDTH - 1 , -C_NCO_PHASE_FRACTIONAL_BITS);
                s_cfg_phase_detector_enable <= '1';
                s_cfg_phase_detector_mode <= '1';
                s_cfg_phase_detector_coef_A <= to_sfixed( K*(1.0 - 1.0/(2.0*Tn)) , s_cfg_phase_detector_coef_A); -- A = K*(1 + Ta/(2*Tn) + (2*Tv)/Ta)
                s_cfg_phase_detector_coef_B <= to_sfixed( K*(1.0/Tn)             , s_cfg_phase_detector_coef_B); -- B = K*(Ta/Tn - (4*Tv)/Ta)
                s_cfg_phase_detector_coef_C <= to_sfixed( K*(1.0/(2.0*Tn) - 1.0) , s_cfg_phase_detector_coef_C); -- C = K*(Ta/(2*Tn) + (2*Tv)/Ta - 1)
                
                
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
                    
                    push_axi_stream(net, input_bus, std_logic_vector(to_signed(data, 16)));
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
        
        variable data : std_logic_vector(31 downto 0);
        variable last : std_logic;
        
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
            
            pop_axi_stream(net, output_bus, data, last);
            
            write(output, to_integer( signed( data(15 downto  0) ) ), RIGHT, 8);
            write(output, to_integer( signed( data(31 downto 16) ) ), RIGHT,16);
            
            writeline(foutput, output);
            
        end loop;
        
    end process proc_write_output;
    
    test_runner_watchdog(runner, 10 ms);
    
    inst_input_master : entity vunit_lib.axi_stream_master
        generic map(
            master  => input_bus
        )
        port map(
            aclk     => s_clk,
            areset_n => not s_rst,
            tvalid   => s_input_valid,
            tready   => s_input_ready,
            tdata    => s_input_slv,
            tlast    => open,
            tkeep    => open,
            tstrb    => open,
            tid      => open,
            tdest    => open,
            tuser    => open
        );
    s_input <= signed(s_input_slv);
        
    inst_output_slave : entity vunit_lib.axi_stream_slave
        generic map(
            slave => output_bus
        )
        port map(
            aclk     => s_clk,
            areset_n => not s_rst,
            tvalid   => s_output_valid,
            tready   => s_output_ready,
            tdata    => std_logic_vector(s_output_q) & std_logic_vector(s_output_i),
            tlast    => open,
            tkeep    => open,
            tstrb    => open,
            tid      => open,
            tdest    => open,
            tuser    => open
        );
    
    inst_UUT : entity work.rf_reciever
        generic map(
            G_DATA_WIDTH                          => C_DATA_WIDTH,
            G_ROUNDING_MODE                       => C_ROUNDING_MODE,
            G_NCO_PHASE_WIDTH                     => C_NCO_PHASE_WIDTH,
            G_NCO_PHASE_FRACTIONAL_BITS           => C_NCO_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                           => C_CIC_ORDER,
            G_CIC_DECIMATION                      => C_CIC_DECIMATION,
            G_PHASE_DETECTOR_COEF_WIDTH           => C_PHASE_DETECTOR_COEF_WIDTH,
            G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS => C_PHASE_DETECTOR_COEF_FRACTIONAL_BITS
        )
        port map(
            i_clk                       => s_clk,
            i_rst                       => s_rst,
            i_input                     => s_input,
            i_input_valid               => s_input_valid,
            o_input_ready               => s_input_ready,
            o_output_0_i                  => s_output_i,
            o_output_0_q                  => s_output_q,
            o_output_0_valid              => s_output_valid,
            i_output_0_ready              => s_output_ready,
            i_cfg_nco_frequency         => s_cfg_nco_frequency,
            i_cfg_phase_detector_enable => s_cfg_phase_detector_enable,
            i_cfg_phase_detector_mode   => s_cfg_phase_detector_mode,
            i_cfg_phase_detector_coef_A => s_cfg_phase_detector_coef_A,
            i_cfg_phase_detector_coef_B => s_cfg_phase_detector_coef_B,
            i_cfg_phase_detector_coef_C => s_cfg_phase_detector_coef_C
        );
    
    
end architecture tb;