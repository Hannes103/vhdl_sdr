library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

entity rf_reciever_register_bank is
    
    generic(
        G_ADDR_WIDTH : integer range 2 to 32 := 2;
        
        G_DATA_WIDTH : integer := 16;
        G_NCO_PHASE_WIDTH : integer := 10;
        G_NCO_PHASE_FRACTIONAL_BITS : integer := 11;
        
        G_PHASE_DETECTOR_COEF_WIDTH : integer := 8;
        G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS : integer := 10
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
        
        o_cfg_nco_frequency : out sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
        
        o_cfg_phase_detector_enable : out std_logic;
        o_cfg_phase_detector_mode : out std_logic;
        
        o_cfg_phase_detector_coef_A : out sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        o_cfg_phase_detector_coef_B : out sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        o_cfg_phase_detector_coef_C : out sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
        o_cfg_phase_detector_threshold : out sfixed(G_DATA_WIDTH - 1 downto 0);
        i_mon_phase_detector_nco_adj : in sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS)
    );
    
end entity rf_reciever_register_bank;

architecture behav of rf_reciever_register_bank is
    
    -- Constants that define the register offsets 
    constant C_OFFSET_REG_NCO_FREQ : integer := 4;
    
    constant C_OFFSET_REG_TRACKER_CR : integer := 8;
    constant C_OFFSET_REG_TRACKER_COEF_A : integer := 12;
    constant C_OFFSET_REG_TRACKER_COEF_B : integer := 16;
    constant C_OFFSET_REG_TRACKER_COEF_C : integer := 20;
    constant C_OFFSET_REG_TRACKER_THRESHOLD : integer := 24;
    constant C_OFFSET_REG_TRACKER_NCO_ADJ : integer := 28;
    
    -- Backing registers
    signal s_reg_nco_freq : sfixed(G_NCO_PHASE_WIDTH - 1 downto -G_NCO_PHASE_FRACTIONAL_BITS);
    
    signal s_reg_tracker_cr : std_logic_vector(1 downto 0);
        
    signal s_reg_tracker_coef_A : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_reg_tracker_coef_B : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_reg_tracker_coef_C : sfixed(G_PHASE_DETECTOR_COEF_WIDTH - 1 downto -G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS);
    signal s_reg_tracker_threshold : sfixed(G_DATA_WIDTH - 1 downto 0);
    
    -- Signals used by generic register bank
    
    signal s_drv_read_addr : unsigned(G_ADDR_WIDTH - 1 downto 0);
    signal s_drv_read_data : std_logic_vector(31 downto 0);
    signal s_drv_read_result : std_logic;
    signal s_drv_write_strobe : std_logic;
    signal s_drv_write_addr : unsigned(G_ADDR_WIDTH - 1 downto 0);
    signal s_drv_write_data : std_logic_vector(31 downto 0);
    signal s_drv_write_result : std_logic;
begin
    
    -- Generic register bank that handles the entire axi lite protocoll for us
    inst_generic_bank : entity work.generic_register_bank
        generic map(
            G_ADDR_WIDTH          => G_ADDR_WIDTH,
            G_REQUIRE_SECURE      => false,
            G_REQUIRE_PRIVILIEGED => false
        )
        port map(
            i_clk              => i_clk,
            i_rstn             => i_rstn,
            i_aw_addr          => i_aw_addr,
            i_aw_prot          => i_aw_prot,
            i_aw_valid         => i_aw_valid,
            o_aw_ready         => o_aw_ready,
            i_w_data           => i_w_data,
            i_w_valid          => i_w_valid,
            o_w_ready          => o_w_ready,
            i_w_strobe         => i_w_strobe,
            o_b_resp           => o_b_resp,
            o_b_valid          => o_b_valid,
            i_b_ready          => i_b_ready,
            i_ar_addr          => i_ar_addr,
            i_ar_prot          => i_ar_prot,
            i_ar_valid         => i_ar_valid,
            o_ar_ready         => o_ar_ready,
            o_r_data           => o_r_data,
            o_r_resp           => o_r_resp,
            o_r_valid          => o_r_valid,
            i_r_ready          => i_r_ready,
            o_drv_read_addr    => s_drv_read_addr,
            i_drv_read_data    => s_drv_read_data,
            i_drv_read_result  => s_drv_read_result,
            o_drv_write_strobe => s_drv_write_strobe,
            o_drv_write_addr   => s_drv_write_addr,
            o_drv_write_data   => s_drv_write_data,
            i_drv_write_result => s_drv_write_result
        );
    
    proc_read_register : process(
        s_drv_read_addr, 
        i_mon_phase_detector_nco_adj,
         s_reg_nco_freq, s_reg_tracker_coef_A, s_reg_tracker_coef_B, s_reg_tracker_coef_C, s_reg_tracker_cr, s_reg_tracker_threshold 
    ) is
    begin
        case to_integer(s_drv_read_addr) is
            
            -- read from NCO frequency register
            when C_OFFSET_REG_NCO_FREQ =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_NCO_PHASE_WIDTH + G_NCO_PHASE_FRACTIONAL_BITS -1 downto 0) <= to_slv(s_reg_nco_freq);
                
            -- read from tracker control register
            when C_OFFSET_REG_TRACKER_CR =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(s_reg_tracker_cr'left downto 0) <= s_reg_tracker_cr;   
               
            -- read from tracker coefficient register A 
            when C_OFFSET_REG_TRACKER_COEF_A =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0) <= to_slv(s_reg_tracker_coef_A);  
                
            -- read from tracker coefficient register A 
            when C_OFFSET_REG_TRACKER_COEF_B =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0) <= to_slv(s_reg_tracker_coef_B);
                
            -- read from tracker coefficient register A 
            when C_OFFSET_REG_TRACKER_COEF_C =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0) <= to_slv(s_reg_tracker_coef_C);
                
            -- read from tracker threshold register
            when C_OFFSET_REG_TRACKER_THRESHOLD =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_DATA_WIDTH -1 downto 0) <= to_slv(s_reg_tracker_threshold);
                
            when C_OFFSET_REG_TRACKER_NCO_ADJ =>
                s_drv_read_result <= '1';
                s_drv_read_data <= 32x"0";
                s_drv_read_data(G_NCO_PHASE_WIDTH + G_NCO_PHASE_FRACTIONAL_BITS -1 downto 0) <= to_slv(i_mon_phase_detector_nco_adj);  
            
            -- any other register failes read!
            when others =>
                s_drv_read_result <= '0';
                s_drv_read_data <= (others => '-');
        end case;
            
    end process proc_read_register;
    
    proc_write_register : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rstn = '0' then
                s_drv_write_result <= '0';
                
                s_reg_nco_freq <= to_sfixed(0, s_reg_nco_freq);
                
                s_reg_tracker_cr <= (others => '0');
                s_reg_tracker_coef_A <= to_sfixed(0, s_reg_tracker_coef_A);
                s_reg_tracker_coef_B <= to_sfixed(0, s_reg_tracker_coef_B);
                s_reg_tracker_coef_C <= to_sfixed(0, s_reg_tracker_coef_C);                
                
            elsif s_drv_write_strobe = '1' then
                case to_integer(s_drv_write_addr) is
                    
                    -- write to NCO frequency register
                    when C_OFFSET_REG_NCO_FREQ =>
                        s_drv_write_result <= '1';
                        s_reg_nco_freq <= to_sfixed(s_drv_write_data(G_NCO_PHASE_WIDTH + G_NCO_PHASE_FRACTIONAL_BITS -1 downto 0), s_reg_nco_freq);

                    -- write to tracker control register
                    when C_OFFSET_REG_TRACKER_CR =>
                        s_drv_write_result <= '1';
                        s_reg_tracker_cr <= s_drv_write_data(1 downto 0);

                    -- write to tracker coefficient register A
                    when C_OFFSET_REG_TRACKER_COEF_A =>
                        s_drv_write_result <= '1';
                        s_reg_tracker_coef_A <= to_sfixed(
                            s_drv_write_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0), s_reg_tracker_coef_A
                        );
                        
                    -- write to tracker coefficient register B
                    when C_OFFSET_REG_TRACKER_COEF_B =>
                        s_drv_write_result <= '1';
                        s_reg_tracker_coef_B <= to_sfixed(
                            s_drv_write_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0), s_reg_tracker_coef_B
                        );
                    
                    -- write to tracker coefficient register A
                    when C_OFFSET_REG_TRACKER_COEF_C =>
                        s_drv_write_result <= '1';
                        s_reg_tracker_coef_C <= to_sfixed(
                            s_drv_write_data(G_PHASE_DETECTOR_COEF_WIDTH + G_PHASE_DETECTOR_COEF_FRACTIONAL_BITS -1 downto 0), s_reg_tracker_coef_C
                        );
                        
                    -- write to tracker threshold register
                    when C_OFFSET_REG_TRACKER_THRESHOLD =>
                        s_drv_write_result <= '1';
                        s_reg_tracker_threshold <= to_sfixed(
                            s_drv_write_data(G_DATA_WIDTH -1 downto 0), s_reg_tracker_threshold
                        );
                        
                    -- write to unknown registern
                    when others =>
                        s_drv_write_result <= '0';
                        
                end case;  
            end if;
        end if;
    end process proc_write_register;
    
    -- Assignment of external control signals for ADC from the register values
    o_cfg_nco_frequency <= s_reg_nco_freq;
    
    o_cfg_phase_detector_enable <= s_reg_tracker_cr(0);
    o_cfg_phase_detector_mode <= s_reg_tracker_cr(1);
    
    o_cfg_phase_detector_coef_A <= s_reg_tracker_coef_A;
    o_cfg_phase_detector_coef_B <= s_reg_tracker_coef_B;
    o_cfg_phase_detector_coef_C <= s_reg_tracker_coef_C;
    
end architecture behav;