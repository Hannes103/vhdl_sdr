library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library unisim;
use unisim.VCOMPONENTS.FDRE;


entity tb_unisim_test is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_unisim_test is
    signal s_rst : std_logic;
    signal s_clk : std_logic;
    signal s_out : std_ulogic;
    signal s_in : std_ulogic;
begin
    
    CreateClock(s_clk, 10 ns);
    
    proc_main : process
    begin
        test_runner_setup(runner, runner_cfg);
        
        while test_suite loop
            s_rst <= '1';
            WaitForClock(s_clk);
            s_rst <= '0';
            s_in <= '0';
            
            if run("do_test") then
                s_in <= '1';
                WaitForClock(s_clk);
                s_in <= '0';
                WaitForClock(s_clk);
                s_in <= '1';
                WaitForClock(s_clk);                
            end if;
        end loop;
        
        WaitForClock(s_clk);
        
        test_runner_cleanup(runner);
    end process proc_main;
    
    inst_FF1 : FDRE
        generic map(
            INIT => '0',
            IS_C_INVERTED => '0',
            IS_D_INVERTED => '0',
            IS_R_INVERTED => '0'
        )
        port map(
            Q  => s_out,
            C  => s_clk,
            CE => '1',
            D  => s_in,
            R  => s_rst
        );
    
    
end architecture tb;