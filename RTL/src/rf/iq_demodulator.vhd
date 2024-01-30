library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

use work.iq_demodulator_pkg.all;

entity iq_demodulator is
    
    generic(
        -- Specifies the number of bits in the input signal.
        -- The input signal is signed so this number includes the sign bit.
        --
        -- Will also be used as the width of the output integer part.
        G_DATA_WIDTH             : integer := 16;
        
        -- Specifies the number of bits in the fractional part of the output I and Q signals.
        -- 
        -- Additional fractional bits can be produced via the CIC decimation performed after the mixing if required.
        -- Up to floor( log2( G_CIC_DECIMATION) ) bits can be output after filtering.
        --
        -- By default the output signal is integer only.
        G_OUTPUT_FRACTIONAL_BITS : integer := 0;
        
        -- Specifies the number of bits in the integer part of the phase accumulator used by the NCO.
        -- See: dds_generator.vhd for more information.
        G_CARRIER_PHASE_WIDTH           : integer := 10;
        
        -- Speciifes the number of bits in the fractional part of the phase accumulator used by the NCO.
        -- See: dds_generator.vhd for more information.
        G_CARRIER_PHASE_FRACTIONAL_BITS : integer := 11;
        
        -- Specifies the filter order of the CIC lowpass decimation filters used after mixing.
        -- 
        -- Filter order has a strong impact on the primary lobe stepness of the CIC filter.
        -- An additional parameter to considere when choosing the filder order is the decimation factor and required output signal bandwidth.
        G_CIC_ORDER      : integer := 4;
        
        -- Specifies the number of independent AXI stream interface avaliable to output the complex data samples.
        -- All output interfaces are arrays with indices from 0 to G_OUTPUT_COUT being valid.
        G_OUTPUT_COUNT : integer range 1 to 8 := 1;
        
        -- Specifies the decimation factor used by the CIC decimation filters.
        --
        -- The output data stream of this demodulator will be one over G_CIC_DECIMATION of the input data stream.
        -- The decimation factor must be least equal to the filter order and must be a power of two.
        G_CIC_DECIMATION : integer := 8;
        
        -- Specifies the rounding mode used to truncate the mixing results after multiplication with the carrier.
        -- By default the standard fixed point rounding style will be used.
        -- To increase module performance (at the cost of some additional quantization noise) the rounding mode can be changed to truncation. 
        G_ROUNDING_MODE : fixed_round_style_type := FIXED_ROUND_STYLE
    );
    
    port(
        -- Synchronous clock input signal.
        signal i_clk : in std_logic;
        
        -- Synchronous active high reset signal.
        signal i_rst : in std_logic;
    
        -- Phase increment control word, used to control the frequency of the internal NCO used for carrier generation.
        -- Will be latched whenever the i_cfg_phase_step_valid flag is high.
        --
        -- For more information see: dds_generator.vhd
        signal i_cfg_phase_step : in std_logic_vector(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
        
        -- Phase increment control word valid signal.
        -- The phase increment word will be loaded on every clock cycle this signal is high.
        -- 
        -- This signal is optional and if left unconnected the phase step will be loaded on every clock cycle.
        signal i_cfg_phase_step_valid : in std_logic := '1';

        signal i_input       : in signed(G_DATA_WIDTH - 1 downto 0);
        signal o_input_ready : out std_logic;
        signal i_input_valid : in std_logic;
        
        signal o_output_i : out t_sfixed_array(G_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
        signal o_output_q : out t_sfixed_array(G_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
        signal i_output_ready : in std_logic_vector(G_OUTPUT_COUNT - 1 downto 0);
        signal o_output_valid : out std_logic_vector(G_OUTPUT_COUNT - 1 downto 0)
    );
    
end entity iq_demodulator;

architecture behav of iq_demodulator is
    
    -- Signals: input data
    
    signal s_input_ready : std_logic;
    signal s_raw_data : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_raw_data_valid : std_logic_vector(2 downto 0);
    
    -- Signals: carrier waveforms
    
    signal s_carrier_cos : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal s_carrier_cos_reg : sfixed(1 downto -G_DATA_WIDTH + 2);
    
    signal s_carrier_sin : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal s_carrier_sin_reg : sfixed(1 downto -G_DATA_WIDTH + 2);
    
    -- Signals for I-data path.
    
    signal s_raw_data_i_M : sfixed(G_DATA_WIDTH + 1 downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_i : sfixed(G_DATA_WIDTH + 1 downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_i_fixed : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    signal s_filtered_data_i : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_filtered_data_i_valid : std_logic;
    
    -- Signals for Q-data path.
    
    signal s_raw_data_q_M : sfixed((G_DATA_WIDTH + 1) downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_q : sfixed((G_DATA_WIDTH + 1) downto (-G_DATA_WIDTH) + 2);
    signal s_raw_data_q_fixed : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    signal s_filtered_data_q : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_filtered_data_q_valid : std_logic;
    
    -- Signals for output
    
    signal s_output_available : std_logic_vector(G_OUTPUT_COUNT - 1 downto 0);
    signal s_output_i         : t_sfixed_array(G_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_output_q         : t_sfixed_array(G_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_output_i_temp    : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_output_q_temp    : sfixed(G_DATA_WIDTH - 1 downto -G_OUTPUT_FRACTIONAL_BITS);
    signal s_output_valid     : std_logic_vector(G_OUTPUT_COUNT - 1 downto 0);
    
begin
    
    -- Local oszillator used for I/Q mixing.
    -- Implemeted as a direct digital synthesis sin/cos oszillator.
    -- Interpolation setting and output control flags are fixed, everything else can be configured by the top level module.
    inst_DDS : entity work.dds_generator
        generic map(
            G_PHASE_WIDTH           => G_CARRIER_PHASE_WIDTH,
            G_PHASE_FRACTIONAL_BITS => G_CARRIER_PHASE_FRACTIONAL_BITS,
            G_SIGNAL_WIDTH          => G_DATA_WIDTH,
            G_ENABLE_INTERPOLATION  => false,
            G_INVERT_OUTPUT         => true,
            G_ENABLE_SHIFTED_OUTPUT => true,
            G_INVERT_SHIFTED_OUTPUT => false
        )
        port map(
            i_clk              => i_clk,
            i_clk_en           => '1',
            i_rst              => i_rst,
            i_phase_step       => i_cfg_phase_step,
            i_phase_step_valid => i_cfg_phase_step_valid,
            o_output           => s_carrier_sin,
            o_output_shifted   => s_carrier_cos
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
                s_input_ready <= '0';
                
                s_raw_data <= to_sfixed(0, s_raw_data);
                
                s_carrier_cos_reg <= to_sfixed(0, s_carrier_cos_reg);
                s_carrier_sin_reg <= to_sfixed(0, s_carrier_sin_reg);
                
                s_raw_data_i_M <= to_sfixed(0, s_raw_data_i_M);
                s_raw_data_q_M <= to_sfixed(0, s_raw_data_q_M);
                
                s_raw_data_i <= to_sfixed(0, s_raw_data_i);
                s_raw_data_q <= to_sfixed(0, s_raw_data_q);
                
                s_raw_data_valid <= (others => '0');
                
            else
                -- we are always ready to accept new data, unless we are under reset
                s_input_ready <= '1';
                
                -- our multiplier has three pipeline stages, so we need to delay the input valid signal for CIC filters
                -- by 3 clock cycles.
                s_raw_data_valid(0) <= i_input_valid;
                s_raw_data_valid(1) <= s_raw_data_valid(0);
                s_raw_data_valid(2) <= s_raw_data_valid(1);
                
                -- A three stage pipeline model is used to allow a DSP slice to be infered for maximum performance
                -- More information about the recommended design guidlines for DSP slices see: UG479
                
                -- First step is to latch all multiplicants into the input registers
                -- This includes the input data and reference oszillators
                s_raw_data <= to_sfixed(i_input);
                
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
    
    -- This process manages the AXI stream outputs of the demodulator.
    -- Multiple concurrent and independent outputs are supported that will each get a new sample once avaliable from the CIC filters.
    --
    -- The output data interface is AXI stream with supported back pressure.
    -- There is however no FIFO implemented, but because of the decimation rate of the CIC filters there should be enough clock cycles avaliable to 
    -- allow each slave to fully consume the output
    proc_output : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                s_output_valid <= (others => '0');
                
                s_output_i <= (others => to_sfixed(0, s_output_i(0)));
                s_output_q <= (others => to_sfixed(0, s_output_q(0)));

                s_output_i_temp <= to_sfixed(0, s_output_i_temp);                
                s_output_q_temp <= to_sfixed(0, s_output_q_temp);
                
                s_output_available <= (others => '0');
            else
                
                -- we support multiple (optional) outputs that are independent of each other.
                for i in G_OUTPUT_COUNT - 1 downto 0 loop
                    -- we do not have a valid output and we have new outputs
                    if s_output_valid(i) = '0' and s_output_available(i) = '1' then
                        -- so present new output and set the valid flag
                        s_output_i(i) <= s_output_i_temp;
                        s_output_q(i) <= s_output_q_temp;
                        
                        s_output_valid(i) <= '1';
                        
                        -- no longer new output avaliable
                        s_output_available(i) <= '0';
                    elsif s_output_valid(i) = '1' and i_output_ready(i) = '1' then
                        -- data has been transfered fully
                        s_output_valid(i) <= '0';
                    end if;
                end loop;
        
                -- latch both filter outputs while they are valid
                -- we cannot wait to do that because the will changer right after the valid strobe
                -- this is common for all outputs.
                if s_filtered_data_i_valid = '1' then
                    s_output_i_temp <= s_filtered_data_i;
                    -- all configured outputs have new data now
                    s_output_available <= (others => '1');
                end if;
                
                if s_filtered_data_q_valid = '1' then
                    s_output_available <= (others => '1');
                    -- all configured output shave new data now
                    s_output_q_temp <= s_filtered_data_q;
                end if;
                
            end if;
        end if;
    end process proc_output;
    
    -- signal for AXIS input interface
    o_input_ready <= s_input_ready;
    
    -- assign temporary variables used as input for CIC decimators
    s_raw_data_i_fixed <= resize(s_raw_data_i, s_raw_data_i_fixed, FIXED_OVERFLOW_STYLE, G_ROUNDING_MODE);
    s_raw_data_q_fixed <= resize(s_raw_data_q, s_raw_data_q_fixed, FIXED_OVERFLOW_STYLE, G_ROUNDING_MODE);

    -- assign output AXIS interface
    o_output_i     <= s_output_i;
    o_output_q     <= s_output_q;
    o_output_valid <= s_output_valid;

end architecture behav;