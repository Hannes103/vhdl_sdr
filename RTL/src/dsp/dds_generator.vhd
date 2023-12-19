library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.dds_generator_pgk.all;

entity dds_generator is

    generic(
        -- Specifies the number of bits that are used for integer part of the phase accumulator.
        -- The number of points in the sine lookup table will be: 2**G_PHASE_WIDTH
        G_PHASE_WIDTH : integer := 5;
        
        -- Specifies the number of fractional bits that are used in the phase accomulator.
        -- The granularity of the phase increment is defined by this number.
        G_PHASE_FRACTIONAL_BITS : integer := 10;
        
        -- Specifies the output data width of the generated sinusodial signal.
        G_SIGNAL_WIDTH : integer := 10;
        
        -- If this parameter is set to true then the output sine/cosine wave(s) will be linearly interpolated using the
        -- fractional phase accumulator. If set to false then only the lookup table values will be used.
        -- 
        -- Has the most effect, if the phase increment has a value smaller than unity.
        G_ENABLE_INTERPOLATION : boolean := true;
        
        -- If this parameter is set to true the non shifted output (o_output) will be inverted.
        -- If set to false then the output at the o_output is a sin(x) if set to true its a -sin(x)
        G_INVERT_OUTPUT : boolean := true;
        
        -- If this parameter is to true then an 90 degree shifted sine wave (cos()) will be output using the
        -- o_output_shifted port. If set to false then the shifted output will be tied to zero.
        G_ENABLE_SHIFTED_OUTPUT : boolean := true;
        
        -- If this parameter is set to true then the shifted output (o_output_shifted) will be inverted.
        -- If set to false then the output at the o_output is a cos(x) if set to true its a -cos(x)
        G_INVERT_SHIFTED_OUTPUT : boolean := false
    );
    
    port(
        -- Synchronous clock input.
        i_clk : in std_logic;
        
        -- Synchronous (active high) clock enable that clock gates all internal registers.
        -- Can be used to implement a external clock prescaler.
        i_clk_en : in std_logic;
        
        -- Active high synchronous reset.
        -- Used to reset all internal registers, forces the outputs to zero and resets the internal phase accumulator to zero.
        i_rst : in std_logic;
        
        -- Phase accumulator step size input. 
        -- This input directly controls the phase increment each clock cycle and can as such be used to control the output waveforms frequency.
        -- Affects both output waveforms (shifted/non shifted).
        --
        -- Data is stored in a fixed point format with the most significant G_PHASE_WIDTH bits as the integer component and the least sigificant G_PHASE_FRACTIONAL_BITS
        -- as the fractional component.
        -- 
        -- The output frequency can be calculated using the following formular:
        --    f_out = (F_i_clk / 2**G_PHASE_WIDTH) * phase_step
        -- 
        -- Where "phase_step" represents the fractional number represented by this input.
        -- The to_phase_increment() function on the dds_generator_pgk can be used to convert the real phase step to a fixed point std_logic_vector() representation.
        i_phase_step : in std_logic_vector(G_PHASE_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto 0);
        
        -- Generated wave form output, not shifted.
        -- Outputs a sin(x) if G_INVERT_OUTPUT is false, outputs a -sin(x) if G_INVERT_OUTPUT is true.
        --
        -- Number of bits is specified by the G_PHASE_WIDTH parameter.
        -- Output format is signed decimal.
        --
        -- With the default generic configuration this output will be a -sin(x)
        o_output         : out std_logic_vector(G_SIGNAL_WIDTH - 1 downto 0);
        
        -- Generated wave form output, shifted.
        -- Only active if G_ENABLE_SHIFTED_OUTPUT set to true. Otherwise its forced to zero.
        --
        -- Outputs a cos(x) if G_INVERT_SHIFTED_OUTPUT is false, outputs a -cos(x) if G_INVERT_SHIFTED_OUTPUT is true.
        --
        -- Number of bits is specified by the G_PHASE_WIDTH parameter.
        -- Output format is signed decimal.
        -- 
        -- With the default generic configuration this output will be a cos(x)
        o_output_shifted : out std_logic_vector(G_SIGNAL_WIDTH - 1 downto 0)
    );
end entity dds_generator;

architecture behav of dds_generator is
    
    -- Sinusodial wave form lookup table that is used as the basis for signal generation.
    -- Values are generated based on the G_PHASE_WIDTH parmameter, with the number of data points in the table equal to 2**G_PHASE_WIDTH.
    -- Datapoint format is signed decimal with the width specified by G_SIGNAL_WIDTH.
    constant C_SIN_TABLE : t_sin_lut := init_sin_lut(G_PHASE_WIDTH, G_SIGNAL_WIDTH);
    
    -- input buffer registers
    signal s_phase_step : unsigned(G_PHASE_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    -- internal counter used for phase accumulator
    signal s_phase_counter : unsigned(G_PHASE_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto 0) := (others => '0');
    signal s_phase : unsigned(G_PHASE_WIDTH - 1 downto 0);
    signal s_phase_shifted : unsigned(G_PHASE_WIDTH - 1 downto 0);
    signal s_phase_frac : unsigned(G_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    -- internal signals that deal with the conditioning of the lookup table data
    signal s_table_out         : signed(G_SIGNAL_WIDTH - 1 downto 0);   
    signal s_table_out_shifted : signed(G_SIGNAL_WIDTH - 1 downto 0);
    signal s_table_out_delay         : signed(G_SIGNAL_WIDTH - 1 downto 0);
    signal s_table_out_delay_shifted : signed(G_SIGNAL_WIDTH - 1 downto 0);
    
    -- internal signals that are related to the interpolation of the output data
    signal s_table_next         : signed(G_SIGNAL_WIDTH - 1 downto 0); 
    signal s_table_next_shifted : signed(G_SIGNAL_WIDTH - 1 downto 0);
    
    signal s_table_diff         : signed(G_SIGNAL_WIDTH - 1 downto 0);
    signal s_table_diff_shifted : signed(G_SIGNAL_WIDTH - 1 downto 0);
    
    signal s_table_interp         : signed(G_SIGNAL_WIDTH + G_PHASE_FRACTIONAL_BITS downto 0);
    signal s_table_interp_shifted : signed(G_SIGNAL_WIDTH + G_PHASE_FRACTIONAL_BITS downto 0);
    
    signal s_table_sum          : signed(G_SIGNAL_WIDTH downto 0);
    signal s_table_sum_shifted  : signed(G_SIGNAL_WIDTH downto 0);
    
    -- output buffer registers
    signal s_output_reg         : signed(G_SIGNAL_WIDTH - 1 downto 0);
    signal s_output_shifted_reg : signed(G_SIGNAL_WIDTH - 1 downto 0);
    
    procedure update_output_register(
        signal p_phase_frac      : in unsigned(G_PHASE_FRACTIONAL_BITS - 1 downto 0);
        
        signal p_table_out       : in    signed(G_SIGNAL_WIDTH - 1 downto 0);
        signal p_table_out_delay : inout signed(G_SIGNAL_WIDTH - 1 downto 0);
        signal p_table_next      : in signed(G_SIGNAL_WIDTH - 1 downto 0);
        signal p_table_diff      : inout signed(G_SIGNAL_WIDTH - 1 downto 0);
        signal p_table_interp    : inout signed(G_SIGNAL_WIDTH + G_PHASE_FRACTIONAL_BITS downto 0);
        signal p_table_sum       : inout signed(G_SIGNAL_WIDTH downto 0);
        signal p_output_reg      : out signed(G_SIGNAL_WIDTH - 1 downto 0);
        
        constant C_INVERT_SIGNAL   : boolean
    ) is
        -- constant specifies the maximum signal amplitude that is used for clamping the output
        constant C_SIGNAL_MAX_VALUE : integer := 2**(G_SIGNAL_WIDTH - 1) - 1;
        -- constant specifies the minimum signal amplitude that is used for clamping the output
        constant C_SIGNAL_MIN_VALUE : integer := -(2**(G_SIGNAL_WIDTH - 1));
        
        variable v_table_sum_temp : signed(G_SIGNAL_WIDTH downto 0);
    begin
        if G_ENABLE_INTERPOLATION then
            -- step 1: determine the difference between current and next sinus sample
            -- this is used as the base value for the linear interpolation that is later scaled correctly
            p_table_diff <= p_table_next - p_table_out;
                
            -- step 2: linearly interpolate using the fractional phase component
            -- here we multiply the difference we calculated earlier by the current phase fractional part
            -- the output difference is one bit larger than both outputs
            p_table_interp <= (signed(p_table_diff) * signed('0' & p_phase_frac));
            p_table_out_delay <= p_table_out; -- we need a 1 cycle delay
            
            -- step 3: add output and interpolation
            -- here we add the linear interpolation vlaue to the table output (that we delayed once)
            -- result is one bit larger than the inputs so that we can avoid an overflow and correctly satturate later
            p_table_sum <= resize(p_table_out_delay, G_SIGNAL_WIDTH + 1) + resize(p_table_interp(G_SIGNAL_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto G_PHASE_FRACTIONAL_BITS), G_SIGNAL_WIDTH + 1);
            
            -- if the signal should be inverted then invert the signal
            if C_INVERT_SIGNAL then
                v_table_sum_temp := -p_table_sum;
            else
                v_table_sum_temp :=  p_table_sum;
            end if;
            
            -- step 4: saturate the counter at the minimum and maximum values
            -- in order to prevent overflows/underflows we need to clamp the output to the maximum and minimum value that can be represented by
            -- s_output_reg.
            p_output_reg <= resize(minimum(C_SIGNAL_MAX_VALUE, maximum(v_table_sum_temp, C_SIGNAL_MIN_VALUE)), G_SIGNAL_WIDTH); 
        else
            -- step 1: write table value to output register
            -- if we do not do any linear interpolation then there is no need to 
            p_output_reg <= s_table_out;
        end if;
    end procedure update_output_register;
begin
    
    proc_phase_counter : process(i_clk) is
    begin
        -- everyhint here is synchronous logic
        if rising_edge(i_clk) then
            
            -- active low reset
            if i_rst = '1' then
                -- counter register must always be reset
                s_phase_counter <= (others => '0');
                
                -- reset internal buffer registers
                s_phase_step <= (others => '0');
                
                -- these signals are only used if the signal interpolation is enabled
                if G_ENABLE_INTERPOLATION then
                    s_table_diff <= (others => '0');
                
                    s_table_interp <= (others => '0');
                    s_table_out_delay <= (others => '0');
                    
                    s_table_sum <= (others => '0');
                    
                    -- if we have a shifted output then we also need to reset its registers
                    if G_ENABLE_SHIFTED_OUTPUT then
                        s_table_diff_shifted <= (others => '0');
                
                        s_table_interp_shifted <= (others => '0');
                        s_table_out_delay_shifted <= (others => '0');
                    
                        s_table_sum_shifted <= (others => '0');
                    end if;
                    
                end if;
    
                -- reset output register
                s_output_reg <= (others => '0');
                
                -- reset shifted output register, if enabled!
                if G_ENABLE_SHIFTED_OUTPUT then
                    s_output_shifted_reg <= (others => '0');
                end if;
            else
                -- we support a synchonous clock enable so that a external prescaler can be used.
                if i_clk_en = '1' then
                    
                    -- step 0: load external signals into internal buffer registers
                    
                    s_phase_step <= unsigned(i_phase_step);
                    
                    -- step 1: increment phase counter
                    
                    -- resseting the counter is done via overflow
                    -- doing it this way (should?) allow us to exactly hit the frequency that we want
                    -- at least on average
                    s_phase_counter <= s_phase_counter + s_phase_step;
                    
                    -- step 2 to 5: generate wave form
                    
                    -- update non shifted output
                    update_output_register(
                        p_phase_frac => s_phase_frac, 
                        p_table_out => s_table_out, 
                        p_table_out_delay => s_table_out_delay, 
                        p_table_next => s_table_next, 
                        p_table_diff => s_table_diff, 
                        p_table_interp => s_table_interp, 
                        p_table_sum => s_table_sum, 
                        p_output_reg => s_output_reg,
                        C_INVERT_SIGNAL => G_INVERT_OUTPUT
                    );
                    
                    -- if the shifted output is enable, we also want to update it
                    if G_ENABLE_SHIFTED_OUTPUT then
                        update_output_register(
                            p_phase_frac => s_phase_frac, 
                            p_table_out => s_table_out_shifted, 
                            p_table_out_delay => s_table_out_delay_shifted, 
                            p_table_next => s_table_next_shifted, 
                            p_table_diff => s_table_diff_shifted, 
                            p_table_interp => s_table_interp_shifted, 
                            p_table_sum => s_table_sum_shifted, 
                            p_output_reg => s_output_shifted_reg,
                            C_INVERT_SIGNAL => G_INVERT_SHIFTED_OUTPUT
                        );
                    end if;
            
                end if; 
                               
            end if;
        end if;
    end process proc_phase_counter;
    
    -- extract correct fields from phase (integer + fractional part)
    -- this can always be done combinatorically 
    s_phase <= s_phase_counter(G_PHASE_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto G_PHASE_FRACTIONAL_BITS);
    s_phase_frac <= s_phase_counter(G_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    gen_shifted_phase_assign: if G_ENABLE_SHIFTED_OUTPUT generate
        -- contains the shifted phase counter, its offset by exactly pi/4 (90 deg)
        s_phase_shifted <= s_phase_counter(G_PHASE_WIDTH + G_PHASE_FRACTIONAL_BITS - 1 downto G_PHASE_FRACTIONAL_BITS) + 2**(G_PHASE_WIDTH - 2);
    end generate;
    
    -- fetch data from table
    -- this includes the current data and the next data
    s_table_out <= C_SIN_TABLE( to_integer(s_phase(G_PHASE_WIDTH - 1 downto 0) + 0) );    
    s_table_next <= C_SIN_TABLE( to_integer(s_phase(G_PHASE_WIDTH - 1 downto 0) + 1) ); 
    
    gen_shifted_phase_table: if G_ENABLE_SHIFTED_OUTPUT generate
        -- identical lookup to unshifted, phase, however it uses the shifter phase counter
        s_table_out_shifted <= C_SIN_TABLE( to_integer(s_phase_shifted(G_PHASE_WIDTH - 1 downto 0) + 0) );    
        s_table_next_shifted <= C_SIN_TABLE( to_integer(s_phase_shifted(G_PHASE_WIDTH - 1 downto 0) + 1) ); 
    end generate;
    
    -- assing registered output
    o_output <= std_logic_vector(s_output_reg);
    
    -- assign registered output (if shifted output is enabled, else output zero)
    gen_shifted_output : if G_ENABLE_SHIFTED_OUTPUT generate
        o_output_shifted <= std_logic_vector(s_output_shifted_reg);
    else generate
        o_output_shifted <= (others => '0');
    end generate;
    
end architecture behav;