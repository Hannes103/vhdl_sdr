library ieee;

use ieee.std_logic_1164.all;
use ieee.fixed_pkg.all;

entity pid_simple is
    generic(
        G_DATA_WIDTH           : integer := 16;
        G_DATA_FRACTIONAL_BITS : integer := 0;
        
        G_COEF_WIDTH           : integer := 4;
        G_COEF_FRACTIONAL_BITS : integer := 0
    );
    port(
        signal i_clk : in std_logic;
        signal i_rst : in std_logic;
        
        signal i_input : in sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
        signal i_input_valid : in std_logic;
        
        signal o_output : out sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
        signal o_output_valid : out std_logic;
        
        signal i_cfg_coef_A : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
        signal i_cfg_coef_B : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
        signal i_cfg_coef_C : in sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS)
    );
end entity pid_simple;

architecture behav of pid_simple is
    type t_input_storage is array (natural range <>) of sfixed(G_DATA_WIDTH - 1 downto -G_DATA_FRACTIONAL_BITS);
    type t_temp_storage is array (natural range <>) of sfixed(G_DATA_WIDTH + G_COEF_WIDTH - 1 downto -(G_DATA_FRACTIONAL_BITS + G_COEF_FRACTIONAL_BITS));
    type t_processing_state is (WAIT_FOR_INPUT, MULTIPLY, ADD, OUTPUT);
    
    signal s_processing_state : t_processing_state;
    
    signal s_cfg_coef_A : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_B : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
    signal s_cfg_coef_C : sfixed(G_COEF_WIDTH - 1 downto -G_COEF_FRACTIONAL_BITS);
    
    signal s_data : t_input_storage(2 downto 0);
    signal s_temp : t_temp_storage(2 downto 0);
    signal s_result : t_input_storage(2 downto 0);
    
    signal s_output_valid : std_logic;
begin
    
    proc_controller : process(i_clk) is
    begin
        
        if rising_edge(i_clk) then
            
            -- reset output valid strobe
            s_output_valid <= '0';
            
            if i_rst = '1' then
                -- reset data registers
                s_data   <= ( others => to_sfixed(0, s_data(0)) );
                s_temp   <= ( others => to_sfixed(0, s_temp(0)) );
                s_result <= ( others => to_sfixed(0, s_result(0)) );
                
                s_cfg_coef_A <= to_sfixed(0, s_cfg_coef_A);
                s_cfg_coef_B <= to_sfixed(0, s_cfg_coef_B);
                s_cfg_coef_C <= to_sfixed(0, s_cfg_coef_C);
                
            else
                     
                case s_processing_state is            
                    when WAIT_FOR_INPUT =>
                        -- wait until we have an input and latch all inputs
                        if i_input_valid <= '1' then
                            -- shift input chain
                            s_data(0) <= i_input;
                            s_data(1) <= s_data(0);
                            s_data(2) <= s_data(1);
                            
                            -- shift output chain
                            s_result(1) <= s_result(0);
                            s_result(2) <= s_result(1);
                            
                            -- latch coefficients
                            s_cfg_coef_A <= i_cfg_coef_A;
                            s_cfg_coef_B <= i_cfg_coef_B;
                            s_cfg_coef_C <= i_cfg_coef_C;
                            
                            s_processing_state <= MULTIPLY;
                        else
                            s_processing_state <= WAIT_FOR_INPUT;
                        end if;
                        
                    when MULTIPLY =>
                        -- multiply all old input values by the respective values
                        s_temp(0) <= s_data(0) * s_cfg_coef_A;
                        s_temp(1) <= s_data(1) * s_cfg_coef_B;
                        s_temp(2) <= s_data(2) * s_cfg_coef_C;
                        
                        s_processing_state <= ADD;
                        
                    when ADD =>
                        s_temp(0) <= resize(s_temp(0) + s_temp(1), s_temp(0));
                        s_temp(1) <= resize(s_temp(2) + s_result(2), s_temp(1));
                
                        s_processing_state <= OUTPUT;
                    
                    when OUTPUT =>                     
                        s_result(0) <= resize(s_temp(0) + s_temp(1), s_result(0));
                        s_output_valid <= '1';
                        
                        s_processing_state <= WAIT_FOR_INPUT;
                
                end case;    
            end if;        
        end if;
        
    end process proc_controller;
    
    o_output <= resize(s_result(0), o_output);
    
    o_output_valid <= s_output_valid;
    
end architecture behav;