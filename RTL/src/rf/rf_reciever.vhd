library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;
use ieee.math_real.all;

use work.iq_demodulator_pkg.all;

use work.generic_pkg.all;

entity rf_reciever is
    generic(
        G_DATA_WIDTH : integer := 16;
        
        G_ROUNDING_MODE : fixed_round_style_type := FIXED_TRUNCATE;
        
        G_NCO_PHASE_WIDTH : integer := 10;
        G_NCO_PHASE_FRACTIONAL_BITS : integer := 11;
        
        G_CIC_ORDER : integer := 4;
        G_CIC_DECIMATION : integer range 8 to 32 := 8;
        
        G_PHASE_DETECTOR_COEF_WIDTH : integer := 8;
        G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS : integer := 10;
        
        G_PHASE_DETECTOR_GAIN_DIV : integer range 1 to 32 := 4;
        
        G_HAS_SECOND_OUTPUT : boolean := false
    );
    
    port(
        -- Synchronous input clock.
        i_clk : in std_logic;
        
        -- Sychrnonous active high reset signal.
        i_rst : in std_logic;
        
        -- TDATA of AXI-Stream input for raw ADC samples that should be proceessed.
        --
        -- Input will be mixed with the internally generated carriers signals to produce the I/Q outputs.
        -- See: iq_demodulator.vhd for more information.
        i_input : in signed(G_DATA_WIDTH - 1 downto 0);
        
        -- TVALID of AXI-Stream input for raw ADC samples.
        i_input_valid : in std_logic;
        
        -- TREADY of AXI-Stram input for raw ADC samples.
        o_input_ready : out std_logic;
        
        o_output_0_i : out sfixed(G_DATA_WIDTH - 1 downto 0);
        o_output_0_q : out sfixed(G_DATA_WIDTH - 1 downto 0);
        o_output_0_valid : out std_logic;
        i_output_0_ready : in std_logic;
        
        o_output_1_i : out sfixed(G_DATA_WIDTH - 1 downto 0);
        o_output_1_q : out sfixed(G_DATA_WIDTH - 1 downto 0);
        o_output_1_valid : out std_logic ;
        i_output_1_ready : in std_logic := '0';
        
        i_cfg_nco_frequency : in sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
        
        i_cfg_phase_detector_enable : in std_logic;
        i_cfg_phase_detector_mode : in std_logic;
        
        i_cfg_phase_detector_coef_A : in sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        i_cfg_phase_detector_coef_B : in sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        i_cfg_phase_detector_coef_C : in sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        i_cfg_phase_detector_threshold : in sfixed(G_DATA_WIDTH - 1 downto 0);
        
        o_mon_phase_detector_nco_adj : out sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS)
    );
end entity rf_reciever;

architecture inst of rf_reciever is
    constant C_PHASE_CONTROLER_SHIFT : integer := integer(log2(real(G_PHASE_DETECTOR_GAIN_DIV)));
    
    -- Specifies the number of outputs that the I/Q demodulator should provide.
    -- The following outputs will be used:
    --   [0] (always  ) => Phase detector for internal frequency tracking loop.
    --   [1] (always  ) => primary external I/Q output (#0)
    --   [2] (optional) => seconary external I/Q output (#1)
    constant C_DEMOD_OUTPUT_COUNT : integer := ReturnIf(G_HAS_SECOND_OUTPUT, 3, 2);
    
    -- Signals for I/Q data distribution
    signal s_data_i : t_sfixed_array(C_DEMOD_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto 0);
    signal s_data_q : t_sfixed_array(C_DEMOD_OUTPUT_COUNT - 1 downto 0)(G_DATA_WIDTH - 1 downto 0);
    signal s_data_ready : std_logic_vector(C_DEMOD_OUTPUT_COUNT - 1 downto 0);
    signal s_data_valid : std_logic_vector(C_DEMOD_OUTPUT_COUNT - 1 downto 0);
    
    -- Signals for phase detector loop:
    signal s_phase_error : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_phase_error_valid : std_logic;
    signal s_phase_error_ready : std_logic;
    
    signal s_phase_controller_output : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_phase_controller_output_strobe : std_logic;
    
    signal s_cfg_nco_frequency : sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
    signal s_cfg_phase_step    : std_logic_vector(G_NCO_PHASE_WIDTH + G_NCO_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    signal s_phase_detector_threshold : sfixed(G_DATA_WIDTH - 1 downto 0);
    signal s_phase_detector_enable_controller : std_logic;
    
begin

    -- Verify that the provided decimation factor is a power of two.
    -- This is required so that we do not need a division for the correct scaling of the output.
    -- NOTE: There may be some IEEE-754 wierdness going on here so we do not check for equality but whether the difference is smaller
    --       than achiveable with G_DECIMATION being integer
    assert abs(round(log2(real(G_PHASE_DETECTOR_GAIN_DIV))) - log2(real(G_PHASE_DETECTOR_GAIN_DIV))) < 0.01 
        report "Gain divider factor must be a power of two. Got: " & integer'image(G_PHASE_DETECTOR_GAIN_DIV)
        severity error; 

    -- Instance for I/Q demodulator with NCO carrier oscillator and CIC decimation filter.
    inst_iq_demod : entity work.iq_demodulator
        generic map(
            G_DATA_WIDTH                    => G_DATA_WIDTH,
            G_OUTPUT_FRACTIONAL_BITS        => 0,
            G_CARRIER_PHASE_WIDTH           => G_NCO_PHASE_WIDTH,
            G_CARRIER_PHASE_FRACTIONAL_BITS => G_NCO_PHASE_FRACTIONAL_BITS,
            G_CIC_ORDER                     => G_CIC_ORDER,
            G_OUTPUT_COUNT                  => C_DEMOD_OUTPUT_COUNT,
            G_CIC_DECIMATION                => G_CIC_DECIMATION,
            G_ROUNDING_MODE                 => G_ROUNDING_MODE
        )
        port map(
            i_clk                  => i_clk,
            i_rst                  => i_rst,
            i_cfg_phase_step       => s_cfg_phase_step,
            i_cfg_phase_step_valid => '1',
            i_input                => i_input,
            o_input_ready          => o_input_ready,
            i_input_valid          => i_input_valid,
            o_output_i             => s_data_i,
            o_output_q             => s_data_q,
            i_output_ready         => s_data_ready,
            o_output_valid         => s_data_valid
        );
      
    -- Phase detector module used in frequency tracking loop
    inst_phase_detector : entity work.phase_detector
        generic map(
            G_INPUT_DATA_WIDTH      => G_DATA_WIDTH,
            G_INPUT_FRACTIONAL_BITS => 0
        )
        port map(
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_clk_en       => i_cfg_phase_detector_enable,
            i_input_i      => s_data_i(0),
            i_input_q      => s_data_q(0),
            i_input_valid  => s_data_valid(0),
            o_input_ready  => s_data_ready(0),
            o_output       => s_phase_error,
            o_output_valid => s_phase_error_valid,
            i_output_ready => s_phase_error_ready,
            i_cfg_mode     => i_cfg_phase_detector_mode
        );

    -- PID controller used as the loop filter in the frequency tracking loop.
    inst_phase_controller : entity work.pid_simple
        generic map(
            G_DATA_WIDTH           => G_DATA_WIDTH,
            G_DATA_FRACTIONAL_BITS => 0,
            G_COEF_WIDTH           => G_PHASE_DETECTOR_COEF_WIDTH,
            G_COEF_FRACTIONAL_BITS => G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS,
            G_ROUNDING_MODE        => G_ROUNDING_MODE
        )
        port map(
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_clk_en        => s_phase_detector_enable_controller,
            i_input         => resize(s_phase_error, s_phase_error),
            o_input_ready   => s_phase_error_ready,
            i_input_valid   => s_phase_error_valid,
            o_output        => s_phase_controller_output,
            o_output_strobe => s_phase_controller_output_strobe,
            i_cfg_coef_A    => i_cfg_phase_detector_coef_A,
            i_cfg_coef_B    => i_cfg_phase_detector_coef_B,
            i_cfg_coef_C    => i_cfg_phase_detector_coef_C
        );
    
    -- This process implements a threshold comperator that selecivly en- or disables the phase detectors controller,
    -- depending on the amplitude of the recieved I/Q samples and the configured threshold.
    --
    -- This is done by comparing valid samples to the configurd threshold and if no sample is above the threshold the
    -- the phase controller gets disabled until the next valid sample arrives.
    --
    -- Design goal is to allow the NCO to keep its phase while we do not recieve an input.
    proc_threshold_comperator : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                s_phase_detector_enable_controller <= '0';
                s_phase_detector_threshold <= to_sfixed(0, s_phase_detector_threshold);
            else
                s_phase_detector_threshold <= i_cfg_phase_detector_threshold;
                
                -- if the phase detector is enabled we generate the enable signal via a threshold comperator
                if i_cfg_phase_detector_enable = '1'  then
                    
                    -- if the data is valid we update the enable flag
                    if s_data_valid(0) = '1' then
                        
                        -- depending on whether we have either a I or a Q signal above the threshold
                        if (abs(s_data_i(0)) >= s_phase_detector_threshold) or (abs(s_data_q(0)) >= s_phase_detector_threshold) then
                            s_phase_detector_enable_controller <= '1';
                        else
                            s_phase_detector_enable_controller <= '0';
                        end if;
                    end if;
                    
                else
                    s_phase_detector_enable_controller <= '0';
                end if;
                
            end if;
        end if;
    end process proc_threshold_comperator;
      
    -- This process implements the NCO frequency register which contains the externally set NCO frequency value
    -- and the compensation value computed by the frequency tracking circuit.
    --
    -- If the phase detector is disabled then the register contents will be loaded every clock cycle from the i_cfg_nco_frequency input.
    --
    -- If the phase detector is enabled then the externally set value will be added to the frequency offset required for tracking as
    -- computed by the frequency tracker.
    -- This will be done every time a new sample is recieved from the frequency tracking loops PID controller.
    proc_NCO_freq_register : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                s_cfg_nco_frequency <= to_sfixed(0, s_cfg_nco_frequency);
                s_cfg_phase_step <= (others => '0');
            else
                
                -- if the phase detector is enabled then the output is: i_cfg_nco_frequency + s_phase_controller_output
                if i_cfg_phase_detector_enable = '1' then
                    s_cfg_nco_frequency <= i_cfg_nco_frequency;
                    
                    -- new sample from PID controller
                    if s_phase_controller_output_strobe = '1' then
                        
                        -- TODO: build numeric model to verify that the controller output gain (as designed here) is optimal!
                        
                        -- The externally set frequency value will be added to the controller response.
                        -- The controller output is interpreted as a fixed point value with the maximum value of exactly 2.00 phase increments.
                        s_cfg_phase_step <= to_slv(
                            resize(
                                s_cfg_nco_frequency + to_sfixed(std_logic_vector(s_phase_controller_output), -C_PHASE_CONTROLER_SHIFT, -(G_DATA_WIDTH + C_PHASE_CONTROLER_SHIFT) + 1), 
                                s_cfg_nco_frequency,
                                FIXED_OVERFLOW_STYLE,
                                G_ROUNDING_MODE
                            )
                        );
                    end if;
                else
                    -- we do not have the phase detector enable so we simply copy the input to the output
                    s_cfg_phase_step <= to_slv(i_cfg_nco_frequency);
                end if;
                
            end if;
        end if;
    end process proc_NCO_freq_register;
      
    -- assign primary I/Q output with all corresponding signals
    o_output_0_i <= s_data_i(1);
    o_output_0_q <= s_data_q(1);
    o_output_0_valid <= s_data_valid(1);
    s_data_ready(1) <= i_output_0_ready;
    
    -- assign actual NCO input value to a monitoring output
    o_mon_phase_detector_nco_adj <= to_sfixed(s_cfg_phase_step, o_mon_phase_detector_nco_adj);
    
    -- assign secondary I/Q output with all corresponding signals (if enabled!)
    gen_assign_second_output : if G_HAS_SECOND_OUTPUT generate
        o_output_1_i <= s_data_i(2);
        o_output_1_q <= s_data_q(2);
        o_output_1_valid <= s_data_valid(2);
        s_data_ready(2) <= i_output_1_ready; 
    end generate;

end architecture inst;
