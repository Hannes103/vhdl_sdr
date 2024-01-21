library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_pid_simple is
  generic (runner_cfg : string); -- @suppress "Naming convention violation: generic name should match pattern '(C|G)_([A-Z0-9_]*)'"
end entity;

architecture tb of tb_pid_simple is
    constant C_DATA_WIDTH           : integer := 16;
    constant C_DATA_FRACTIONAL_BITS : integer := 0;
        
    constant C_COEF_WIDTH           : integer := 5;
    constant C_COEF_FRACTIONAL_BITS : integer := 8;
 
    signal s_clk : std_logic;
    signal s_rst : std_logic;
    
    signal s_input        : sfixed(C_DATA_WIDTH - 1 downto -C_DATA_FRACTIONAL_BITS);
    signal s_input_valid  : std_logic;
    signal s_output       : sfixed(C_DATA_WIDTH - 1 downto -C_DATA_FRACTIONAL_BITS);
    signal s_output_valid : std_logic;
    signal s_cfg_coef_A   : sfixed(C_COEF_WIDTH - 1 downto -C_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_B   : sfixed(C_COEF_WIDTH - 1 downto -C_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_C   : sfixed(C_COEF_WIDTH - 1 downto -C_COEF_FRACTIONAL_BITS);
    
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
    -- generate clock signal
    CreateClock(s_clk, 10 ns);
    
    proc_main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        
        while test_suite loop
            set_timeout(runner, 20 ms);
            
            -- reset DUT
            s_rst <= '1';
            WaitForClock(s_clk);
            s_rst <= '0';
            
            if run("P_response") then
                -- K = 2.31, Tn = inf, Tv = 0, Ta = 1
                s_cfg_coef_A <= to_sfixed( 2.31, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed( 0.00, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed(-2.31, s_cfg_coef_B);
                
                s_input <= to_sfixed(100, s_input);
                s_input_valid <= '1';
     
                for i in 0 to 8 loop
                    VerifyNextSample(s_clk, s_output_valid, s_output, 231.0);
                end loop;
                
            elsif run("PI_response") then
                -- K = 1.8, Tn = 2.0, Tv = 0, Ta = 1
                s_cfg_coef_A <= to_sfixed( 2.25, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed( 0.90, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed(-1.35, s_cfg_coef_B);
                
                s_input <= to_sfixed(100, s_input);
                s_input_valid <= '1';
     
                VerifyNextSample(s_clk, s_output_valid, s_output, 225.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 315.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 405.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 495.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 585.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 675.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 765.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 855.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 945.0);    
                
            elsif run("PD_response") then
                -- K = 0.05, Tn = inf, Tv = 0.2, Ta = 1
                s_cfg_coef_A <= to_sfixed( 0.07, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed(-0.04, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed(-0.03, s_cfg_coef_B);
                
                s_input <= to_sfixed(100, s_input);
                s_input_valid <= '1';
                
                VerifyNextSample(s_clk, s_output_valid, s_output, 7.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 7.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 7.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 7.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 7.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3.0);
            elsif run("PID_response") then
                -- K = 1.1, Tn = 0.1, Tv = 0.2, Ta = 1
                s_cfg_coef_A <= to_sfixed( 7.04, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed(10.12, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed( 4.84, s_cfg_coef_B);
                
                s_input <= to_sfixed(100, s_input);
                s_input_valid <= '1';
                
                VerifyNextSample(s_clk, s_output_valid, s_output, 704.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 1716.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 2904.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 3916.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 5104.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 6116.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 7304.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 8316.0);
                VerifyNextSample(s_clk, s_output_valid, s_output, 9504.0);
            end if;
            
        end loop;
        
        test_runner_cleanup(runner);
        
    end process proc_main;
    
    test_runner_watchdog(runner, 10 ms);
    
    inst_UUT : entity work.pid_simple
        generic map(
            G_DATA_WIDTH           => C_DATA_WIDTH,
            G_DATA_FRACTIONAL_BITS => C_DATA_FRACTIONAL_BITS,
            G_COEF_WIDTH           => C_COEF_WIDTH,
            G_COEF_FRACTIONAL_BITS => C_COEF_FRACTIONAL_BITS
        )
        port map(
            i_clk          => s_clk,
            i_rst          => s_rst,
            i_input        => s_input,
            i_input_valid  => s_input_valid,
            o_output       => s_output,
            o_output_valid => s_output_valid,
            i_cfg_coef_A   => s_cfg_coef_A,
            i_cfg_coef_B   => s_cfg_coef_B,
            i_cfg_coef_C   => s_cfg_coef_C
        );
    
    
end architecture tb;
    
