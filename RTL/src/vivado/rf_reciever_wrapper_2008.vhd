library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

entity rf_reciever_wrapper_2008 is
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
    
    -- Configuration signal conversion signals
    
    signal s_cfg_nco_frequency         : sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_A : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_B : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_cfg_phase_detector_coef_C : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);

begin

    s_rst <= not ARESETn;

    -- Input conversion assignments
    s_input <= signed(S00_AXIS_INPUT_TDATA);

    -- Output conversion assignments
    M00_AXIS_OUTPUT_TDATA <= to_slv(s_output_0_q) & to_slv(s_output_0_i);
    M01_AXIS_OUTPUT_TDATA <= to_slv(s_output_1_q) & to_slv(s_output_1_i);

    -- Configuration conversion assigments
    s_cfg_nco_frequency <= to_sfixed(cfg_nco_frequency, s_cfg_nco_frequency);
    s_cfg_phase_detector_coef_A <= to_sfixed(cfg_phase_detector_coef_A, s_cfg_phase_detector_coef_A);
    s_cfg_phase_detector_coef_B <= to_sfixed(cfg_phase_detector_coef_B, s_cfg_phase_detector_coef_B);
    s_cfg_phase_detector_coef_C <= to_sfixed(cfg_phase_detector_coef_C, s_cfg_phase_detector_coef_C);
    
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
            
            i_cfg_phase_detector_enable => cfg_phase_detector_enable,
            i_cfg_phase_detector_mode   => cfg_phase_detector_mode,
            i_cfg_phase_detector_coef_A => s_cfg_phase_detector_coef_A,
            i_cfg_phase_detector_coef_B => s_cfg_phase_detector_coef_B,
            i_cfg_phase_detector_coef_C => s_cfg_phase_detector_coef_C
        );
    

end architecture inst;
