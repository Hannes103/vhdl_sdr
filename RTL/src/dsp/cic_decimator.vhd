library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;
use ieee.fixed_pkg.all;

entity cic_decimator is
    
    generic(
        -- Specifies the cic filter order.
        -- The filter order can be used to control the frequency response of the CIC filter.
        -- 
        -- Restriction: Must be smaller or equal to G_DECIMATION.
        G_ORDER : integer range 1 to 16;
        
        -- Specfies the decimation factor that is used for resampling of the input signal.
        -- Every G_DECIMATION clock cycles of the i_clk a valid sample will be output via the o_output signal.
        --
        -- Restriction: Must be larger or equal to G_ORDER.
        G_DECIMATION : integer range 2 to 32;
        
        -- Specifies the width of the inputs signals integer part.
        -- The output integer part width is also specified by this generic.
        G_INPUT_WIDTH : integer range 8 to 32 := 16;
        
        -- Specifies the number of fractional bits of the input signal.
        G_INPUT_FRACTIONAL_BITS  : integer range 0 to 8 := 0;
        
        -- Specifies the additional output fractional bits that will be added by the filter.
        -- Must be smaller or equal to ceil(log2(G_DECIMATION)).
        G_OUTPUT_FRACTIONAL_BITS : integer range 0 to 5 := 0
    );
    
    port(
        i_clk : in std_logic;
        i_rst : in std_logic;
        
        i_input  : in sfixed(G_INPUT_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        i_input_valid : in std_logic;
        
        o_output : out sfixed(G_INPUT_WIDTH - 1 downto -(G_OUTPUT_FRACTIONAL_BITS + G_INPUT_FRACTIONAL_BITS));
        o_output_valid : out std_logic
    );
    
end entity cic_decimator;

-- Behavioral description of the cic_decimator.
architecture behav of cic_decimator is
    
    -- Specifies the width of the internal prescaler/counter used to generate the resampling clock enable.
    -- G_DECIMATION needs to be a power of two for this generation to work.
    constant C_RESAMPLE_COUNTER_WIDTH : integer := integer(LOG2(real(G_DECIMATION)));
    
    -- Specifies the width of the internal state counter that is used for
    constant C_COMB_STATE_WIDTH : integer := integer(ceil(LOG2(real(G_ORDER))));
    
    -- Specifies with of the integrator accumulators the the pipelining registers used in the comb blocks.
    -- Must be large enough to store the maximum input sample times the decimation factor, for all integrators.
    -- Theoretically every integrator could have a different width for more efficient use of resources, however
    -- this is not implemented here.
    constant C_INTERNAL_WIDTH : integer := G_INPUT_WIDTH + G_INPUT_FRACTIONAL_BITS + integer(ceil(real(G_ORDER) * log2(real(G_DECIMATION))));
    
    -- This type is used for storage to implement the different deplay lines required.
    -- The delay line depth is equal to the filter order and its width is equal to the maximum accumulator width we need to
    -- prevent unwanted overflows.
    type t_delay_storage is array(G_ORDER - 1 downto 0) of signed(C_INTERNAL_WIDTH - 1 downto 0);
    
    -- Signals: resampler
    
    signal s_resampl_counter : unsigned(C_RESAMPLE_COUNTER_WIDTH - 1 downto 0) := (others => '0');
    signal s_keep_sample     : std_logic;
    
    -- Signals: integrator
    
    signal s_int_delay_line  : t_delay_storage;
    
    -- Signals: comb
    
    signal s_comb_delay_line : t_delay_storage;
    signal s_comb_output     : t_delay_storage;
    
    signal s_comb_state : unsigned(C_COMB_STATE_WIDTH - 1 downto 0) := (others => '0');
    signal s_comb_prevent_output : std_logic;
    
    -- Signals: output generation
    
    signal s_output : signed( G_INPUT_WIDTH + G_INPUT_FRACTIONAL_BITS + G_OUTPUT_FRACTIONAL_BITS - 1 downto 0 );
    signal s_output_valid_delay : std_logic;
    signal s_output_valid : std_logic;
begin
    
    -- Assert that the number of fractional output bits is not larger than the gained filter accuracy allows
    -- This check is required so that the shifting logic does not recieve invalid bit indices
    assert G_OUTPUT_FRACTIONAL_BITS <= integer(ceil(log2(real(G_DECIMATION))))
        report "Output fractional bits are constrained by decimation factor! Got: " & integer'image(G_OUTPUT_FRACTIONAL_BITS) &
        " expected: [0;" & integer'image(integer(log2(real(G_DECIMATION)))) & "]"
        severity error;
    
    -- Verify that the provided decimation factor is a power of two.
    -- This is required so that we do not need a division for the correct scaling of the output.
    -- NOTE: There may be some IEEE-754 wierdness going on here so we do not check for equality but whether the difference is smaller
    --       than achiveable with G_DECIMATION being integer
    assert abs(round(log2(real(G_DECIMATION))) - log2(real(G_DECIMATION))) < 0.01 
        report "Decimation factor must be a power of two. Got: " & integer'image(G_DECIMATION)
        severity error; 
    
    -- Verify that the filter order is smaller than the configured decimation factor.
    -- This is required because otherwise the internal comb pipelining does not work.
    assert G_ORDER <= G_DECIMATION 
        report "Filter order cannot exceed decimation factor! Got: " & integer'image(G_ORDER)
        severity error;
    
    -- This process implements the G_ORDER integrators thats forms the portion of the filter running at input clock frequency.
    -- Every time the input sample is valid the integrator section will update the entire cain.
    -- The output of the integrator section can be accessed via s_int_delay_line(G_ORDER - 1).
    proc_integrator : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                -- synchronous reset for the internal storage registers
                s_int_delay_line <= (others => (others => '0'));
            else
                -- we can only process samples if our input is valid.
                if i_input_valid = '1' then
                
                    -- First stage needs to be implemented manually the other stages can be generated using for loops.
                    s_int_delay_line(0) <= s_int_delay_line(0) + signed(to_slv(i_input));         
                    for i in 1 to G_ORDER - 1 loop
                        s_int_delay_line(i) <= s_int_delay_line(i) + s_int_delay_line(i - 1);
                    end loop;  
                
                end if;
            end if;
            
        end if;
    end process proc_integrator;
    
    -- This process implements to comb section running in the down samplened section of the filter.
    -- It implements G_ORDER differentiators that run synchronously to the down sampled input clock.
    --
    -- Every G_DECIMATION i_clk cycles (everytime the s_keep_sample-signal is high) the comb chain will be updated exactly once.
    -- The comb chain is updated sequentially over G_ORDER clock cycles after the s_keep_sample signal.
    --
    -- Once the last comb section has been updated and is valid to be output the s_comb_prevent_output flag will be set to low,
    -- The final output value will be accessible via the s_comb_output(G_ORDER-1) signal.
    --
    -- The input will be taken from the last stage of the integrator section. (s_int_delay_line(G_ORDER - 1))
    -- Processing of samples only occures while i_input_valid is high.
    proc_comb : process(i_clk) is
        -- This variable is used as a temporary (intra-execution) storage of the address of the comb section that should be updated
        -- this cycle.
        variable current_index : integer range G_ORDER downto 0;
    begin
        if rising_edge(i_clk)  then
            if i_rst = '1' then
                -- synchronous reset of all registers written by this process
                s_comb_delay_line <= (others => (others => '0'));
                s_comb_output <= (others => (others => '0'));
                
                s_comb_state <= (others => '0');
                s_comb_prevent_output <= '1';
            else
                -- we can only continue if our input is invalid. If not, then we pause
                if i_input_valid = '1' then
                
                    -- we want to keep the current sample
                    if s_keep_sample = '1' then
                        -- Start the processing of the current sample by latching it into the first comb section
                        -- and initiating the comb ripple by setting the correct s_comb_state and allowing the output to be updated.
                        s_comb_delay_line(0) <= s_int_delay_line(G_ORDER - 1);
                        s_comb_output(0)     <= s_int_delay_line(G_ORDER - 1) - s_comb_delay_line(0);
                        
                        s_comb_state <= to_unsigned(G_ORDER - 1, s_comb_state);
                        s_comb_prevent_output <= '0';
                    end if;
                    
                    -- for cic filters with not unity order we need to ripple trough the chain of combs
                    -- updating each comb exactly once for a single sample
                    --
                    -- The processing is done sequentially over multiple clock cycle because we want to minimize
                    -- the critical path.
                    if (s_comb_state /= 0) and (G_ORDER > 1) then
                        current_index := G_ORDER - to_integer(s_comb_state);
                        
                        -- implements the comb (differentiator) section
                        s_comb_delay_line(current_index) <= s_comb_output(current_index - 1);
                        s_comb_output(current_index)     <= s_comb_output(current_index - 1) - s_comb_delay_line(current_index);
                        
                        -- decrement the current comb section, so that the next section will be updated.
                        s_comb_state <= s_comb_state - 1;
                    else
                        -- if the comb state is zero then we have to set
                        -- the prevent output flag.
                        if s_comb_prevent_output <= '0' then
                            s_comb_prevent_output <= '1';
                        end if;
                    end if;
                    
                end if;
            end if;
            
        end if;
    end process proc_comb;
    
    -- This process implements the update of the output data register every time a new sample is produced by the comb section of the filter.
    -- Depending on the filter order (=1, /= 1) the trigger for this will be different:
    --  - G_ORDER = 1 : Every time the s_comb_prevent_output flag is low
    --  - G_ORDER > 1 : Every time the s_comb_prevent_output flag is low, and the s_comb_state is equal to zero (last subsample was processed)
    --
    -- In additional to the output data register update a output data valid strobe signal will be generated.
    -- This strobe is delayed one clock cycle, so that the newly produced data has enough time to be stable.
    --
    -- Output generation is paused will the component is reset and while the input sample is not valid.
    proc_output : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            
            if i_rst = '1' then
                s_output_valid <= '0';
                s_output_valid_delay <= '0';
                
                s_output <= (others => '0');
            else
                -- we can only continue if the input is valid, otherwise we need to pause
                if i_input_valid = '1' then
                    -- only update the output IF the prevent output flag is low
                    -- its used to indicate that the comb update state machine is active
                    --
                    -- for a first order filter we can simply pass the s_keep_sample flag along.
                    -- for higher order filters we need to do this on the last comb pipeline stage
                    if ( ((G_ORDER > 1) and (s_comb_state = 0)) or (G_ORDER = 1)) and (s_comb_prevent_output = '0') then
                        
                        -- generate a single cycle output valid flag that can be used to latch our output.
                        s_output_valid <= '1';
                        
                        -- We need to divide by the CIC filter output by the gain of the filter to normalize it.
                        -- The gain of a multistage CIC filter (with unity delay after resampling) is DECIMATION**ORDER.
                        -- We divide by shifting the appropriate number of bits.
                        s_output <= s_comb_output(G_ORDER - 1)(C_INTERNAL_WIDTH - 1 downto C_INTERNAL_WIDTH - G_INPUT_WIDTH - G_INPUT_FRACTIONAL_BITS - G_OUTPUT_FRACTIONAL_BITS); 
                        
                    else
                        s_output_valid <= '0';
                    end if;
                    
                    -- We need to delay the output valid flag by one clock cycle so that our output is stable already.
                    s_output_valid_delay <= s_output_valid;
                end if;
            end if;
            
        end if;
    end process proc_output;
    
    -- assign output, by conversion of internal fixed point format (represented by a signed value) to the sfixed type.
    o_output <= to_sfixed( std_logic_vector(s_output), o_output );
           
    o_output_valid <= s_output_valid_delay;
    
    -- This process implements the generation of the synchronous clock enable flag used to resample
    -- the incoming data. This is done using a up counter (prescaler) that overflows every G_DECIMATION cycles.
    -- This requires that the decimation value is a power of two.
    --
    -- The resample counter is disabled while the component is under reset or if the input sample is invalid.
    proc_resampler : process(i_clk) is
    begin
        -- synchronous logic
        if( rising_edge(i_clk) ) then
            if i_rst = '1' then
                -- synchronous reset, set everything to zero.
                s_resampl_counter <= (others => '0');
                
            else
                -- sample counter can only increment if the input is valid
                if i_input_valid = '1' then
                    -- if not reset then the increment the counter by one every clock cycle
                    s_resampl_counter <= s_resampl_counter + 1;
                end if;
            end if;
        end if;
    end process proc_resampler;
    
    -- clock enable is generated combinatorically from the internal decimation prescaler
    -- s_keep_sample will be high for exacly one clock cycle end then low for G_DECIMATION_COUNTER - 1 cycles.
    s_keep_sample <= '1' when (s_resampl_counter = to_unsigned(0, C_RESAMPLE_COUNTER_WIDTH)) and i_rst = '0' else '0';
    
end architecture behav;