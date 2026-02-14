library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.fixed_pkg.all;

entity TransformadaClark is
generic (
        INT_BITS  : integer := 8;
        FRAC_BITS : integer := 24
    );
port (
    i_clk : in std_logic;
    i_rst : in std_logic;

    --Inicio de calculo
    i_start : in std_logic;

    -- Entradas de tensiones trifasicas (U, V ,W)
    i_U : in std_logic_vector (31 downto 0);
    i_V : in std_logic_vector (31 downto 0);
    i_W : in std_logic_vector (31 downto 0);

    -- Salida Calculo terminado
    o_valido : out std_logic;

    -- Salidas de tensiones en el sistema alfa-beta
    o_alfa : out std_logic_vector(31 downto 0);
    o_beta : out std_logic_vector(31 downto 0)
);
end TransformadaClark;

architecture Behavioral of TransformadaClark is
    -- Constantes en formato Q1.24 para amplitud invariante
    -- K_ALPHA = 2/3
    constant K_ALPHA : sfixed(1 downto -FRAC_BITS) := to_sfixed(2.0/3.0, 1, -FRAC_BITS);
    -- K_BETA  = 1/sqrt(3)  (Simplificación de 2/3 * sqrt(3)/2)
    constant K_BETA  : sfixed(1 downto -FRAC_BITS) := to_sfixed(0.577350269, 1, -FRAC_BITS);

    -- Señales internas para las componentes alfa y beta
    signal w_alfa : sfixed(INT_BITS*3 +1 downto -(FRAC_BITS*3)) := (others => '0');
    signal w_beta : sfixed(INT_BITS*3 downto -(FRAC_BITS*3)) := (others => '0');
    signal r_alfa : sfixed(INT_BITS - 1 downto -FRAC_BITS);
    signal r_beta : sfixed(INT_BITS - 1 downto -FRAC_BITS);

    -- SEÑALES DE PIPELINE (Etapa 1)
    signal val_p1     : std_logic;
    signal term_u_p1  : sfixed(INT_BITS - 1 downto -FRAC_BITS);
    signal sum_vw_p1  : sfixed(INT_BITS downto -FRAC_BITS); -- V + W
    signal diff_vw_p1 : sfixed(INT_BITS downto -FRAC_BITS); -- V - W

    -- SEÑALES DE PIPELINE (Etapa 2 - Salida)
    signal val_p2     : std_logic;

    begin

    process (i_clk)
        -- Variables temporales para conversión y resize automático
        variable v_in_u, v_in_v, v_in_w : sfixed(INT_BITS-1 downto -FRAC_BITS);
        
        -- Variables para cálculos intermedios de mayor precisión
        variable v_mult_alfa : sfixed(INT_BITS+4 downto -FRAC_BITS*2);
        variable v_mult_beta : sfixed(INT_BITS+2 downto -FRAC_BITS*2);
        variable v_term_alfa : sfixed(INT_BITS+2 downto -FRAC_BITS);
        
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                val_p1   <= '0';
                val_p2   <= '0';
                o_valido <= '0';
                o_alfa   <= (others => '0');
                o_beta   <= (others => '0');
            else
                ------------------------------------------------------------
                -- ETAPA 1: Captura, Sumas y Restas
                ------------------------------------------------------------
                -- Convertimos entradas SLV a sfixed
                v_in_u := to_sfixed(i_U, INT_BITS-1, -FRAC_BITS);
                v_in_v := to_sfixed(i_V, INT_BITS-1, -FRAC_BITS);
                v_in_w := to_sfixed(i_W, INT_BITS-1, -FRAC_BITS);

                -- Cálculos preliminares (Pre-Adders)
                -- Guardamos U para usarlo después
                term_u_p1  <= v_in_u;
                -- (V + W)
                sum_vw_p1  <= v_in_v + v_in_w;
                -- (V - W)
                diff_vw_p1 <= v_in_v - v_in_w;
                
                -- Pipeline del valid
                val_p1 <= i_start;

                ------------------------------------------------------------
                -- ETAPA 2: Multiplicaciones y Asignación Final
                ------------------------------------------------------------
                
                -- CÁLCULO ALPHA: 2/3 * (U - 0.5 * (V + W))
                -- Nota: Multiplicar por 0.5 es un shift a la derecha (sra 1)
                v_term_alfa := resize(term_u_p1, INT_BITS+1, -FRAC_BITS) - (resize(sum_vw_p1, INT_BITS+1, -FRAC_BITS) sra 1);
                v_mult_alfa := v_term_alfa * K_ALPHA;

                -- CÁLCULO BETA: 1/sqrt(3) * (V - W)
                v_mult_beta := diff_vw_p1 * K_BETA;

                -- Salidas con Resize final (Truncamiento/Redondeo)
                o_alfa <= to_slv(resize(v_mult_alfa, INT_BITS-1, -FRAC_BITS));
                o_beta <= to_slv(resize(v_mult_beta, INT_BITS-1, -FRAC_BITS));
                val_p2 <= val_p1; 
                
                -- Pipeline del valid
                o_valido <= val_p2; -- El dato calculado ahora corresponde al valid del ciclo anterior
                
            end if;

        end if;

    end process;

    end Behavioral;