library ieee;

-- This package contains various generic utility methods that are used in some modules.
-- Most of these methods could be replaced with VHDL-2019 features but we use VHDL-2008.
package generic_pkg is
    
    -- This function provides IF/ELSE functionalities for the use in constants or generics.
    -- 
    -- Returns 'vTrue' if 'cond' is true and otherwise returns 'vFalse'.
    -- Integer version.
    function ReturnIf(cond : boolean ; vTrue : integer ; vFalse : integer) return integer;
    
end package generic_pkg;

package body generic_pkg is
 
    function ReturnIf(cond : boolean ; vTrue : integer ; vFalse : integer) return integer is
    begin
        if cond then
            return vTrue;
        else
            return vFalse;
        end if;
    end function ReturnIf;
    
end package body generic_pkg;
