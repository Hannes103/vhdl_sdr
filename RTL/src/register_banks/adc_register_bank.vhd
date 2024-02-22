library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_register_bank is
    
    generic(
        G_ADDR_WIDTH : integer range 2 to 32 := 2
    );
    
    port(
        -- Global AXI-Lite signals

        i_clk     : in std_logic;
        i_rstn    : in std_logic;

        -- AXI-Lite write address channel

        i_aw_addr  : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        i_aw_prot  : in std_logic_vector(2 downto 0);
        i_aw_valid : in std_logic;
        o_aw_ready : out std_logic;

        -- AXI-Lite write data channel

        i_w_data   : in std_logic_vector(31 downto 0);
        i_w_valid  : in std_logic;
        o_w_ready  : out std_logic;
        i_w_strobe : in std_logic_vector(3 downto 0); -- @suppress "Unused port: i_w_strobe is not used in src.generic_register_bank(behav)"

        -- AXI-Lite write response channel

        o_b_resp     : out std_logic_vector(1 downto 0);
        o_b_valid    : out std_logic;
        i_b_ready    : in std_logic;

        -- AXI-Lite read address channel

        i_ar_addr  : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        i_ar_prot  : in std_logic_vector(2 downto 0);
        i_ar_valid : in std_logic;
        o_ar_ready : out std_logic;

        -- AXI-Lite read response/data channel

        o_r_data  : out std_logic_vector(31 downto 0);
        o_r_resp  : out std_logic_vector(1 downto 0);
        o_r_valid : out std_logic;
        i_r_ready : in std_logic;
        
        -- Generic ADC control signals
        o_adc_aRst_n : out std_logic;
        o_adc_sTestMode : out std_logic;
        o_adc_sEnableAquisition : out std_logic;
        
        -- Generic ADC status signals
        
        i_adc_sRstBusy : in std_logic;
        i_adc_sInitDoneRelay : in std_logic;
        i_adc_sInitDoneADC : in std_logic;
        i_adc_sConfigError : in std_logic;
        i_adc_sDataOverflow : in std_logic;
        
        -- ADC conrol signals for channel 1 and 2 relay configuration
        
        o_adc_sCh1CouplingConfig : out std_logic;
        o_adc_sCh2CouplingConfig : out std_logic;
        o_adc_sCh1GainConfig : out std_logic;
        o_adc_sCh2GainConfig : out std_logic;
        
        -- ADC calibraton control signals for both channels 
        o_adc_Ch1xxMultCoef : out std_logic_vector(17 downto 0);
        o_adc_Ch1xxAddCoef : out std_logic_vector(17 downto 0);
        o_adc_Ch2xxMultCoef : out std_logic_vector(17 downto 0);
        o_adc_Ch2xxAddCoef : out std_logic_vector(17 downto 0)
    );
    
end entity adc_register_bank;

architecture behav of adc_register_bank is
    
    -- Constants that define the register offsets 
    
    constant C_OFFSET_REG_CR : integer := 0;
    constant C_OFFSET_REG_SR : integer := 4;
    constant C_OFFSET_REG_CALIB1_MULT : integer := 8;
    constant C_OFFSET_REG_CALIB1_ADD  : integer := 12;
    constant C_OFFSET_REG_CALIB2_MULT : integer := 16;
    constant C_OFFSET_REG_CALIB2_ADD  : integer := 20;
    
    -- Backing registers
    
    signal s_reg_cr             : std_logic_vector(6 downto 0);
    signal s_reg_calib_ch1_mult : std_logic_vector(17 downto 0);
    signal s_reg_calib_ch1_add  : std_logic_vector(17 downto 0);
    signal s_reg_calib_ch2_mult : std_logic_vector(17 downto 0);
    signal s_reg_calib_ch2_add  : std_logic_vector(17 downto 0);
    
    -- Signals used by generic register bank
    
    signal s_drv_read_addr : unsigned(G_ADDR_WIDTH - 1 downto 0);
    signal s_drv_read_data : std_logic_vector(31 downto 0);
    signal s_drv_read_result : std_logic;
    signal s_drv_write_strobe : std_logic;
    signal s_drv_write_addr : unsigned(G_ADDR_WIDTH - 1 downto 0);
    signal s_drv_write_data : std_logic_vector(31 downto 0);
    signal s_drv_write_result : std_logic;
begin
    
    -- Generic register bank that handles the entire axi lite protocoll for us
    inst_generic_bank : entity work.generic_register_bank
        generic map(
            G_ADDR_WIDTH          => G_ADDR_WIDTH,
            G_REQUIRE_SECURE      => false,
            G_REQUIRE_PRIVILIEGED => false
        )
        port map(
            i_clk              => i_clk,
            i_rstn             => i_rstn,
            i_aw_addr          => i_aw_addr,
            i_aw_prot          => i_aw_prot,
            i_aw_valid         => i_aw_valid,
            o_aw_ready         => o_aw_ready,
            i_w_data           => i_w_data,
            i_w_valid          => i_w_valid,
            o_w_ready          => o_w_ready,
            i_w_strobe         => i_w_strobe,
            o_b_resp           => o_b_resp,
            o_b_valid          => o_b_valid,
            i_b_ready          => i_b_ready,
            i_ar_addr          => i_ar_addr,
            i_ar_prot          => i_ar_prot,
            i_ar_valid         => i_ar_valid,
            o_ar_ready         => o_ar_ready,
            o_r_data           => o_r_data,
            o_r_resp           => o_r_resp,
            o_r_valid          => o_r_valid,
            i_r_ready          => i_r_ready,
            o_drv_read_addr    => s_drv_read_addr,
            i_drv_read_data    => s_drv_read_data,
            i_drv_read_result  => s_drv_read_result,
            o_drv_write_strobe => s_drv_write_strobe,
            o_drv_write_addr   => s_drv_write_addr,
            o_drv_write_data   => s_drv_write_data,
            i_drv_write_result => s_drv_write_result
        );
    
    proc_read_register : process(
        s_drv_read_addr, 
        i_adc_sConfigError, i_adc_sDataOverflow, i_adc_sInitDoneADC, i_adc_sInitDoneRelay, i_adc_sRstBusy, 
        s_reg_calib_ch1_add, s_reg_calib_ch1_mult, s_reg_calib_ch2_add, s_reg_calib_ch2_mult, s_reg_cr
    ) is
    begin
        case to_integer(s_drv_read_addr) is
            
            -- read to status register
            when C_OFFSET_REG_CR =>
                s_drv_read_result <= '1';
                s_drv_read_data <= ( 6 downto 0 => s_reg_cr ,others => '0');
                
            -- read to status register
            when C_OFFSET_REG_SR =>
                s_drv_read_result <= '1';
                
                s_drv_read_data <= (
                    0 => i_adc_sRstBusy, 
                    1 => i_adc_sInitDoneADC,
                    2 => i_adc_sInitDoneRelay,
                        
                    4 => i_adc_sConfigError,
                    5 => i_adc_sDataOverflow,
                    others => '0'
                );
                
            -- read from channel 1 calibration multiplier register
            when C_OFFSET_REG_CALIB1_MULT =>
                s_drv_read_result <= '1';
                s_drv_read_data <= (17 downto 0 => s_reg_calib_ch1_mult, others => '0');
            
            -- read from channel 1 calibration addition register
            when C_OFFSET_REG_CALIB1_ADD =>
                s_drv_read_result <= '1';
                s_drv_read_data <= (17 downto 0 => s_reg_calib_ch1_add, others => '0');
            
            -- read from channel 2 calibration multiplier register
            when C_OFFSET_REG_CALIB2_MULT =>
                s_drv_read_result <= '1';
                s_drv_read_data <= (17 downto 0 => s_reg_calib_ch2_mult, others => '0');
            
            -- read from channel 2 calibration addition register
            when C_OFFSET_REG_CALIB2_ADD =>
                s_drv_read_result <= '1';
                s_drv_read_data <= (17 downto 0 => s_reg_calib_ch2_add, others => '0');
            
            -- any other register failes read!
            when others =>
                s_drv_read_result <= '0';
                s_drv_read_data <= (others => '-');
        end case;
            
    end process proc_read_register;
    
    proc_write_register : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rstn = '0' then
                s_drv_write_result <= '0';
                
                s_reg_cr <= (others => '0');
                
                s_reg_calib_ch1_mult <= 18x"10000";
                s_reg_calib_ch1_add  <= 18x"00000";
                s_reg_calib_ch2_mult <= 18x"10000";
                s_reg_calib_ch2_add  <= 18x"00000";
                
            elsif s_drv_write_strobe = '1' then
                case to_integer(s_drv_write_addr) is
                    
                    -- write to control register
                    when C_OFFSET_REG_CR =>
                        s_drv_write_result <= '1';
                        
                        -- if the module is enabled, the we cannot write to the channel gain and coupling control bits
                        if s_drv_write_data(0) = '1' then
                            s_reg_cr(2 downto 0) <= s_drv_write_data(2 downto 0);
                        else
                            s_reg_cr <= s_drv_write_data(6 downto 0);
                        end if;
                     
                    -- write to channel 1 calibration multiplier register
                    when C_OFFSET_REG_CALIB1_MULT =>
                        s_drv_write_result <= '1';
                        s_reg_calib_ch1_mult <= s_drv_write_data(17 downto 0);
                      
                    -- write to channel 1 calibration addition register
                    when C_OFFSET_REG_CALIB1_ADD =>
                        s_drv_write_result <= '1';
                        s_reg_calib_ch1_add <= s_drv_write_data(17 downto 0);
                        
                    -- write to channel 2 calibration multplier register
                    when C_OFFSET_REG_CALIB2_MULT =>
                        s_drv_write_result <= '1';
                        s_reg_calib_ch2_mult <= s_drv_write_data(17 downto 0);
                    
                    -- write to channel 2 calibration addition register
                    when C_OFFSET_REG_CALIB2_ADD =>
                        s_drv_write_result <= '1';
                        s_reg_calib_ch2_add <= s_drv_write_data(17 downto 0);
                        
                    -- write to unknown registern
                    when others =>
                        s_drv_write_result <= '0';
                        
                end case;  
            end if;
        end if;
    end process proc_write_register;
    
    -- Assignment of external control signals for ADC from the register values
    
    o_adc_aRst_n             <= s_reg_cr(0);
    o_adc_sEnableAquisition  <= s_reg_cr(1);
    o_adc_sTestMode          <= s_reg_cr(2);
    o_adc_sCh1CouplingConfig <= s_reg_cr(3);
    o_adc_sCh1GainConfig     <= s_reg_cr(4);
    o_adc_sCh2CouplingConfig <= s_reg_cr(5);
    o_adc_sCh2GainConfig     <= s_reg_cr(6);

    o_adc_Ch1xxMultCoef <= s_reg_calib_ch1_mult;
    o_adc_Ch1xxAddCoef  <= s_reg_calib_ch1_add;
    o_adc_Ch2xxMultCoef <= s_reg_calib_ch2_mult;
    o_adc_Ch2xxAddCoef  <= s_reg_calib_ch2_add;

end architecture behav;