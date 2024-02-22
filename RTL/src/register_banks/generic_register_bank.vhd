library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This entity provides a relativly simple conversion mechanism from AXI-lite to a simpler bus mechansim that can 
-- be used to implement register banks.
--
-- For read accesses a combinatorical interface is exposed that is supposed to be implemented via address decoding.
-- For write accesses a single cycle strobe signal interface is exposed that can be used as a clock enable. 
--
-- It supports filtering of not secure or not privileged transactions. This can be configured via generics.
entity generic_register_bank is
    generic(
        -- Specifies the width of the address bus used for write and read transactions.
        -- Because only word accesses are supported, the minmum number of address bits is two.
        G_ADDR_WIDTH          : integer range 2 to 32 := 2;
        
        -- If set to true then only secure (AxPROT(1) = 0) read and write transactions are allowed.
        -- All not secure transactions will be aborted (via a SLVERR) and no data will be written or returned.
        --
        -- If set to false then any accesses are allowed.
        G_REQUIRE_SECURE      : boolean := false;
        
        -- If set to true then only privileged (AxPROT(0) = 1) read and write transactions are allowed.
        -- All not provileged transactions will be aborted (via a SLVERR) and no data will be written or returned.
        --
        -- If set to false then any accesses are allowed.
        G_REQUIRE_PRIVILIEGED : boolean := false
    );
    port(
        -- Global AXI-Lite signals

        i_clk     : in std_logic;
        i_rstn    : in std_logic;

        -- AXI-Lite write address channel

        i_aw_addr  : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        i_aw_prot  : in std_logic_vector(2 downto 0);
        i_aw_valid : in std_logic;
        o_aw_ready : out std_logic;

        -- AXI-Lite write data channel

        i_w_data   : in std_logic_vector(31 downto 0);
        i_w_valid  : in std_logic;
        o_w_ready  : out std_logic;
        i_w_strobe : in std_logic_vector(3 downto 0); -- @suppress "Unused port: i_w_strobe is not used in src.generic_register_bank(behav)"

        -- AXI-Lite write response channel

        o_b_resp     : out std_logic_vector(1 downto 0);
        o_b_valid    : out std_logic;
        i_b_ready    : in std_logic;

        -- AXI-Lite read address channel

        i_ar_addr  : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        i_ar_prot  : in std_logic_vector(2 downto 0);
        i_ar_valid : in std_logic;
        o_ar_ready : out std_logic;

        -- AXI-Lite read response/data channel

        o_r_data  : out std_logic_vector(31 downto 0);
        o_r_resp  : out std_logic_vector(1 downto 0);
        o_r_valid : out std_logic;
        i_r_ready : in std_logic;
        
        -- Register driver read signals
        
        -- Read transaction address.
        -- Changes every time a new read transaction is recieved.
        --
        -- Its supposed to drive combinatoricall logic that generates the
        -- i_drv_read_data and i_drv_read_result signals.
        o_drv_read_addr : out unsigned(G_ADDR_WIDTH - 1 downto 0);
        
        -- Read transaction data. Will be returned to axi lite master.
        --
        -- Should be generated combinatorically from the read transaction address and must be valid on the next clock
        -- cycle after the read address has changed.
        i_drv_read_data : in std_logic_vector(31 downto 0);
        
        -- Read opeation result. 
        -- Speicifes whether the read was to a known register and successfull ('1') or to a unknown register
        -- and not successfull ('0'). Is used to generate the axi read transaction response (rresp).
        --
        -- Should be generated combinatorically from the read transaction address and must be valid on the next clock
        -- cycle after the read address has changed.
        i_drv_read_result : in std_logic;
            
        -- Register driver write signals
            
        o_drv_write_strobe : out std_logic;
        o_drv_write_addr : out unsigned(G_ADDR_WIDTH - 1 downto 0);
        o_drv_write_data : out std_logic_vector(31 downto 0);
        i_drv_write_result : in std_logic
    );
end entity generic_register_bank;

-- This architecture contains the behavioural specification that implements the
-- generic_register_bank entity.
architecture behav of generic_register_bank is
    
    -- Verifies that provided AxPROT value has the access values required by the generic
    -- configuration. Always required is that the module is accessed as data.
    -- Depending on the configuration a secure or privileged access required.
    --
    -- Argument: prot : std_logic_vector 
    --   Value provided to the AxPROT port of an AXI lite address channel.
    --
    -- Returns: true if the provided access flags satisfy the configured requirements.
    function IsAccessValid(prot : std_logic_vector) return boolean is
    begin
        -- if we have a instruction access its invalid
        if prot(2) = '1' then
            return false;
        end if;
        
        -- if we have a unsecure access but we require one then its invalid
        if prot(1) = '1' and G_REQUIRE_SECURE then
            return false;
        end if;
        
        -- if we have a unprivileged access but we require one then its invalid
        if prot(0) = '0' and G_REQUIRE_PRIVILIEGED then
            return false;
        end if;
        
        -- all requirements satisfied, so we can return true
        return true;
    end function IsAccessValid;
    
    -- Signals for read process
    
    signal s_ar_addr : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal s_ar_prot : std_logic_vector(2 downto 0);
    
    signal s_r_valid : std_logic;
    signal s_r_data : std_logic_vector(31 downto 0);
    signal s_r_resp : std_logic_vector(1 downto 0);

    signal s_read_wait_for_driver : std_logic;
    
    -- Signals for write process
    
    signal s_aw_ready : std_logic;  
    signal s_aw_addr  : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal s_aw_prot  : std_logic_vector(2 downto 0);
    
    signal s_w_ready  : std_logic;  
    signal s_w_data : std_logic_vector(31 downto 0);
    
    signal s_b_resp   : std_logic_vector(1 downto 0);
    signal s_b_valid  : std_logic;
    
    signal s_write_wait_for_driver : std_logic;
    
begin
    
    o_aw_ready <= s_aw_ready;
    
    o_w_ready <= s_w_ready;
    
    o_b_resp  <= s_b_resp;
    o_b_valid <= s_b_valid;
    
    -- the register driver should only get a single cycle strobe signal it can used as clock enable to
    -- write the valid data to the backing registers.
    -- s_w_ready and s_aw_ready are only ever low together for once cycle so this works great.
    -- However we also want to prevent the strobe signal from being generated if the provided access indicators are not
    -- what we expect.
    o_drv_write_strobe <= '1' when s_w_ready = '0' and s_aw_ready = '0' and IsAccessValid(s_aw_prot) else '0';
    
    o_drv_write_addr <= unsigned(s_aw_addr);
    o_drv_write_data <= s_w_data;
    
    -- This process implements the synchronous logic required for AXI-lite write transactions.
    -- It manages the write address, data and response channels.
    --
    -- A single cycle wait state is included as to allow the register driver to write the data.
    -- A full AXI transaction takes 5 clock cycles. Total troughput should be about 33%. 
    proc_write : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rstn = '0' then
                s_aw_ready <= '1';
                s_aw_addr <= (others => '0');
                s_aw_prot <= (others => '0');
                
                s_w_ready <= '1';
                s_w_data <= (others => '0');
                
                s_b_resp <= "00";
                s_b_valid <= '0';
                
                s_write_wait_for_driver <= '0';
            else
                
                -- we have valid data on the write address bus
                if i_aw_valid = '1' and s_aw_ready = '1' then
                    s_aw_addr <= i_aw_addr;
                    s_aw_prot <= i_aw_prot;
                    s_aw_ready <= '0';
                end if;
                
                -- we have valid data on the write data bus
                if i_w_valid = '1' and s_w_ready = '1' then
                    s_w_ready <= '0';
                    s_w_data <= i_w_data;
                end if;
                
                -- now that we have a valid address and valid write data we wait for the register driver to response
                if s_aw_ready = '0' and s_w_ready = '0' then
                    -- this signal is simply used to delay the write response logic by one cycle
                    s_write_wait_for_driver <= '1';
                    
                    -- we are ready to now once again accept new data from the master
                    s_aw_ready <= '1';
                    s_w_ready <= '1';                
                end if;
                
                -- using the "s_write_wait_for_driver" signal we wait for one clock cycle 
                -- to give the register driver one clock cycle time to write the data to the backing registers and to
                -- provide us an response whether the register written to is valid.
                if s_write_wait_for_driver = '1' then
                    if s_b_valid = '0' then
                        -- we do not yet have valid data on the write response channel
                        -- we we can write some
                        s_b_valid <= '1';
                        
                        if i_drv_write_result = '1' and IsAccessValid(s_aw_prot) then
                            s_b_resp <= "00"; -- OKAY
                        else
                            s_b_resp <= "10"; -- SLVERR
                        end if;
                        
                        s_write_wait_for_driver <= '0';
                    end if;
                end if; 
                
                -- we have some valid data on the write response channel and have completed a handshake    
                if i_b_ready = '1' and s_b_valid = '1' then
                    s_b_valid <= '0';  
                end if;
                               
            end if;
        end if;
    end process proc_write;
     
    -- we are always read to read, unless we are currently waiting for a response from the register driver
    o_ar_ready <= not s_read_wait_for_driver;
    o_r_valid  <= s_r_valid;
    o_r_data   <= s_r_data;
    o_r_resp   <= s_r_resp;
    
    o_drv_read_addr <= unsigned(s_ar_addr);
    
    -- This process implements the synchronous logic required for AXI-lite read transactions.
    -- It manages the read address and data channels.
    --
    -- A single cycle wait state is included as to allow the register driver to respond with data.
    -- A full AXI transaction takes 3 clock cycles. Total troughput should be about 33%. 
    proc_read : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rstn = '0' then
                s_ar_addr <= (others => '0');
                s_ar_prot <= "000";

                s_r_valid <= '0';
                s_r_data <= (others => '0');
                s_r_resp <= (others => '0');
                    
                s_read_wait_for_driver <= '0';
            else
                -- read transaction is complete if both rvalid and rready are high
                if( s_r_valid = '1' and i_r_ready = '1' ) then
                    s_r_valid <= '0';
                end if;
        
                -- input address is valid an there is no outstanding transaction
                if i_ar_valid = '1' and s_read_wait_for_driver = '0' then
                    s_read_wait_for_driver <= '1';
                    s_ar_addr <= i_ar_addr;
                    s_ar_prot <= i_ar_prot;
                end if;
                
                -- the s_read_wait_for_driver signal is used to delay the processing of the read address handshake for one clock cycle
                -- give the register driver the chance to provide us with the correct data.
                if s_read_wait_for_driver = '1' and i_r_ready = '1' then
                    s_read_wait_for_driver <= '0';
                        
                    -- if the correct access rights are presented then we output the result
                    -- with an OKAY status otherwise output zero with SLVERR.
                    if i_drv_read_result = '1' and IsAccessValid(s_ar_prot) then
                        s_r_data <= i_drv_read_data;
                        s_r_resp <= "00"; -- OKAY
                    else
                         s_r_data <= (others => '0');
                         s_r_resp <= "10"; -- SLVERR
                    end if;
                    
                    s_r_valid <= '1';
                 end if;
                
            end if;     
        end if;
    end process proc_read;


end architecture behav;
