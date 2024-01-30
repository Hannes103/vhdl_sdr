library ieee;

use ieee.std_logic_1164.all;

use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;

-- This entity implements a simple PID-style discrete type controller.
-- 
-- It does not feature anti-wind up or any other special features because the controller is implemented
-- using the (simplified/combined) second order time discrete transfer function: F(z)=(A*z^2 + B*z + C)/(z^2 - 1)
--
-- Input data and output data integer and fractional width can be controlled using the provided generic flags.
-- The filtering coefficients A,B and C can be provided via input signals and are dynamically changeable.
-- 
-- The input data interface consists of a simple AXI stream interface.
--
-- The output data interface consists of a output data bus and a strobe signal that indicates when the output data is valid.
-- Its designed to drive a simple register style interface that latches the data once ready.
--
-- Between providing input data and the output data being ready it takes at most 7 clock cycles.
-- This module is NOT pipelined, as such it can only accept data every 8 clock cycles.
entity pid_simple is
    generic(
        -- This generic specifies the input data integer part width in bits.
        -- The input data is signed and the sign bit will count torwards the here configured bit width.
        -- 
        -- The signal output will have the identical bit width. 
        G_DATA_WIDTH           : integer := 16;
        
        -- This generic specifies the width of the fractial component of the input data.
        -- If not required (only integer samples are provided) it should be set to zero. 
        G_DATA_FRACTIONAL_BITS : integer := 0;
        
        -- This generic specififes the integer part width of the filtering coefficients A,B and C.
        -- The coefficients are signed and the sigh bit will count torwards the here configured bit length.
        G_COEF_WIDTH           : integer := 5;
        
        -- This generic specifies the frational part width of the filtering coefficients A,B and C.
        G_COEF_FRACTIONAL_BITS : integer := 8;
    
        -- This generic can be used to control the rounding operation that is done to truncate the result of the
        -- internal calculations down to configued output data width.
        G_ROUNDING_MODE : fixed_round_style_type := FIXED_ROUND_STYLE
    );
    port(
        -- Input clock signal.
        signal i_clk : in std_logic;
        
        -- Input clock enable signal.
        signal i_clk_en : in std_logic := '1';
        
        -- Active high synchronous reset signal.
        signal i_rst : in std_logic;
        
        -- Input data signal (AXI-Stream TDATA)
        signal i_input       : in sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
        -- Input data was latched by controller signal (AXI-Stream TREADY)
        signal o_input_ready : out std_logic;
        -- Input data is valid signal (AXI-Stream TVALID)
        signal i_input_valid : in std_logic;
        
        -- Output data signal
        -- 
        -- The output data calculated from the configued transfer function will be output using this signal.
        -- A change to this output will always be followed by a rising edge of o_output_strobe.
        --
        -- The output data stays stable after the o_output_strobe until the next sample has been processed.
        signal o_output : out sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
        
        -- Output data valid signal
        --
        -- The outout data interface is designed to drive a simple register set that latches the output
        -- provided a o_output every time this signal is high.
        --
        -- Will be high for exactly one clock cycle after the output data has been updated with the newly calculated signal.
        signal o_output_strobe : out std_logic;
        
        -- Transfer function coefficient A input signal.
        --
        -- Will be latched from this signal every time a new input sample is accepted into the controller. (See: i_input_valid)
        -- Between samples the value of this signal does not matter.
        --
        -- The A-coefficient can be calculated from the time continous parameters of the PID-Controller in the following manner:
        -- A = K*(1 + Ta/(2*Tn) + (2*Tv)/Ta)
        -- (Ta = Sampling Time, Tn = integrator time constant, Tv = differentiator time constant) 
        signal i_cfg_coef_A : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
        
        -- Transfer function coefficient B input signal.
        --
        -- Will be latched from this signal every time a new input sample is accepted into the controller. (See: i_input_valid)
        -- Between samples the value of this signal does not matter.
        --
        -- The B-coefficient can be calculated from the time continous parameters of the PID-Controller in the following manner:
        -- B = K*(Ta/Tn - (4*Tv)/Ta)
        -- (Ta = Sampling Time, Tn = integrator time constant, Tv = differentiator time constant) 
        signal i_cfg_coef_B : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
        
        -- Transfer function coefficient C input signal.
        --
        -- Will be latched from this signal every time a new input sample is accepted into the controller. (See: i_input_valid)
        -- Between samples the value of this signal does not matter.
        --
        -- The C-coefficient can be calculated from the time continous parameters of the PID-Controller in the following manner:
        -- C = K*(Ta/(2*Tn) + (2*Tv)/Ta - 1)
        -- (Ta = Sampling Time, Tn = integrator time constant, Tv = differentiator time constant) 
        signal i_cfg_coef_C : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS)
    );
end entity pid_simple;

-- This architecture describes the behaviour of the simple pid controller.
architecture behav of pid_simple is
    -- Types used in other signals
    
    type t_input_storage is array (natural range <>) of sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
    type t_temp_storage is array (natural range <>) of sfixed(G_DATA_WIDTH + G_COEF_WIDTH - 1 downto -(G_DATA_FRACTIONAL_BITS + G_COEF_FRACTIONAL_BITS));
    type t_processing_state is (WAIT_FOR_INPUT, MULTIPLY0, MULTIPLY1, ADD0, ADD1, OUTPUT);
    
    -- Signals: state machine 
    
    signal s_processing_state : t_processing_state;
    
    -- Signals: input buffer registers for filter coefficients
    
    signal s_cfg_coef_A : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_B : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_C : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);

    -- Signals: register chains used to storage of the old input and output samples    
    
    signal s_data      : t_input_storage(2 downto 0);
    signal s_result    : t_input_storage(2 downto 0);

    -- Signals: temporary registers used to pass calculation results from DSP slice to DSP slice

    signal s_temp_prod : t_temp_storage(2 downto 0);
    signal s_temp_add  : t_temp_storage(2 downto 0);
    
    -- Signals: input and output management signals   
    
    signal s_input_ready  : std_logic;
    signal s_output_strobe : std_logic;
    
begin
    
    -- This process implements the PID controller transfer function using a 7 state satemachine.
    -- It latches input data using an AXI-Stream interface and calculates the system response.
    -- Then outputs everyting.
    proc_controller : process(i_clk) is
    begin
        
        if rising_edge(i_clk) then
                        
            if i_rst = '1' then
                s_processing_state <= WAIT_FOR_INPUT;
                
                -- reset coefficients      
                s_cfg_coef_A <= to_sfixed(0, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed(0, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed(0, s_cfg_coef_C);
                
                -- reset data registers
                s_data      <= ( others => to_sfixed(0, s_data(0)) );
                s_temp_prod <= ( others => to_sfixed(0, s_temp_prod(0)) );
                s_temp_add  <= ( others => to_sfixed(0, s_temp_prod(0)) );
                s_result    <= ( others => to_sfixed(0, s_result(0)) );
                
                s_input_ready <= '0';
                s_output_strobe <= '0';
                
            elsif i_clk_en = '1' then
                -- reset output valid strobe
                -- because we only want to generate a single cycle strobe.
                s_output_strobe <= '0';
                
                -- the following state machine is designed to implement the simplified transfer equation of a PID controller
                -- it uses 6 clock cycles per sample and contains enough wait states to fully allow DSP slices to be used.
                case s_processing_state is
                    
                    -- frist stage is an AXI stream style input interface
                    -- that stores the input data, as well as the input coefficients in temporary registers for later use
                    when WAIT_FOR_INPUT =>
                        s_output_strobe <= '0';
                        
                        -- wait until we have an input and latch all inputs
                        if i_input_valid = '1' then
                            -- acknowlege that we have fetched the input
                            s_input_ready <= '1';
                            
                            -- shift input chain
                            s_data(0) <= i_input;
                            s_data(1) <= s_data(0);
                            s_data(2) <= s_data(1);
                            
                            -- shift output chain
                            s_result(1) <= s_result(0);
                            s_result(2) <= s_result(1);
                            
                            -- store coefficients
                            s_cfg_coef_A <= i_cfg_coef_A;
                            s_cfg_coef_B <= i_cfg_coef_B;
                            s_cfg_coef_C <= i_cfg_coef_C;
                            
                            s_processing_state <= MULTIPLY0;
                        else
                            s_processing_state <= WAIT_FOR_INPUT;
                        end if;
                        
                    -- second stage is the multplication of the first temporary
                    when MULTIPLY0 =>
                        -- one cycle after latching the data we want to reset the ready flag.
                        s_input_ready <= '0';
                        
                        -- to allow inference of DSP slices we multiply one values first, giving it one clock cycle more time
                        -- to propagate to the other dsp slice where it will be then added
                        s_temp_prod(0) <= s_data(0) * s_cfg_coef_A;

                        s_processing_state <= MULTIPLY1;
                    
                    when MULTIPLY1 =>
                        -- now we multiply the other two values
                        s_temp_prod(1) <= s_data(1) * s_cfg_coef_B;   
                        s_temp_prod(2) <= s_data(2) * s_cfg_coef_C; 
                          
                        s_processing_state <= ADD0;
                    
                    when ADD0 =>
                        -- on more clock cycle so that we should not have both the recently multiplied values
                        -- and the multplication result from before in the post adder registers of the DSP slice
                        s_temp_add(0) <= resize(s_temp_prod(1) + s_temp_prod(0), s_temp_add(0));
                        s_temp_add(1) <= resize(s_temp_prod(2) + s_result(2), s_temp_add(1)); 
                        
                        s_processing_state <= ADD1;
                        
                    when ADD1 =>
                        -- finally a logic level adder that finalizes the result
                        s_temp_add(2) <= resize(s_temp_add(0) + s_temp_add(1), s_temp_add(2)); 
                        
                        s_processing_state <= OUTPUT;
                    
   
                    when OUTPUT =>
                        -- truncate result and write to output
                        s_result(0) <= resize(s_temp_add(2), s_result(0), FIXED_OVERFLOW_STYLE, G_ROUNDING_MODE);
                        s_output_strobe <= '1';
                        
                        s_processing_state <= WAIT_FOR_INPUT;
                
                end case;    
            end if;        
        end if;
        
    end process proc_controller;
    
    o_input_ready <= s_input_ready;
    
    o_output <= s_result(0);
    o_output_strobe <= s_output_strobe;
    
end architecture behav;