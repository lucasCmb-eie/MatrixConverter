library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_Modulador_v1_0_M_AXIS_DIRECTS is
    generic (
        C_M_AXIS_TDATA_WIDTH    : integer    := 32;
        C_M_START_COUNT    : integer    := 32
    );
    port (
        -- User ports
        M_DIRECTS : in std_logic_vector(17 downto 0);
        M_BEGIN_Ts : in std_logic;  -- Data valid between falling and rising edge
        -- AXI Stream ports
        M_AXIS_ACLK    : in std_logic;
        M_AXIS_ARESETN    : in std_logic;
        M_AXIS_TVALID    : out std_logic;
        M_AXIS_TDATA    : out std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
        M_AXIS_TLAST    : out std_logic;
        M_AXIS_TREADY    : in std_logic
    );
end entity;

architecture implementation of AXI_Modulador_v1_0_M_AXIS_DIRECTS is
    signal axis_tvalid    : std_logic;
    signal axis_tvalid_delay : std_logic;
    signal ts_prev        : std_logic;  -- To detect edges
    signal transfer_active : std_logic;  -- Active during transfer period
    signal transfer_done  : std_logic;  -- Added to track successful transfers
begin
    -- Direct data assignment
    M_AXIS_TDATA(17 downto 0) <= M_DIRECTS;
    M_AXIS_TDATA(C_M_AXIS_TDATA_WIDTH-1 downto 18) <= (others => '0');
    
    -- Edge detection and transfer control
    process(M_AXIS_ACLK)
    begin
        if rising_edge(M_AXIS_ACLK) then
            if M_AXIS_ARESETN = '0' then
                axis_tvalid <= '0';
                axis_tvalid_delay <= '0';
                ts_prev <= '0';
                transfer_active <= '0';
                transfer_done <= '0';
            else
                ts_prev <= M_BEGIN_Ts;
                
                 -- Detect falling edge (start transfer)
                if M_BEGIN_Ts = '0' and ts_prev = '1' then
                    transfer_active <= '1';
                    transfer_done <= '0';
                -- Detect rising edge or successful transfer (end transfer)
                elsif (M_BEGIN_Ts = '1' and ts_prev = '0') or transfer_done = '1' then
                    transfer_active <= '0';
                end if;
                
                -- Control TVALID and track successful transfers
                if transfer_active = '1' then
                    axis_tvalid <= '1';
                    -- If receiver is ready, mark transfer as done
                    if M_AXIS_TREADY = '1' then
                        transfer_done <= '1';
                    end if;
                else
                    axis_tvalid <= '0';
                end if;
                axis_tvalid_delay <= axis_tvalid;
            end if;
        end if;
    end process;

    M_AXIS_TVALID <= axis_tvalid_delay;
    -- TLAST is asserted when we detect rising edge of Ts (end of transfer)
    M_AXIS_TLAST <= '1' when ((M_BEGIN_Ts = '1' and ts_prev = '0') or transfer_done = '1') else '0';

end implementation;
