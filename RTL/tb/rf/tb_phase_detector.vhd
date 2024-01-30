library ieee;

library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.math_real.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_phase_detector is 
 generic ( runner_cfg : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity tb_phase_detector;

architecture tb of tb_phase_detector is
    constant C_SIGNAL_WIDTH : integer          := 16;
    
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    
    signal s_input_i : sfixed( C_SIGNAL_WIDTH - 1 downto 0 );
    signal s_input_q : sfixed( C_SIGNAL_WIDTH - 1 downto 0 );
    signal s_input_valid : std_logic;
    signal s_input_ready : std_logic;
    
    signal s_output : sfixed(C_SIGNAL_WIDTH - 1 downto 0);
    signal s_output_valid : std_logic;
    signal s_output_ready : std_logic;
    
    signal s_cfg_mode : std_logic;
begin
    
    CreateClock(s_clk, 10 ns);
    
    proc_main : process is
        variable is_sucessfull : boolean := false;
        
        procedure VerifyResult(i : integer; q : integer; expected : integer) is
        begin
            -- insert a single valid sample into the phase detector
            s_input_i <= to_sfixed(i, s_input_i);
            s_input_q <= to_sfixed(q, s_input_q);
            s_input_valid <= '1';
                    
            -- wait until the sample was latched
            WaitForClock(s_clk, s_input_ready);
            s_input_valid <= '0';
            
            -- wait for valid output sample
            WaitForClock(s_clk, s_output_valid);
            
            -- verify that result is correct
            assert s_output = (expected) report "Output does not match expected value! (Got: " & to_string(to_integer(s_output)) & " expected: " & to_string(expected) & ")";
            
            -- acknowlege output
            s_output_ready <= '1';
            WaitForClock(s_clk);
            s_output_ready <= '0';
        end procedure VerifyResult;
        
    begin
        test_runner_setup(runner, runner_cfg);
        
        while test_suite loop
            set_timeout(runner, 100 ms);

            -- reset peripheral
            s_rst <= '1';
            s_input_valid <= '0';
            s_output_ready <= '0';
            WaitForClock(s_clk, 1);
            s_rst <= '0';

            if run("bypass_mode_returns_inverted_q_samples") then
                s_cfg_mode <= '0'; -- mode = bypass
                
                for i in 0 to 4 loop
                    VerifyResult(i * 510, i * 250, i * 250);
                end loop;
                
            elsif run("bypass_mode_returns_within_2_clock_cycles") then
                s_cfg_mode <= '0'; -- mode = bypass
                
                for i in 0 to 4 loop
                    -- insert a single valid sample into the phase detector
                    s_input_i <= to_sfixed(i *  2000,  s_input_i);
                    s_input_q <= to_sfixed(i *(-2000), s_input_q);
                    s_input_valid <= '1';
                    
                    -- wait until the sample was latched
                    WaitForClock(s_clk, s_input_ready);
                    s_input_valid <= '0';
                    
                    -- check that we have a most 3 clock cycles from sample to output
                    is_sucessfull := false;
                    for j in 0 to 2 loop
                        WaitForClock(s_clk);
                        if s_output_valid = '1' then
                            is_sucessfull := true;
                            exit;
                        end if;
                    end loop;
                    
                    -- verify that the latency requirement was met
                    if is_sucessfull = false then
                        report "Input to output latency is higher than 3 clock cycles!" severity error;
                    end if;
                    
                    assert s_output = s_input_q;
                    
                    
                    -- acknowlege output
                    s_output_ready <= '1';
                    WaitForClock(s_clk);
                    s_output_ready <= '0';
                end loop;
            
            elsif run("multiply_mode_returns_within_3_clock_cycles") then
                s_cfg_mode <= '1'; -- mode = bypass
                
                for i in 0 to 4 loop
                    -- insert a single valid sample into the phase detector
                    s_input_i <= to_sfixed(i *  2000,  s_input_i);
                    s_input_q <= to_sfixed(i *(-2000), s_input_q);
                    s_input_valid <= '1';
                    
                    -- wait until the sample was latched
                    WaitForClock(s_clk, s_input_ready);
                    s_input_valid <= '0';
                    
                    -- check that we have a most 3 clock cycles from sample to output
                    is_sucessfull := false;
                    for j in 0 to 2 loop
                        WaitForClock(s_clk);
                        if s_output_valid = '1' then
                            is_sucessfull := true;
                            exit;
                        end if;
                    end loop;
                    
                    -- verify that the latency requirement was met
                    if is_sucessfull = false then
                        report "Input to output latency is higher than 3 clock cycles!" severity error;
                    end if;
                    
                    -- result should be zero because we are on the 45 deg lines of the constellation
                    assert s_output = 0;
                    
                    -- acknowlege output
                    s_output_ready <= '1';
                    WaitForClock(s_clk);
                    s_output_ready <= '0';
                end loop;
                
            elsif run("multipler_mode_returns_correct_value_Q1") then
                s_cfg_mode <= '1'; -- mode = multiply
                
                for i in 0 to 4 loop
                    VerifyResult(i * 1000, i * 2000, i * 1000);
                end loop;
                
            elsif run("multipler_mode_returns_correct_value_Q2") then
                s_cfg_mode <= '1'; -- mode = multiply
                
                for i in 0 to 4 loop
                    VerifyResult(i * 1000, i * (-2000), i * (-1000));
                end loop;
                
            elsif run("multipler_mode_returns_correct_value_Q3") then
                s_cfg_mode <= '1'; -- mode = multiply
                
                for i in 0 to 4 loop
                    VerifyResult(i * (-1000), i * (2000), i * (-1000));
                end loop;
                
            elsif run("multipler_mode_returns_correct_value_Q4") then
                s_cfg_mode <= '1'; -- mode = multiply
                
                for i in 0 to 4 loop
                    VerifyResult(i * (1000), i * (-2000), i * (-1000));
                end loop;
                
            end if;

        end loop;
        
        test_runner_cleanup(runner);  
    end process proc_main;
 
    test_runner_watchdog(runner, 10 ms);
    
    inst_UUT : entity work.phase_detector
        generic map(
            G_INPUT_DATA_WIDTH      => C_SIGNAL_WIDTH,
            G_INPUT_FRACTIONAL_BITS => 0
        )
        port map(
            i_clk          => s_clk,
            i_rst          => s_rst,
            i_input_i      => s_input_i,
            i_input_q      => s_input_q,
            i_input_valid  => s_input_valid,
            o_input_ready  => s_input_ready,
            o_output       => s_output,
            o_output_valid => s_output_valid,
            i_output_ready => s_output_ready,
            i_cfg_mode     => s_cfg_mode
        );
    
    
end architecture tb;