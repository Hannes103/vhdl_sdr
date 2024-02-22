library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.vc_context;

use vunit_lib.axi_lite_master_pkg.all;
use vunit_lib.bus_master_pkg.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

entity tb_adc_register_bank is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_adc_register_bank is
    constant C_ADDR_WIDTH : integer := 8;
    
    signal s_bus_handle : bus_master_t := new_bus(32, C_ADDR_WIDTH);
    
    -- AXI lite signals 
    signal s_clk : std_logic;
    signal s_rstn : std_logic;
    signal s_aw_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal s_aw_prot : std_logic_vector(2 downto 0);
    signal s_aw_valid : std_logic;
    signal s_aw_ready : std_logic;
    signal s_w_data : std_logic_vector(31 downto 0);
    signal s_w_valid : std_logic;
    signal s_w_ready : std_logic;
    signal s_w_strobe : std_logic_vector(3 downto 0);
    signal s_b_resp : std_logic_vector(1 downto 0);
    signal s_b_valid : std_logic;
    signal s_b_ready : std_logic;
    signal s_ar_addr : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal s_ar_prot : std_logic_vector(2 downto 0);
    signal s_ar_valid : std_logic;
    signal s_ar_ready : std_logic;
    signal s_r_data : std_logic_vector(31 downto 0);
    signal s_r_resp : std_logic_vector(1 downto 0);
    signal s_r_valid : std_logic;
    signal s_r_ready : std_logic;
    
    -- ADC control signals
    
    signal s_adc_aRst_n : std_logic;
    signal s_adc_sTestMode : std_logic;
    signal s_adc_sEnableAquisition : std_logic;
    signal s_adc_sRstBusy : std_logic;
    signal s_adc_sInitDoneRelay : std_logic;
    signal s_adc_sInitDoneADC : std_logic;
    signal s_adc_sConfigError : std_logic;
    signal s_adc_sDataOverflow : std_logic;
    signal s_adc_sCh1CouplingConfig : std_logic;
    signal s_adc_sCh2CouplingConfig : std_logic;
    signal s_adc_sCh1GainConfig : std_logic;
    signal s_adc_sCh2GainConfig : std_logic;
    signal s_adc_Ch1xxMultCoef : std_logic_vector(17 downto 0);
    signal s_adc_Ch1xxAddCoef : std_logic_vector(17 downto 0);
    signal s_adc_Ch2xxMultCoef : std_logic_vector(17 downto 0);
    signal s_adc_Ch2xxAddCoef : std_logic_vector(17 downto 0);
begin
    CreateClock(s_clk, 10 ns);
    
    inst_axi_lite_master: entity vunit_lib.axi_lite_master
        generic map(
            bus_handle => s_bus_handle
        )
        port map(
            aclk    => s_clk,
            arready => s_ar_ready,
            arvalid => s_ar_valid,
            araddr  => s_ar_addr,
            rready  => s_r_ready,
            rvalid  => s_r_valid,
            rdata   => s_r_data,
            rresp   => s_r_resp,
            awready => s_aw_ready,
            awvalid => s_aw_valid,
            awaddr  => s_aw_addr,
            wready  => s_w_ready,
            wvalid  => s_w_valid,
            wdata   => s_w_data,
            wstrb   => s_w_strobe,
            bvalid  => s_b_valid,
            bready  => s_b_ready,
            bresp   => s_b_resp
        );
       
    inst_UUT : entity work.adc_register_bank
        generic map(
            G_ADDR_WIDTH => C_ADDR_WIDTH
        )
        port map(
            i_clk                    => s_clk,
            i_rstn                   => s_rstn,
            i_aw_addr                => s_aw_addr,
            i_aw_prot                => s_aw_prot,
            i_aw_valid               => s_aw_valid,
            o_aw_ready               => s_aw_ready,
            i_w_data                 => s_w_data,
            i_w_valid                => s_w_valid,
            o_w_ready                => s_w_ready,
            i_w_strobe               => s_w_strobe,
            o_b_resp                 => s_b_resp,
            o_b_valid                => s_b_valid,
            i_b_ready                => s_b_ready,
            i_ar_addr                => s_ar_addr,
            i_ar_prot                => s_ar_prot,
            i_ar_valid               => s_ar_valid,
            o_ar_ready               => s_ar_ready,
            o_r_data                 => s_r_data,
            o_r_resp                 => s_r_resp,
            o_r_valid                => s_r_valid,
            i_r_ready                => s_r_ready,
            o_adc_aRst_n             => s_adc_aRst_n,
            o_adc_sTestMode          => s_adc_sTestMode,
            o_adc_sEnableAquisition  => s_adc_sEnableAquisition,
            i_adc_sRstBusy           => s_adc_sRstBusy,
            i_adc_sInitDoneRelay     => s_adc_sInitDoneRelay,
            i_adc_sInitDoneADC       => s_adc_sInitDoneADC,
            i_adc_sConfigError       => s_adc_sConfigError,
            i_adc_sDataOverflow      => s_adc_sDataOverflow,
            o_adc_sCh1CouplingConfig => s_adc_sCh1CouplingConfig,
            o_adc_sCh2CouplingConfig => s_adc_sCh2CouplingConfig,
            o_adc_sCh1GainConfig     => s_adc_sCh1GainConfig,
            o_adc_sCh2GainConfig     => s_adc_sCh2GainConfig,
            o_adc_Ch1xxMultCoef      => s_adc_Ch1xxMultCoef,
            o_adc_Ch1xxAddCoef       => s_adc_Ch1xxAddCoef,
            o_adc_Ch2xxMultCoef      => s_adc_Ch2xxMultCoef,
            o_adc_Ch2xxAddCoef       => s_adc_Ch2xxAddCoef
        );
    proc_main : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            set_timeout(runner, 10 us);

            -- perform a reset
            s_rstn <= '0';
            WaitForClock(s_clk, 2);
            s_rstn <= '1';

            s_aw_prot <= "000";
            s_ar_prot <= "000";

            if run("write_to_CR0_changes_reset") then
                -- check intial value after reset
                assert s_adc_aRst_n = '0';
            
                -- check whether we can set the reset flag
                
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000001", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_aRst_n = '1' report "Reset must not be active while CR->0 is set";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000001");
                
                -- check whether we can reset the reset flag
                
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000000", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);  
                
                assert s_adc_aRst_n = '0' report "Reset must be active while CR->0 is clear";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000000");
            elsif run("write_to_CR1_changes_EnableAquisition") then
                --check initial state after reset
                assert s_adc_sEnableAquisition = '0';
            
                -- check whether we can set the start aquisition flag
            
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000002", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sEnableAquisition = '1' report "EnableAquisition must be high while CR->1 is set";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000002");
                
                -- check whether we can reset the start aquisition flag
            
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000000", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sEnableAquisition = '0' report "EnableAquisition must be low while CR->1 is reset";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000000");
            
            elsif run("write_to_CR2_changes_testMode") then
                --check initial state after reset
                assert s_adc_sTestMode = '0';
            
                -- check whether we can set the test mode flag
            
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000004", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sTestMode = '1' report "TestMode must be high while CR->2 is set";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000004");
                
                -- check whether we can reset the test mode flag
            
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000000", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sTestMode = '0' report "TestMode must be low while CR->2 is reset";
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000000");
            elsif run("write_to_CR3_4_5_6_changes_values") then
                -- check initial value after reset
                assert s_adc_sCh1CouplingConfig = '0';  
                assert s_adc_sCh1GainConfig = '0';
                assert s_adc_sCh2CouplingConfig = '0';
                assert s_adc_sCh2GainConfig = '0';
            
                -- check write for coupling
                
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000028", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sCh1CouplingConfig = '1';  
                assert s_adc_sCh1GainConfig = '0';
                assert s_adc_sCh2CouplingConfig = '1';
                assert s_adc_sCh2GainConfig = '0';
                
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000028");
                
                -- check write for gain
                
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000050", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sCh1CouplingConfig = '0';  
                assert s_adc_sCh1GainConfig = '1';
                assert s_adc_sCh2CouplingConfig = '0';
                assert s_adc_sCh2GainConfig = '1';
                
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000050");
            
            elsif run("write_to_CR3_4_5_6_does_not_work_if_enabled") then
                -- enable ADC
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000001", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);  
                
                -- try to change configuration
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00000079", axi_resp_okay);            
                wait_until_idle(net, s_bus_handle);   
                
                assert s_adc_sCh1CouplingConfig = '0';  
                assert s_adc_sCh1GainConfig = '0';
                assert s_adc_sCh2CouplingConfig = '0';
                assert s_adc_sCh2GainConfig = '0';
                
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"00000001");
                
            elsif run("read_from_SR_returns_state") then
                s_adc_sRstBusy <= '1';
                s_adc_sInitDoneADC <= '0';
                s_adc_sInitDoneRelay <= '1';
                s_adc_sConfigError <= '0';
                s_adc_sDataOverflow <= '1';
                
                check_axi_lite(net, s_bus_handle, 8x"4", axi_resp_okay, 32x"00000025");
            
                s_adc_sRstBusy <= '0';
                s_adc_sInitDoneADC <= '1';
                s_adc_sInitDoneRelay <= '0';
                s_adc_sConfigError <= '1';
                s_adc_sDataOverflow <= '0';
                
                check_axi_lite(net, s_bus_handle, 8x"4", axi_resp_okay, 32x"00000012");
            
            elsif run("write_to_calib1_mult_add_changes_values") then
                assert s_adc_Ch1xxMultCoef = 18x"10000";
                assert s_adc_Ch1xxAddCoef  = 18x"00000";
            
                write_axi_lite(net, s_bus_handle, 8x"8", 32x"0000F55F", axi_resp_okay); -- calib_ch1_mult  
                write_axi_lite(net, s_bus_handle, 8x"C", 32x"0000AB0A", axi_resp_okay); -- calib_ch1_add
                wait_until_idle(net, s_bus_handle);  
                
                assert s_adc_Ch1xxMultCoef = 18x"0F55F";    
                assert s_adc_Ch1xxAddCoef  = 18x"0AB0A";
                
                check_axi_lite(net, s_bus_handle, 8x"8", axi_resp_okay, 32x"0000F55F");
                check_axi_lite(net, s_bus_handle, 8x"C", axi_resp_okay, 32x"0000AB0A");
            
            elsif run("write_to_calib2_mult_add_changes_values") then
                assert s_adc_Ch2xxMultCoef = 18x"10000";
                assert s_adc_Ch2xxAddCoef  = 18x"00000";
            
                write_axi_lite(net, s_bus_handle, 8x"10", 32x"000055FF", axi_resp_okay); -- calib_ch2_mult  
                write_axi_lite(net, s_bus_handle, 8x"14", 32x"0000ABCD", axi_resp_okay); -- calib_ch2_add
                wait_until_idle(net, s_bus_handle);  
                
                assert s_adc_Ch2xxMultCoef = 18x"055FF";    
                assert s_adc_Ch2xxAddCoef  = 18x"0ABCD";
                
                check_axi_lite(net, s_bus_handle, 8x"10", axi_resp_okay, 32x"000055FF");
                check_axi_lite(net, s_bus_handle, 8x"14", axi_resp_okay, 32x"0000ABCD");
            end if;
                                    
            WaitForClock(s_clk, 1);
            
        end loop;
        test_runner_cleanup(runner);
    end process;
    
    test_runner_watchdog(runner, 10 ms);

end architecture;