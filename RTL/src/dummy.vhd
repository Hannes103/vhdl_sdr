library ieee;

use ieee.std_logic_1164.all;

entity dummy is
    
    port(
        a : in std_logic;
        b : in std_logic;
        c : in std_logic;
        d : in std_logic;
        y : out std_logic
    );
    
end entity dummy;

architecture behav of dummy is
begin
    
    -- implement logic function as specified in problem sheet
    y <= ((a and b) or c) and (not d);
    
end architecture behav;