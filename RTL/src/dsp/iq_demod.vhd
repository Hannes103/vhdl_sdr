library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;

entity iq_demod is
    
    generic(
        G_DATA_WIDTH : integer := 16;
        G_OUTPUT_FRACTIONAL_BITS : integer := 0;
        
        G_CARRIER_PHASE_WIDTH : integer := 11;
        G_CARRIER_PHASE_FRACTIONAL_BITS : integer := 10;
        
        G_CIC_ORDER : integer := 0;
        G_CIC_DECIMATION : integer := 8
    );
    
    port(
        signal i_clk : in std_logic;
        signal i_rst : in std_logic;
    
        signal i_phase_step : in std_logic_vector(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);

        signal i_data : in signed(G_DATA_WIDTH - 1 downto 0);
        signal i_data_valid : in std_logic;
        
        signal o_data_i : out sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
        signal o_data_q : out sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
        signal o_data_valid : out std_logic
    );
    
end entity iq_demod;

architecture behav of iq_demod is
    signal s_carrier_cos : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal s_carrier_cos_reg : sfixed(1 downto -G_DATA_WIDTH + 2);
    
    signal s_carrier_sin : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal s_carrier_sin_reg : sfixed(1 downto -G_DATA_WIDTH + 2);
    
    signal s_raw_data : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_raw_data_valid : std_logic_vector(2 downto 0);
    
    signal s_raw_data_i_M : sfixed(G_DATA_WIDTH + 1 downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_i   : sfixed(G_DATA_WIDTH + 1 downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_i_fixed : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    signal s_filtered_data_i : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_filtered_data_i_valid : std_logic;
    
    signal s_raw_data_q_M : sfixed((G_DATA_WIDTH + 1) downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_q   : sfixed((G_DATA_WIDTH + 1) downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_q_fixed : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    signal s_filtered_data_q : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_filtered_data_q_valid : std_logic;
begin
    
    -- Local oszillator used for I/Q mixing.
    -- Implemeted as a direct digital synthesis sin/cos oszillator.
    -- Interpolation setting and output control flags are fixed, everything else can be configured by the top level module.
    inst_DDS : entity work.dds_generator
        generic map(
            G_PHASE_WIDTH           => G_CARRIER_PHASE_WIDTH,
            G_PHASE_FRACTIONAL_BITS => G_CARRIER_PHASE_FRACTIONAL_BITS,
            G_SIGNAL_WIDTH          => G_DATA_WIDTH,
            G_ENABLE_INTERPOLATION  => true,
            G_INVERT_OUTPUT         => true,
            G_ENABLE_SHIFTED_OUTPUT => true,
            G_INVERT_SHIFTED_OUTPUT => false
        )
        port map(
            i_clk            => i_clk,
            i_clk_en         => '1',
            i_rst            => i_rst,
            i_phase_step     => i_phase_step,
            o_output         => s_carrier_sin,
            o_output_shifted => s_carrier_cos
        );
    
    -- CIC decimator for I data path
    inst_CIC_data_I : entity work.cic_decimator
        generic map(
            G_ORDER                  => G_CIC_ORDER,
            G_DECIMATION             => G_CIC_DECIMATION,
            G_INPUT_WIDTH            => G_DATA_WIDTH,
            G_INPUT_FRACTIONAL_BITS  => 0,
            G_OUTPUT_FRACTIONAL_BITS => G_OUTPUT_FRACTIONAL_BITS
        )
        port map(
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_input        => s_raw_data_i_fixed,
            i_input_valid  => s_raw_data_valid(2),
            o_output       => s_filtered_data_i,
            o_output_valid => s_filtered_data_i_valid
        );
    
    -- CIC decimator for the Q data path
    inst_CIC_data_Q : entity work.cic_decimator
        generic map(
            G_ORDER                  => G_CIC_ORDER,
            G_DECIMATION             => G_CIC_DECIMATION,
            G_INPUT_WIDTH            => G_DATA_WIDTH,
            G_INPUT_FRACTIONAL_BITS  => 0,
            G_OUTPUT_FRACTIONAL_BITS => G_OUTPUT_FRACTIONAL_BITS
        )
        port map(
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_input        => s_raw_data_q_fixed,
            i_input_valid  => s_raw_data_valid(2),
            o_output       => s_filtered_data_q,
            o_output_valid => s_filtered_data_q_valid
        );
        
    -- This process implements the two multipliers that mix the local oszillator with the input data signal.
    -- It follows the xilinx design recommendations for DSP slices.
    --
    -- It calculates:
    --   s_raw_data_i = i_data * s_carrier_cos
    --   s_raw_data_q = i_data * s_carrier_sin
    proc_mult : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            -- synchronous reset for all internal and DSP registers
            if i_rst = '1' then
                s_raw_data <= to_sfixed(0, s_raw_data);
                
                s_carrier_cos_reg <= to_sfixed(0, s_carrier_cos_reg);
                s_carrier_sin_reg <= to_sfixed(0, s_carrier_sin_reg);
                
                s_raw_data_i_M <= to_sfixed(0, s_raw_data_i_M);
                s_raw_data_q_M <= to_sfixed(0, s_raw_data_q_M);
                
                s_raw_data_i <= to_sfixed(0, s_raw_data_i);
                s_raw_data_q <= to_sfixed(0, s_raw_data_q);
                
                s_raw_data_valid <= (others => '0');
                
            else
                -- our multiplier has three pipeline stages, so we need to delay the input valid signal for CIC filters
                -- by 3 clock cycles.
                s_raw_data_valid(0) <= i_data_valid;
                s_raw_data_valid(1) <= s_raw_data_valid(0);
                s_raw_data_valid(2) <= s_raw_data_valid(1);
                
                -- A three stage pipeline model is used to allow a DSP slice to be infered for maximum performance
                -- More information about the recommended design guidlines for DSP slices see: UG479
                
                -- First step is to latch all multiplicants into the input registers
                -- This includes the input data and reference oszillators
                s_raw_data <= to_sfixed(i_data);
                
                s_carrier_cos_reg <= to_sfixed(s_carrier_cos, s_carrier_cos_reg);
                s_carrier_sin_reg <= to_sfixed(s_carrier_sin, s_carrier_sin_reg);
                
                -- second step is to perform the multiplication
                s_raw_data_i_M <= s_raw_data * s_carrier_cos_reg;
                s_raw_data_q_M <= s_raw_data * s_carrier_sin_reg;
                
                -- third step is to copy the multiplication result to the output register
                -- this is done because xilinx DSP slices do not allow the accumulator to be bypassed 
                s_raw_data_i <= s_raw_data_i_M;
                s_raw_data_q <= s_raw_data_q_M;
            end if;
        end if;
    end process proc_mult;
    
    -- assign temporary variables used as input for CIC decimators
    s_raw_data_i_fixed <= resize(s_raw_data_i, s_raw_data_i_fixed);
    s_raw_data_q_fixed <= resize(s_raw_data_q, s_raw_data_q_fixed);

    -- assign outputs
    o_data_i <= s_filtered_data_i;
    o_data_q <= s_filtered_data_q;
    
    -- Because we know that the CIC decimators are synchronized, we can use either one of the two data valid
    -- signals of both. We use both just for safety.
    o_data_valid <= s_filtered_data_i_valid and s_filtered_data_q_valid;

end architecture behav;