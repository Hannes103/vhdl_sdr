library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;


entity costas_loop is
    generic(
        G_INPUT_DATA_WIDTH : integer := 16;
        G_INPUT_FRACTIONAL_BITS : integer := 0;
        
        G_CARRIER_PHASE_WIDTH : integer := 11;
        G_CARRIER_PHASE_FRACTIONAL_BITS : integer := 10;
        
        G_MODULATION_TYPE : string := "QAM-4"
    );
    port(
        i_clk : in std_logic;
        i_rst : in std_logic;
        
        i_cfg_target_frequency : in std_logic_vector(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);               
        i_cfg_enable_threshold : in sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        
        i_data_valid : in std_logic;
        i_data_i : in sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        i_data_q : in sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        
        o_error_unfiltered : out sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
        
        o_phase_step : out std_logic_vector(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0)
    );
end entity costas_loop;

architecture behav of costas_loop is
    constant C_MODULATION_QAM4 : string := "QAM-4";
    constant C_MODULATION_BKSP : string := "BPSK";
    
    constant C_CORRECTION_I_MAX : integer := 2**(G_CARRIER_PHASE_FRACTIONAL_BITS + 1) - 1;
    
    -- I/Q data registers
    
    signal s_data_i_raw  : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_data_i_mult : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    
    signal s_data_q_raw  : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_data_q_mult : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    
    -- Configuration registers
    
    signal s_cfg_enable_threshold : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    signal s_cfg_target_frequency : unsigned(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
    
    -- Internal control signals
    
    signal s_enable_controller : std_logic;
    
    -- Controller signals
    
    signal s_error_unfiltered : sfixed(G_INPUT_DATA_WIDTH - 1 downto -G_INPUT_FRACTIONAL_BITS);
    
    signal s_correction_P : signed(G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
    signal s_correction_I : signed(G_CARRIER_PHASE_FRACTIONAL_BITS + 2 downto 0);
    
    -- Output signals
    
    signal s_phase_step : unsigned(G_CARRIER_PHASE_WIDTH + G_CARRIER_PHASE_FRACTIONAL_BITS - 1 downto 0);
begin

    proc_controller : process(i_clk) is
        variable s_correction_i_temp : signed(G_CARRIER_PHASE_FRACTIONAL_BITS + 3 downto 0);
    begin
        
        if rising_edge(i_clk) then
            
            if i_rst = '1' then
                -- reset all 
                s_cfg_target_frequency <= to_unsigned(0, s_cfg_target_frequency);
                
                s_correction_P <= to_signed(0, s_correction_P);
                s_correction_I <= to_signed(0, s_correction_I);
                
                s_phase_step <= to_unsigned(0, s_phase_step);
            else

                -- use data valid as clock enable
                if i_data_valid <= '1' then
                    s_cfg_target_frequency <= unsigned(i_cfg_target_frequency);
                
                    -- only update the frequency correction if we have a valid input signal.
                    if s_enable_controller = '1' then
                        
                        -- P-controller
                        s_correction_P <= -to_signed( s_error_unfiltered / 256, s_correction_P);
                        
                        -- I-controller
                        -- integrator is satturating, as to not overflow.
                        
                        s_correction_i_temp := s_correction_I - to_signed( s_error_unfiltered, s_correction_i_temp) / 512;
                        if s_correction_i_temp >= C_CORRECTION_I_MAX then
                            s_correction_i_temp := to_signed(C_CORRECTION_I_MAX, s_correction_i_temp);
                        elsif s_correction_i_temp <= -C_CORRECTION_I_MAX then
                            s_correction_i_temp := to_signed(-C_CORRECTION_I_MAX, s_correction_i_temp);
                        end if;
                        
                        s_correction_I <= resize(s_correction_i_temp, s_correction_I);
                        
                    end if;
                    -- calculate output phase step
                    -- s_phase_step = s_traget_frequency + frequency_correction 
                    s_phase_step <= unsigned(signed(s_cfg_target_frequency) + s_correction_P + s_correction_I / 64);
                end if;
            end if;
            
        end if;
        
    end process proc_controller;
    
    o_phase_step <= std_logic_vector(s_phase_step);

    o_error_unfiltered <= s_error_unfiltered;

    proc_calculate_error : process(i_clk) is
        
    begin
        -- synchronous logic
        if rising_edge(i_clk) then
            
            if i_rst = '1' then
                -- reset logic
                s_data_i_raw <= to_sfixed(0, s_data_i_raw);
                s_data_q_raw <= to_sfixed(0, s_data_q_raw);
                
                s_cfg_enable_threshold <= to_sfixed(0, s_cfg_enable_threshold);
                
                -- registers are only used for QAM-4 modulation type.
                if G_MODULATION_TYPE = C_MODULATION_QAM4 then
                    s_data_i_mult <= to_sfixed(0, s_data_i_mult);
                    s_data_q_mult <= to_sfixed(0, s_data_q_mult);
                end if;
                
                s_error_unfiltered <= to_sfixed(0, s_error_unfiltered);  
            else
                s_cfg_enable_threshold <= i_cfg_enable_threshold;
                
                -- use data valid as clock enable signal
                if i_data_valid <= '1' then
                    s_data_i_raw <= i_data_i;
                    s_data_q_raw <= i_data_q;
                    
                    -- caculate error depending on the selected modulation
                    if G_MODULATION_TYPE = C_MODULATION_QAM4 then                                            
                        
                        -- s_data_i_mult = sign(s_data_q_raw) * s_data_i_raw;
                        if( s_data_q_raw < 0 ) then
                            s_data_i_mult <= resize(-s_data_i_raw, s_data_i_mult);
                        else
                            s_data_i_mult <= s_data_i_raw;
                        end if;
                        
                        -- s_data_q_mult = sign(s_data_i_raw) * s_data_q_raw;
                        if( s_data_i_raw < 0 ) then
                            s_data_q_mult <= resize(-s_data_q_raw, s_data_q_mult);
                        else
                            s_data_q_mult <= s_data_q_raw;
                        end if;
                        
                        -- calculate error
                        s_error_unfiltered <= resize(s_data_i_mult - s_data_q_mult, s_error_unfiltered);
                    
                    elsif G_MODULATION_TYPE = C_MODULATION_BKSP then  
                        
                        -- only thing we need to do is multply both input values
                        
                        -- TODO: maybe use additional register to allow better DSP slice pipelining?
                        -- TODO: this is pretty crap, because it instantly satturates, needs improvement very much1
                        s_error_unfiltered <= resize(s_data_i_raw * s_data_q_raw, s_error_unfiltered);
                        
                    else
                        report "Unknown or not supported modulation type: " & G_MODULATION_TYPE  severity error;                     
                    end if;
                    
                    -- if the input data is above the configured threshold then we enable the controller
                    -- otherwise we do nothing
                    if (abs(s_data_i_raw) > s_cfg_enable_threshold) and (abs(s_data_i_raw) > s_cfg_enable_threshold) then
                        s_enable_controller <= '1';
                    else
                        s_enable_controller <= '0';
                    end if;
                    
                end if;
            end if;
        end if;
    end process proc_calculate_error;

end architecture behav;
