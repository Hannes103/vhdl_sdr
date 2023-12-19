library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package dds_generator_pgk is
    type t_sin_lut is array(natural range <>) of signed;
    
    type t_signed_array is array(natural range <>) of signed;
    type t_unsigned_array is array(natural range <>) of unsigned;
    
    function init_sin_lut(phase_width : integer; signal_width : integer) return t_sin_lut;
        
    function to_phase_increment(phase_width : integer; phase_fractional_bits : integer; value : real) return std_logic_vector;
    function to_phase_increment(phase_width : integer; phase_fractional_bits : integer; clk_freq : real; target_freq : real) return std_logic_vector;
end package dds_generator_pgk;

package body dds_generator_pgk is
    
    function init_sin_lut(phase_width : integer; signal_width : integer) return t_sin_lut is
        variable result : t_sin_lut(2**(phase_width) - 1 downto 0)(signal_width - 1 downto 0);
        
        -- length of the sin lookup table the number of different phase values
        constant C_LENGTH : integer := 2**(phase_width);
        
        -- maximum value of a signed integer with <signal_width> bits.
        constant C_MAX_DATA : integer := 2**(signal_width - 1) - 1;
        
        variable value : real;
    begin
        for i in 0 to C_LENGTH - 1 loop
            -- generate the sinus
            value := round(real(C_MAX_DATA) * sin( (MATH_2_PI / real(C_LENGTH)) * real(i) ));
            
            -- convert value to signal stored in table
            result(i) := to_signed(integer(value), signal_width);
        end loop;
        
        return result;
    end function init_sin_lut;
    
    function to_phase_increment(phase_width : integer; phase_fractional_bits : integer; clk_freq : real; target_freq : real) return std_logic_vector is
        variable base_freq : real;
    begin
        base_freq := clk_freq / 2.0**real(phase_width); 
        
        return to_phase_increment(phase_width, phase_fractional_bits, target_freq/base_freq);
        
    end function to_phase_increment;
    
    function to_phase_increment(phase_width : integer; phase_fractional_bits : integer; value : real) return std_logic_vector is
        variable result : std_logic_vector(phase_width + phase_fractional_bits - 1 downto 0);
        variable frac : real;
    begin        
        -- assign integer phase divider
        result(phase_width + phase_fractional_bits - 1 downto phase_fractional_bits) := std_logic_vector( to_unsigned(integer(floor(value)), phase_width) );
        
        -- calculate fractional part
        frac := value - floor(value);
        frac := frac * (2.0 ** phase_fractional_bits);
        
        report "FRAC: " & to_string(frac);
        
        -- assign fractional part
        result(phase_fractional_bits - 1 downto 0) := std_logic_vector( to_unsigned(integer(round(frac)), phase_fractional_bits) );
        
        return result;
    end function to_phase_increment;
    
end package body dds_generator_pgk;
