library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

entity rf_reciever_wrapper_2000 is
    generic(
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
        signal ACLK   : in std_logic;
        signal ARESETn : in std_logic;
        
        signal S00_AXIS_INPUT_TDATA  : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        signal S00_AXIS_INPUT_TVALID : in std_logic;
        signal S00_AXIS_INPUT_TREADY : out std_logic;
        
        signal M00_AXIS_OUTPUT_TDATA  : out std_logic_vector(G_DATA_WIDTH * 2 - 1 downto 0);
        signal M00_AXIS_OUTPUT_TVALID : out std_logic;
        signal M00_AXIS_OUTPUT_TREADY : in  std_logic;
        
        signal M01_AXIS_OUTPUT_TDATA  : out std_logic_vector(G_DATA_WIDTH * 2 - 1 downto 0);
        signal M01_AXIS_OUTPUT_TVALID : out std_logic;
        signal M01_AXIS_OUTPUT_TREADY : in  std_logic := '0';
        
        signal cfg_nco_frequency : in std_logic_vector(G_NCO_PHASE_WIDTH + G_NCO_PHASE_FRACTIONAL_BITS - 1 downto 0);
        
        signal cfg_phase_detector_enable : in std_logic;
        signal cfg_phase_detector_mode   : in std_logic;
        signal cfg_phase_detector_coef_A : in std_logic_vector(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS - 1 downto 0);
        signal cfg_phase_detector_coef_B : in std_logic_vector(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS - 1 downto 0);
        signal cfg_phase_detector_coef_C : in std_logic_vector(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS - 1 downto 0)
    );
end entity rf_reciever_wrapper_2000;

architecture inst of rf_reciever_wrapper_2000 is
begin

    inst_rf_reciever_wrapper : entity work.rf_reciever_wrapper_2008
        generic map(
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
            ACLK                      => ACLK,
            ARESETn                   => ARESETn,
            S00_AXIS_INPUT_TDATA      => S00_AXIS_INPUT_TDATA,
            S00_AXIS_INPUT_TVALID     => S00_AXIS_INPUT_TVALID,
            S00_AXIS_INPUT_TREADY     => S00_AXIS_INPUT_TREADY,
            
            M00_AXIS_OUTPUT_TDATA     => M00_AXIS_OUTPUT_TDATA,
            M00_AXIS_OUTPUT_TVALID    => M00_AXIS_OUTPUT_TVALID,
            M00_AXIS_OUTPUT_TREADY    => M00_AXIS_OUTPUT_TREADY,
            
            M01_AXIS_OUTPUT_TDATA     => M01_AXIS_OUTPUT_TDATA,
            M01_AXIS_OUTPUT_TVALID    => M01_AXIS_OUTPUT_TVALID,
            M01_AXIS_OUTPUT_TREADY    => M01_AXIS_OUTPUT_TREADY,
            
            cfg_nco_frequency         => cfg_nco_frequency,
            cfg_phase_detector_enable => cfg_phase_detector_enable,
            cfg_phase_detector_mode   => cfg_phase_detector_mode,
            cfg_phase_detector_coef_A => cfg_phase_detector_coef_A,
            cfg_phase_detector_coef_B => cfg_phase_detector_coef_B,
            cfg_phase_detector_coef_C => cfg_phase_detector_coef_C
        );
end architecture inst;
