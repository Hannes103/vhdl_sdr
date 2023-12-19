library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

use ieee.math_real.all;

use std.env.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_cic_decimator is
  generic (runner_cfg : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity;

architecture tb of tb_cic_decimator is
    constant C_ORDER : integer := 4;
    constant C_DECIMATION : integer := 8;
    
    constant C_OUTPUT_FRACTIONAL_BITS : integer := 3;
    
    constant C_INPUT_WIDTH : integer := 8;
    constant C_INPUT_FRACTIONAL_BITS : integer := 3;

    
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    signal s_input_valid : std_logic;
    signal s_input : sfixed(C_INPUT_WIDTH - 1 downto -C_INPUT_FRACTIONAL_BITS);
    
    signal s_output : sfixed(C_INPUT_WIDTH - 1 downto -(C_OUTPUT_FRACTIONAL_BITS + C_INPUT_FRACTIONAL_BITS));
    signal s_output_valid : std_logic;
    
begin
    
    -- generate clock signal
    CreateClock(s_clk, 10 ns);
    
    proc_main : process
        
        procedure VerifyNextSample(
            signal p_clk : std_logic;
            signal p_output_valid : std_logic;
            signal p_output : sfixed;
            constant p_value : real;
            constant THRESHOLD : real := 0.1
        ) is
        begin
            wait until p_output_valid = '1' and rising_edge(p_clk);
            assert abs(to_real(p_output) - p_value) <= THRESHOLD;
        end procedure;
        
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            set_timeout(runner, 20 ms);

            -- reset peripheral
            s_rst <= '1';
            WaitForClock(s_clk, 1);
            s_rst <= '0';
            
            if run("step_response_matches") then
                -- verify that the step respons matches
                -- what we want is a step from 0 to 100.5 and the computed response should match
                -- something that matlab computes to a reasonable degree
                s_input <= to_sfixed(100.5, s_input);
                s_input_valid <= '1';
                WaitForClock(s_clk);
                
                VerifyNextSample(s_clk, s_output_valid, s_output,   0.000);
                VerifyNextSample(s_clk, s_output_valid, s_output,   1.717);
                VerifyNextSample(s_clk, s_output_valid, s_output,  37.785);
                VerifyNextSample(s_clk, s_output_valid, s_output,  92.400);
                VerifyNextSample(s_clk, s_output_valid, s_output, 100.500);
                VerifyNextSample(s_clk, s_output_valid, s_output, 100.500);
                
            elsif run("decimation_is_correctly_performed") then
                -- set input to fixed value, the exact value does not matter because we are only interrested whether the decimation works
                s_input <= to_sfixed(0, s_input);
                s_input_valid <= '1';
                WaitForClock(s_clk);
                
                -- wait until the first samples comes out of the decimator
                wait until rising_edge(s_clk) and s_output_valid = '1';
                
                -- now every 8th clock cycle we must get a new sample
                -- every other clock cycle must have the output valid flag low.
                for i in 1 to C_DECIMATION * 10 loop
                    WaitForClock(s_clk);
                    
                    if (i mod 8) = 0 then
                        assert s_output_valid = '1';
                    else
                        assert s_output_valid = '0';
                    end if;
                    
                end loop;
                
            elsif run("steps_response_matches_with_short_input_pause") then
                -- verify that the step respons matches
                -- what we want is a step from 0 to 100.5 and the computed response should match
                -- something that matlab computes to a reasonable degree
                s_input <= to_sfixed(100.5, s_input);
                s_input_valid <= '1';
                WaitForClock(s_clk);
                
                VerifyNextSample(s_clk, s_output_valid, s_output, 0.0);
                VerifyNextSample(s_clk, s_output_valid, s_output,   1.717);
                VerifyNextSample(s_clk, s_output_valid, s_output,  37.785);
                
                -- now we have short interruption of input data
                -- because we should not sample anything while the input is not valid we should be able to set the input to whatever we want
                s_input_valid <= '0';
                s_input <= to_sfixed(0, s_input);
                WaitForClock(s_clk, C_DECIMATION * 2);
                s_input_valid <= '1';
                s_input <= to_sfixed(100.5, s_input);
                
                -- continue sample vierification
                VerifyNextSample(s_clk, s_output_valid, s_output,  92.400);
                VerifyNextSample(s_clk, s_output_valid, s_output, 100.500);
                VerifyNextSample(s_clk, s_output_valid, s_output, 100.500);
            end if;
                
        end loop;
        
        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 10 ms);
    
    inst_UUT : entity work.cic_decimator
        generic map(
            G_ORDER       => C_ORDER,
            G_DECIMATION  => C_DECIMATION,
            G_INPUT_WIDTH => 8,
            G_INPUT_FRACTIONAL_BITS => C_INPUT_FRACTIONAL_BITS,
            G_OUTPUT_FRACTIONAL_BITS => C_OUTPUT_FRACTIONAL_BITS
        )
        
        port map(
            i_clk    => s_clk,
            i_rst    => s_rst,
            i_input  => s_input,
            i_input_valid => s_input_valid,
            o_output => s_output,
            o_output_valid => s_output_valid
        );
    
    
    
end architecture;