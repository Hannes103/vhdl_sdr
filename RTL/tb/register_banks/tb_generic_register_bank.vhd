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

entity tb_generic_register_bank is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_generic_register_bank is
    constant C_ADDR_WIDTH : integer := 8;
    
    signal s_bus_handle : bus_master_t := new_bus(32, C_ADDR_WIDTH);
    
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
    
    signal s_drv_read_addr : unsigned(C_ADDR_WIDTH - 1 downto 0);
    signal s_drv_read_data : std_logic_vector(31 downto 0);
    signal s_drv_read_result : std_logic;
    signal s_drv_write_strobe : std_logic;
    signal s_drv_write_addr : unsigned(C_ADDR_WIDTH - 1 downto 0);
    signal s_drv_write_data : std_logic_vector(31 downto 0);
    signal s_drv_write_result : std_logic;
    
    signal s_dummy_register : std_logic_vector(31 downto 0);
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
       
    inst_UUT : entity work.generic_register_bank
        generic map(
            G_ADDR_WIDTH          => C_ADDR_WIDTH,
            G_REQUIRE_SECURE      => true,
            G_REQUIRE_PRIVILIEGED => false
        )
        port map(
            i_clk      => s_clk,
            i_rstn     => s_rstn,
            i_aw_addr  => s_aw_addr,
            i_aw_prot  => s_aw_prot,
            i_aw_valid => s_aw_valid,
            o_aw_ready => s_aw_ready,
            i_w_data   => s_w_data,
            i_w_valid  => s_w_valid,
            o_w_ready  => s_w_ready,
            i_w_strobe => s_w_strobe,
            o_b_resp   => s_b_resp,
            o_b_valid  => s_b_valid,
            i_b_ready  => s_b_ready,
            i_ar_addr  => s_ar_addr,
            i_ar_prot  => s_ar_prot,
            i_ar_valid => s_ar_valid,
            o_ar_ready => s_ar_ready,
            o_r_data   => s_r_data,
            o_r_resp   => s_r_resp,
            o_r_valid  => s_r_valid,
            i_r_ready  => s_r_ready,
            o_drv_read_addr    => s_drv_read_addr,
            i_drv_read_data    => s_drv_read_data,
            i_drv_read_result  => s_drv_read_result,
            o_drv_write_strobe => s_drv_write_strobe,
            o_drv_write_addr   => s_drv_write_addr,
            o_drv_write_data   => s_drv_write_data,
            i_drv_write_result => s_drv_write_result
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

            s_aw_prot <= "001";
            s_ar_prot <= "001";

            if run("axi_read_returns_correct_value") then       
                -- the following register exists            
                check_axi_lite(net, s_bus_handle, 8x"0", axi_resp_okay, 32x"FF00FF00");

                -- the following register does not exist!
                check_axi_lite(net, s_bus_handle, 8x"2", axi_resp_slverr, 32x"-");
                
            elsif run("axi_write_returns_correct_valid") then
                write_axi_lite(net, s_bus_handle, 8x"0", 32x"00FF00FF", axi_resp_slverr);
                write_axi_lite(net, s_bus_handle, 8x"1", 32x"00FF00FF", axi_resp_okay);
                write_axi_lite(net, s_bus_handle, 8x"1", 32x"00FF00FF", axi_resp_okay);
                
                wait_until_idle(net, s_bus_handle);   
           elsif run("axi_write_writes_to_register_can_be_read") then
                
                write_axi_lite(net, s_bus_handle, 8x"1", 32x"FFFF00FF", axi_resp_okay);
                wait_until_idle(net, s_bus_handle);   
                
                check_axi_lite(net, s_bus_handle, 8x"1", axi_resp_okay, 32x"FFFF00FF");
            elsif run("axi_instrction_read_returns_slave_error") then
                s_ar_prot <= "100";
                -- this register does exist but access should be denied because is a instrution access
                check_axi_lite(net, s_bus_handle, 8x"1", axi_resp_slverr, 32x"-");
               
            elsif run("axi_not_secure_write_returns_slave_error") then
                s_aw_prot <= "010";
                s_ar_prot <= "010";
                
                -- register that is writte does exist, but request should be denied because we are not secure
                write_axi_lite(net, s_bus_handle, 8x"1", 32x"00FF00FF", axi_resp_slverr);
                wait_until_idle(net, s_bus_handle);
                
                -- this register does exist but access should be denied because we are not secure
                check_axi_lite(net, s_bus_handle, 8x"1", axi_resp_slverr, 32x"-");
            end if;
                                    
            WaitForClock(s_clk, 1);
            
        end loop;
        test_runner_cleanup(runner);
    end process;
    
    -- this process implements the read portion of a dummy register driver
    proc_dummy_drv_read : process(s_drv_read_addr, s_dummy_register) is
    begin
        case to_integer(s_drv_read_addr) is
            when 0 =>
                s_drv_read_data <= x"FF00FF00";
                s_drv_read_result <= '1';
            when 1 =>
                s_drv_read_data <= s_dummy_register;
                s_drv_read_result <= '1';
            when others =>
                s_drv_read_data <= (others => 'X');
                s_drv_read_result <= '0';
        end case;      
    end process proc_dummy_drv_read;
    
    -- this process implements the write portion of a dummy register driver
    proc_dummy_drv_write : process(s_clk) is
    begin
        if rising_edge(s_clk) then
            if s_rstn = '0' then
                s_drv_write_result <= '0';
                
                s_dummy_register <= (others => '0');
                
            elsif s_drv_write_strobe = '1' then
                case to_integer(s_drv_write_addr) is
                    when 1 =>
                        s_dummy_register <= s_drv_write_data;
                        s_drv_write_result <= '1';
                    when others =>
                        s_drv_write_result <= '0';
                end case;  
            end if;
        end if;
    end process proc_dummy_drv_write;
    
    test_runner_watchdog(runner, 10 ms);

end architecture;