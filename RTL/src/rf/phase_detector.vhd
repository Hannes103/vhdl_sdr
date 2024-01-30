library ieee;

use ieee.std_logic_1164.all;
use ieee.fixed_pkg.all;

-- This entity implements a simple I/Q phase detector that supports both BPSK (two constellation points) or QAM-4 (4-constellation points).
-- 
-- Input and output data streams are in signed fixed point format.
-- Input to output latency is 3 clock cycles. The design is not pipelined, so can accept a new sample every 3 clock cycles.
entity phase_detector is
    
    generic(
        -- This generic specifies the number of data bits in the internal part of the input signals. (I and Q data path)
        -- The input data format is signed, so this width also includes one sign bit.
        -- Will also be used as the data width for the output.
        G_INPUT_DATA_WIDTH : integer := 16;
        
        -- Specifies the number of fractional bits in the input and output signals.
        G_INPUT_FRACTIONAL_BITS : integer := 0
    );
    
    port(
        -- Synchronous clock input.
        i_clk : in std_logic;
        
        -- Input clock enable signal.
        i_clk_en : in std_logic := '1';
        
        -- Active high synchronous reset input.
        i_rst : in std_logic;
        
        -- AXI stream data for input port. (Real component)
        --
        -- Represents the real (or inphase) component of the complex input data stream.
        -- Is used to compute the phase error.
        --
        -- Forms the first half of the AXI stream input data signal.
        i_input_i : in sfixed( G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS );
        
        -- AXI stream data for input port. (Imaginary component)
        -- 
        -- Represents the imaginary (or quadature) component of the complex input data stream.
        -- Is used to compute the pase error.
        --
        -- Forms the second half of the AXI stream input data signal.
        i_input_q : in sfixed( G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS );
        
        -- AXI stream valid signal for input port.
        i_input_valid : in std_logic;
        
        -- AXI stream ready signal for input port.
        o_input_ready : out std_logic; 
        
        -- AXI stream output of computed phase error.
        --
        -- If the output is positive, then there is a positive phase offset between the input signal and nearest corresponding constellation reference point.
        -- The constellation points used depend on the selected configuration mode (bypass, product)
        -- If the output is negative, then there is a negative phase error.
        o_output : out sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        
        -- AXI stream valid signal for output port.
        o_output_valid : out std_logic;
        
        -- AXI stream ready signal for output port.
        i_output_ready : in std_logic;
        
        -- This input selects the phase detectors mode of operation.
        -- Will be latched one clock cycle befor a new output is presented. 
        --
        -- If set to '1' it selects the QAM-4 or product mode.
        -- In this mode of computation the output signal will be performed using the following equation that is
        -- suitable for use in QAM-4/QPSK-4 systems: output = sign(I)*Q - sign(Q)*I.
        --
        -- If set to '0' it selectes the BPSK or bypass mode.
        -- In this mode the phase error computation is bypassed and the Q sample is output directly.
        -- This is suitable for use in binary phase keying systems.
        i_cfg_mode : in std_logic
    );
    
end entity phase_detector;

-- This architecture contains the behavioural description of the phase detector.
architecture behav of phase_detector is
    
    -- Signals: state machine
    
    type t_state_multiplier is (MULT_WAIT_FOR_INPUT, MULT_MULTIPLY, MULT_ACCUMULATE);
    signal s_state_multiplier : t_state_multiplier;
    
    type t_state_output is (OUTPUT_WAIT_FOR_RESULT, OUTPUT_WAIT_FOR_READY );
    signal s_state_output : t_state_output;
    
    -- Signals: input management
    
    signal s_input_i  : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_input_q  : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    
    signal s_input_ready : std_logic;
    
    -- Signals: output management
    
    signal s_output : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_output_valid : std_logic;
    
    signal s_cfg_mode : std_logic;
    
    -- Signals: multiplier
    
    signal s_data_i_mult : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);    
    signal s_data_q_mult : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    
    signal s_result_multiplier : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_result_available : std_logic;
begin
    
    proc_output : process(i_clk) is
    begin
        if rising_edge(i_clk) then 
            if i_rst = '1' then

                s_output <= to_sfixed(0, s_output);
                s_output_valid <= '0';
            elsif i_clk_en = '1' then
                -- we always want to latch the current output mode
                s_cfg_mode <= i_cfg_mode;
                
                -- the output is also implemented using a state machine to allow back pressure from the consuming device 
                -- at best this allows us to output data a f_clk/2. However because we are working in the low sample rate domain
                -- we shouldnt need any more troughput than f_clk/8.
                --
                -- A state machine is used to allow for low latency output.
                case s_state_output is
                    
                    -- first stage is to wait for the result from the multiplier
                    -- We use a single clock cycle strobe signal to detect when the multiplier is ready.
                    -- If the recieving unit cannot accept a sample every time we present one we will lose data here.
                    -- If the recieving unit can accept a sample every time we present one, we should be able to operate at the
                    -- 100% troughput (as limited by the multiplier)
                    when OUTPUT_WAIT_FOR_RESULT =>  
                        if s_result_available = '1' then
                            
                            -- depending on the selected mode (MULTIPLY, PASSTROUGH) we either use the
                            -- result calculated by the multplier or just pass the Q component trough.
                            if s_cfg_mode = '1' then
                                s_output <= s_result_multiplier;
                            else
                                s_output <= resize(s_input_q, s_output);
                            end if;
                            
                            -- output is now valid
                            s_output_valid <= '1';
                            
                            s_state_output <= OUTPUT_WAIT_FOR_READY;
                        else
                            s_state_output <= OUTPUT_WAIT_FOR_RESULT;
                        end if;
                        
                    when OUTPUT_WAIT_FOR_READY =>
                        -- wait for ready signal and if we have it then reset the valid signal
                        -- and return to waiting
                        if i_output_ready = '1' then
                            s_output_valid <= '0';
                        
                            s_state_output <= OUTPUT_WAIT_FOR_RESULT;
                        else
                            s_state_output <= OUTPUT_WAIT_FOR_READY;
                        end if;
                        
                end case;
                            
            end if;     
        end if;
    end process proc_output;
     
    o_output <= s_output;
    o_output_valid <= s_output_valid;
    
    proc_multiplier : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            
            if i_rst = '1' then
                -- reset both the raw input data and the multiplier registers
                s_input_i <= to_sfixed(0, s_input_i);
                s_input_q <= to_sfixed(0, s_input_q);
                s_input_ready <= '0';
        
                s_data_i_mult <= to_sfixed(0, s_data_i_mult);
                s_data_q_mult <= to_sfixed(0, s_data_q_mult);
                
                -- result is not valid
                s_result_multiplier <= to_sfixed(0, s_result_multiplier);
                s_result_available <= '0';
                
                s_state_multiplier <= MULT_WAIT_FOR_INPUT;
            elsif i_clk_en = '1' then
                
                -- The phase detector is inteded to be used in the low sampling rate domain (after decimation).
                -- Because of this not every input sample will be present. We cant simply stall the entire pipeline because
                -- we want minimal latency.
                -- So to avoid complex pipeline stall mechanisms we simply use a state machine. This however will limit troughput.
                case s_state_multiplier is
                    
                    -- first step is to latch the input and send an acknowlege
                    when MULT_WAIT_FOR_INPUT =>
                        -- take back the new data available flag
                        s_result_available <= '0';
                        
                        if i_input_valid = '1' then
                            -- acknowlege input
                            s_input_ready <= '1';
                            
                            -- lata data
                            s_input_i <= i_input_i;
                            s_input_q <= i_input_q;
                            
                            s_state_multiplier <= MULT_MULTIPLY;
                        else
                            s_state_multiplier <= MULT_WAIT_FOR_INPUT;
                        end if;
                        
                    -- Second step is to perform the "multplication" of the latched input operands     
                    when MULT_MULTIPLY =>
                        -- reset input acknowlege bit
                        s_input_ready <= '0';
                        
                         -- s_data_i_mult = sign(s_input_q) * s_input_i;
                        if( s_input_q < 0 ) then
                            s_data_i_mult <= resize(-s_input_i, s_data_i_mult);
                        else
                            s_data_i_mult <= s_input_i;
                        end if;
                            
                        -- s_data_q_mult = sign(s_input_i) * s_input_q;
                        if( s_input_i < 0 ) then
                            s_data_q_mult <= resize(-s_input_q, s_data_q_mult);
                        else
                            s_data_q_mult <= s_input_q;
                        end if;
                        
                        s_state_multiplier <= MULT_ACCUMULATE;
                      
                    -- last step is to sum the two pre-multiplied values together and signal the
                    -- output module that new data is avaliable. This is done via a single cycle strobe signal.  
                    when MULT_ACCUMULATE =>
                        -- s_result_multiplier = s_data_q_multi - s_data_i_mult
                        s_result_multiplier <= resize(s_data_q_mult - s_data_i_mult, s_result_multiplier);
                    
                        -- signal the output process that we have a new result
                        -- this strobe is exactly one cycle long.
                        s_result_available <= '1';
              
                        -- return to initial state
                        s_state_multiplier <= MULT_WAIT_FOR_INPUT;               
                end case;
            end if;
        end if;
    end process proc_multiplier;
    
    o_input_ready <= s_input_ready; 
    
end architecture behav;