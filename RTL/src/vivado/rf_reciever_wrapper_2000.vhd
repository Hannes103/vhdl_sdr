library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

entity rf_reciever_wrapper_2000 is
    generic(
        G_S01_AXI_ADDR_WIDTH : integer;
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
end entity rf_reciever_wrapper_2000;

architecture inst of rf_reciever_wrapper_2000 is
begin

    inst_rf_reciever_wrapper : entity work.rf_reciever_wrapper_2008
        generic map(
            G_S01_AXI_ADDR_WIDTH                  => G_S01_AXI_ADDR_WIDTH,
            G_DATA_WIDTH                          => G_DATA_WIDTH,
            G_NCO_PHASE_WIDTH                     => G_NCO_PHASE_WIDTH,
            G_NCO_PHASE_FRACTIONAL_BITS           => G_NCO_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                           => G_CIC_ORDER,
            G_CIC_DECIMATION                      => G_CIC_DECIMATION,
            G_PHASE_DETECTOR_COEF_WIDTH           => G_PHASE_DETECTOR_COEF_WIDTH,
            G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS => G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS,
            G_HAS_SECOND_OUTPUT                   => G_HAS_SECOND_OUTPUT
        )
        port map(
            ACLK                   => ACLK,
            ARESETn                => ARESETn,
            S00_AXIS_INPUT_TDATA   => S00_AXIS_INPUT_TDATA,
            S00_AXIS_INPUT_TVALID  => S00_AXIS_INPUT_TVALID,
            S00_AXIS_INPUT_TREADY  => S00_AXIS_INPUT_TREADY,
            M00_AXIS_OUTPUT_TDATA  => M00_AXIS_OUTPUT_TDATA,
            M00_AXIS_OUTPUT_TVALID => M00_AXIS_OUTPUT_TVALID,
            M00_AXIS_OUTPUT_TREADY => M00_AXIS_OUTPUT_TREADY,
            M01_AXIS_OUTPUT_TDATA  => M01_AXIS_OUTPUT_TDATA,
            M01_AXIS_OUTPUT_TVALID => M01_AXIS_OUTPUT_TVALID,
            M01_AXIS_OUTPUT_TREADY => M01_AXIS_OUTPUT_TREADY,
            S01_AXI_AWADDR         => S01_AXI_AWADDR,
            S01_AXI_AWPROT         => S01_AXI_AWPROT,
            S01_AXI_AWVALID        => S01_AXI_AWVALID,
            S01_AXI_AWREADY        => S01_AXI_AWREADY,
            S01_AXI_WDATA          => S01_AXI_WDATA,
            S01_AXI_WVALID         => S01_AXI_WVALID,
            S01_AXI_WREADY         => S01_AXI_WREADY,
            S01_AXI_WSTRB          => S01_AXI_WSTRB,
            S01_AXI_BRESP          => S01_AXI_BRESP,
            S01_AXI_BVALID         => S01_AXI_BVALID,
            S01_AXI_BREADY         => S01_AXI_BREADY,
            S01_AXI_ARADDR         => S01_AXI_ARADDR,
            S01_AXI_ARPROT         => S01_AXI_ARPROT,
            S01_AXI_ARVALID        => S01_AXI_ARVALID,
            S01_AXI_ARREADY        => S01_AXI_ARREADY,
            S01_AXI_RDATA          => S01_AXI_RDATA,
            S01_AXI_RRESP          => S01_AXI_RRESP,
            S01_AXI_RVALID         => S01_AXI_RVALID,
            S01_AXI_RREADY         => S01_AXI_RREADY
        );
end architecture inst;
