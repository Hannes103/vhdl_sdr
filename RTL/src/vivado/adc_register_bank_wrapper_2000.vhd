library ieee;

use ieee.std_logic_1164.all;

entity adc_register_bank_wrapper_2000 is
    generic(
        C_S_AXI_ADDR_WIDTH : integer := 8
    );
    port(
        -- global AXI-Lite signals
        
        S_AXI_ACLK     : in std_logic;
        S_AXI_ARESET_N : in std_logic;
        
        -- AXI-Lite write address channel
        
        S_AXI_AWADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_AWPROT  : in std_logic_vector(2 downto 0);
        S_AXI_AWVALID : in std_logic;
        S_AXI_AWREADY : out std_logic;
        
        -- AXI-Lite write data channel
        
        S_AXI_WDATA  : in std_logic_vector(31 downto 0);
        S_AXI_WVALID : in std_logic;
        S_AXI_WREADY : out std_logic;
        S_AXI_WSTRB  : in std_logic_vector(3 downto 0);  
        
        -- AXI-Lite write response channel
        
        S_AXI_BRESP  : out std_logic_vector(1 downto 0);
        S_AXI_BVALID : out std_logic;
        S_AXI_BREADY : in std_logic;
        
        -- AXI-Lite read address channel
        
        S_AXI_ARADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_ARPROT  : in std_logic_vector(2 downto 0);
        S_AXI_ARVALID : in std_logic;
        S_AXI_ARREADY : out std_logic;
        
        -- AXI-Lite read response/data channel
        
        S_AXI_RDATA  : out std_logic_vector(31 downto 0);
        S_AXI_RRESP  : out std_logic_vector(1 downto 0);
        S_AXI_RVALID : out std_logic;
        S_AXI_RREADY : in std_logic;
        
        -- generic ADC control signals
        aRst_n : out std_logic;
        sTestMode : out std_logic;
        sEnableAquisition : out std_logic;
        
        -- generic ADC status signals
        sRstBusy : in std_logic;
        sInitDoneRelay : in std_logic;
        sInitDoneADC : in std_logic;
        sConfigError : in std_logic;
        sDataOverflow : in std_logic;
        
        -- ADC channel coupling control signals
        sCh1CouplingConfig : out std_logic;
        sCh2CouplingConfig : out std_logic;
        sCh1GainConfig : out std_logic;
        sCh2GainConfig : out std_logic;
        
        -- ADC calibration signals 
        Ch1xxMultCoef : out std_logic_vector(17 downto 0);
        Ch1xxAddCoef : out std_logic_vector(17 downto 0);
        Ch2xxMultCoef : out std_logic_vector(17 downto 0);
        Ch2xxAddCoef : out std_logic_vector(17 downto 0)      
    );
end entity adc_register_bank_wrapper_2000;

architecture inst of adc_register_bank_wrapper_2000 is
begin
    
    inst_adc_register_bank : entity work.adc_register_bank
        generic map(
            G_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
        )
        port map(
            i_clk                    => S_AXI_ACLK,
            i_rstn                   => S_AXI_ARESET_N,
            i_aw_addr                => S_AXI_AWADDR,
            i_aw_prot                => S_AXI_AWPROT,
            i_aw_valid               => S_AXI_AWVALID,
            o_aw_ready               => S_AXI_AWREADY,
            i_w_data                 => S_AXI_WDATA,
            i_w_valid                => S_AXI_WVALID,
            o_w_ready                => S_AXI_WREADY,
            i_w_strobe               => S_AXI_WSTRB,
            o_b_resp                 => S_AXI_BRESP,
            o_b_valid                => S_AXI_BVALID,
            i_b_ready                => S_AXI_BREADY,
            i_ar_addr                => S_AXI_ARADDR,
            i_ar_prot                => S_AXI_ARPROT,
            i_ar_valid               => S_AXI_ARVALID,
            o_ar_ready               => S_AXI_ARREADY,
            o_r_data                 => S_AXI_RDATA,
            o_r_resp                 => S_AXI_RRESP,
            o_r_valid                => S_AXI_RVALID,
            i_r_ready                => S_AXI_RREADY,
            
            o_adc_aRst_n             => aRst_n,
            o_adc_sTestMode          => sTestMode,
            o_adc_sEnableAquisition  => sEnableAquisition,
            
            i_adc_sRstBusy           => sRstBusy,
            i_adc_sInitDoneRelay     => sInitDoneRelay,
            i_adc_sInitDoneADC       => sInitDoneADC,
            i_adc_sConfigError       => sConfigError,
            i_adc_sDataOverflow      => sDataOverflow,
            
            o_adc_sCh1CouplingConfig => sCh1CouplingConfig,
            o_adc_sCh2CouplingConfig => sCh2CouplingConfig,
            o_adc_sCh1GainConfig     => sCh1GainConfig,
            o_adc_sCh2GainConfig     => sCh2GainConfig,
            
            o_adc_Ch1xxMultCoef      => Ch1xxMultCoef,
            o_adc_Ch1xxAddCoef       => Ch1xxAddCoef,
            o_adc_Ch2xxMultCoef      => Ch2xxMultCoef,
            o_adc_Ch2xxAddCoef       => Ch2xxAddCoef
        );
        
end architecture inst;