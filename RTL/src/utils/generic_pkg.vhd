library ieee;

package generic_pkg is
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
