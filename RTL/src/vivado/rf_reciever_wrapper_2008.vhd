library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

entity rf_reciever_wrapper_2008 is
    generic(
        G_S01_AXI_ADDR_WIDTH : integer := 8;
        
        G_DATA_WIDTH : integer := 16;
        
        G_NCO_PHASE_WIDTH : integer := 10;
        G_NCO_PHASE_FRACTIONAL_BITS : integer := 11;
        
        G_CIC_ORDER : integer := 4;
        G_CIC_DECIMATION : integer range 8 to 32 := 8;
        
        G_PHASE_DETECTOR_COEF_WIDTH : integer := 8;
        G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS : integer := 10;
        
        G_HAS_SECOND_OUTPUT : boolean := false
    );
    
    port(
        -- global signals
        
        ACLK   : in std_logic;
        ARESETn : in std_logic;
        
        -- AXI-Stream input signals
        
        S00_AXIS_INPUT_TDATA  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        S00_AXIS_INPUT_TVALID : in std_logic;
        S00_AXIS_INPUT_TREADY : out std_logic;
        
        -- primary AXI-Stream output signals
        
        M00_AXIS_OUTPUT_TDATA  : out std_logic_vector(G_DATA_WIDTH * 2 - 1 downto 0);
        M00_AXIS_OUTPUT_TVALID : out std_logic;
        M00_AXIS_OUTPUT_TREADY : in  std_logic;
        
        -- seconary AXI-Stream output signals
        
        M01_AXIS_OUTPUT_TDATA  : out std_logic_vector(G_DATA_WIDTH * 2 - 1 downto 0);
        M01_AXIS_OUTPUT_TVALID : out std_logic;
        M01_AXIS_OUTPUT_TREADY : in  std_logic := '0';
        
        -- AXI-Lite write address channel
        
        S01_AXI_AWADDR  : in std_logic_vector(G_S01_AXI_ADDR_WIDTH - 1 downto 0);
        S01_AXI_AWPROT  : in std_logic_vector(2 downto 0);
        S01_AXI_AWVALID : in std_logic;
        S01_AXI_AWREADY : out std_logic;
        
        -- AXI-Lite write data channel
        
        S01_AXI_WDATA  : in std_logic_vector(31 downto 0);
        S01_AXI_WVALID : in std_logic;
        S01_AXI_WREADY : out std_logic;
        S01_AXI_WSTRB  : in std_logic_vector(3 downto 0);  
        
        -- AXI-Lite write response channel
        
        S01_AXI_BRESP  : out std_logic_vector(1 downto 0);
        S01_AXI_BVALID : out std_logic;
        S01_AXI_BREADY : in std_logic;
        
        -- AXI-Lite read address channel
        
        S01_AXI_ARADDR  : in std_logic_vector(G_S01_AXI_ADDR_WIDTH - 1 downto 0);
        S01_AXI_ARPROT  : in std_logic_vector(2 downto 0);
        S01_AXI_ARVALID : in std_logic;
        S01_AXI_ARREADY : out std_logic;
        
        -- AXI-Lite read response/data channel
        
        S01_AXI_RDATA  : out std_logic_vector(31 downto 0);
        S01_AXI_RRESP  : out std_logic_vector(1 downto 0);
        S01_AXI_RVALID : out std_logic;
        S01_AXI_RREADY : in std_logic
    );
end entity rf_reciever_wrapper_2008;

architecture inst of rf_reciever_wrapper_2008 is
    signal s_rst : std_logic;
   
    -- Input conversion signals
    
    signal s_input : signed(G_DATA_WIDTH - 1 downto 0);
    
    -- Output conversion signals
   
    signal s_output_0_i : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_output_0_q : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_output_1_i : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_output_1_q : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    -- Configuration signals
    
    signal s_cfg_nco_frequency          : sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_enable  : std_logic;
    signal s_cfg_phase_detector_mode    : std_logic;
    signal s_cfg_phase_detector_coef_A  : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_B  : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_C  : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_threshold : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_mon_phase_detector_nco_adj : sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);

begin

    s_rst <= not ARESETn;

    -- Input conversion assignments
    s_input <= signed(S00_AXIS_INPUT_TDATA);

    -- Output conversion assignments
    M00_AXIS_OUTPUT_TDATA <= to_slv(s_output_0_q) & to_slv(s_output_0_i);
    M01_AXIS_OUTPUT_TDATA <= to_slv(s_output_1_q) & to_slv(s_output_1_i);
    
    inst_rf_reciever : entity work.rf_reciever
        generic map(
            G_DATA_WIDTH                          => G_DATA_WIDTH,
            G_ROUNDING_MODE                       => FIXED_TRUNCATE,
            G_NCO_PHASE_WIDTH                     => G_NCO_PHASE_WIDTH,
            G_NCO_PHASE_FRACTIONAL_BITS           => G_NCO_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                           => G_CIC_ORDER,
            G_CIC_DECIMATION                      => G_CIC_DECIMATION,
            G_PHASE_DETECTOR_COEF_WIDTH           => G_PHASE_DETECTOR_COEF_WIDTH,
            G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS => G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS,
            G_HAS_SECOND_OUTPUT                   => G_HAS_SECOND_OUTPUT
        )
        port map(
            i_clk                       => ACLK,
            i_rst                       => s_rst,
            
            i_input                     => s_input,
            i_input_valid               => S00_AXIS_INPUT_TVALID,
            o_input_ready               => S00_AXIS_INPUT_TREADY,
            
            o_output_0_i                => s_output_0_i,
            o_output_0_q                => s_output_0_q,
            o_output_0_valid            => M00_AXIS_OUTPUT_TVALID,
            i_output_0_ready            => M00_AXIS_OUTPUT_TREADY,
            
            o_output_1_i                => s_output_1_i,
            o_output_1_q                => s_output_1_q,
            o_output_1_valid            => M01_AXIS_OUTPUT_TVALID,
            i_output_1_ready            => M01_AXIS_OUTPUT_TREADY,
            
            i_cfg_nco_frequency         => s_cfg_nco_frequency,
            
            i_cfg_phase_detector_enable => s_cfg_phase_detector_enable,
            i_cfg_phase_detector_mode   => s_cfg_phase_detector_mode,
            i_cfg_phase_detector_coef_A => s_cfg_phase_detector_coef_A,
            i_cfg_phase_detector_coef_B => s_cfg_phase_detector_coef_B,
            i_cfg_phase_detector_coef_C => s_cfg_phase_detector_coef_C,
            i_cfg_phase_detector_threshold => s_cfg_phase_detector_threshold,
            
            o_mon_phase_detector_nco_adj => s_mon_phase_detector_nco_adj
        );
    
    inst_rf_reciever_register_bank : entity work.rf_reciever_register_bank
        generic map(
            G_ADDR_WIDTH                          => G_S01_AXI_ADDR_WIDTH,
            G_DATA_WIDTH                          => G_DATA_WIDTH,
            G_NCO_PHASE_WIDTH                     => G_NCO_PHASE_WIDTH,
            G_NCO_PHASE_FRACTIONAL_BITS           => G_NCO_PHASE_FRACTIONAL_BITS,
            G_PHASE_DETECTOR_COEF_WIDTH           => G_PHASE_DETECTOR_COEF_WIDTH,
            G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS => G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS
        )
        port map(
            i_clk                    => ACLK,
            i_rstn                   => ARESETn,
            i_aw_addr                => S01_AXI_AWADDR,
            i_aw_prot                => S01_AXI_AWPROT,
            i_aw_valid               => S01_AXI_AWVALID,
            o_aw_ready               => S01_AXI_AWREADY,
            i_w_data                 => S01_AXI_WDATA,
            i_w_valid                => S01_AXI_WVALID,
            o_w_ready                => S01_AXI_WREADY,
            i_w_strobe               => S01_AXI_WSTRB,
            o_b_resp                 => S01_AXI_BRESP,
            o_b_valid                => S01_AXI_BVALID,
            i_b_ready                => S01_AXI_BREADY,
            i_ar_addr                => S01_AXI_ARADDR,
            i_ar_prot                => S01_AXI_ARPROT,
            i_ar_valid               => S01_AXI_ARVALID,
            o_ar_ready               => S01_AXI_ARREADY,
            o_r_data                 => S01_AXI_RDATA,
            o_r_resp                 => S01_AXI_RRESP,
            o_r_valid                => S01_AXI_RVALID,
            i_r_ready                => S01_AXI_RREADY,
            
            o_cfg_nco_frequency          => s_cfg_nco_frequency,
            o_cfg_phase_detector_enable  => s_cfg_phase_detector_enable,
            o_cfg_phase_detector_mode    => s_cfg_phase_detector_mode,
            o_cfg_phase_detector_coef_A  => s_cfg_phase_detector_coef_A,
            o_cfg_phase_detector_coef_B  => s_cfg_phase_detector_coef_B,
            o_cfg_phase_detector_coef_C  => s_cfg_phase_detector_coef_C,
            o_cfg_phase_detector_threshold => s_cfg_phase_detector_threshold,
            i_mon_phase_detector_nco_adj => s_mon_phase_detector_nco_adj
        );
end architecture inst;
