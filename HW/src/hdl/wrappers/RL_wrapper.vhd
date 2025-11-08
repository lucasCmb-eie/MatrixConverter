library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.fixed_pkg.all;

entity RL_wrapper is
    generic (
        INT_BITS    : integer := 8;
        FRAC_BITS   : integer := 24
    );
    port (
        -- Señales de control
        i_clk     : in  std_logic;
        i_rst   : in  std_logic; -- Reset asíncrono activo a nivel bajo

        o_Enable : out std_logic;

        -- Coeficientes del filtro (entradas configurables)
        i_c_a0    : in  std_logic_vector(INT_BITS -1 + FRAC_BITS downto 0);
        i_c_a1    : in  std_logic_vector(INT_BITS -1 + FRAC_BITS downto 0);
        i_c_b1    : in  std_logic_vector(INT_BITS -1 + FRAC_BITS downto 0);

        -- Puertos de datos
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_Iu : out std_logic_vector(31 downto 0);
        o_Iv : out std_logic_vector(31 downto 0);
        o_Iw : out std_logic_vector(31 downto 0)
     );
end RL_wrapper;

architecture Behavioral of RL_wrapper is

    signal tick_enable : std_logic;
    signal w_oU : sfixed(INT_BITS-1 downto -FRAC_BITS);
    signal w_oV : sfixed(INT_BITS-1 downto -FRAC_BITS);
    signal w_oW : sfixed(INT_BITS-1 downto -FRAC_BITS);

begin

    -- Generador de enable cada 64 µs
    U_EnableGen : entity work.EnableGen
        generic map (
            CLK_FREQ_HZ => 100000000,
            TCONV_US    => 16     -- Tconv = 16 µs
        )
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,
            o_tick => tick_enable
        );
    o_Enable <= tick_enable;

    RL_U : entity work.RL_fase
        generic map (INT_BITS => INT_BITS, FRAC_BITS => FRAC_BITS)
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_enable => tick_enable,
            i_c_a0 => to_sfixed(i_c_a0, 7, -24),
            i_c_a1 => to_sfixed(i_c_a1, 7, -24),
            i_c_b1 => to_sfixed(i_c_b1, 7, -24),
            i_U => to_sfixed(i_U, 7, -24),
            o_I => w_oU
        );

    RL_V : entity work.RL_fase
        generic map (INT_BITS => INT_BITS, FRAC_BITS => FRAC_BITS)
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_enable => tick_enable,
            i_c_a0 => to_sfixed(i_c_a0, 7, -24),
            i_c_a1 => to_sfixed(i_c_a1, 7, -24),
            i_c_b1 => to_sfixed(i_c_b1, 7, -24),
            i_U => to_sfixed(i_V, 7, -24),
            o_I => w_oV
        );

    RL_W : entity work.RL_fase
        generic map (INT_BITS => INT_BITS, FRAC_BITS => FRAC_BITS)
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_enable => tick_enable,
            i_c_a0 => to_sfixed(i_c_a0, 7, -24),
            i_c_a1 => to_sfixed(i_c_a1, 7, -24),
            i_c_b1 => to_sfixed(i_c_b1, 7, -24),
            i_U => to_sfixed(i_W, 7, -24),
            o_I => w_oW
        );

    o_Iu <= to_slv(w_oU);
    o_Iv <= to_slv(w_oV);
    o_Iw <= to_slv(w_oW);

    -- RL_core : entity work.RL
    --     generic map (
    --         INT_BITS  => INT_BITS,
    --         FRAC_BITS => FRAC_BITS
    --     )
    --     port map (
    --         i_clk   => i_clk,
    --         i_rst   => i_rst,
    --         i_enable => tick_enable,
    --         i_c_a0  => to_sfixed(i_c_a0, INT_BITS-1, -FRAC_BITS),
    --         i_c_a1  => to_sfixed(i_c_a1, INT_BITS-1, -FRAC_BITS),
    --         i_c_b1  => to_sfixed(i_c_b1, INT_BITS-1, -FRAC_BITS),
    --         i_U => i_U,
    --         i_V => i_V,
    --         i_W => i_W,

    --         o_Iu => o_Iu,
    --         o_Iv => o_Iv,
    --         o_Iw => o_Iw
    --     );

end Behavioral;
