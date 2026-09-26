library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! Un eje del controlador proporcional-resonante.
--!
--!   x1[n] = x1[n-1] - k*x2[n-1] + b*e[n]      k = 2*sin(w_o*Ts/2)  (Q1.24)
--!   x2[n] = x2[n-1] + k*x1[n]                 b = Kr*Ts            (Q8.24)
--!   u[n]  = Kp*e[n] + x1[n]
--!
--! El segundo integrador usa el x1 YA actualizado (discretizacion
--! forward-backward). La matriz de transicion resultante es
--! [[1,-k],[k,1-k^2]], de determinante 1 para cualquier k: los polos quedan
--! sobre el circulo unidad aunque k este mal cuantizado, asi que el
--! resonador no se amortigua ni diverge por redondeo. Un error en k solo
--! corre la frecuencia.
--!
--! Ojo: det(A) = 1 no significa que A sea ortogonal. Lo que la rotacion
--! conserva es x1^2 + x2^2 - k*x1*x2, no el modulo euclideo.
--!
--! Como el resonador ideal NO amortigua, cualquier basura en x1/x2 se queda
--! para siempre: el reset tiene que dejarlos exactamente en cero.
--!
--! i_sat congela la ENTRADA, no el estado: x2 sigue rotando, de modo que el
--! resonador no pierde fase contra la referencia mientras dura la
--! saturacion. Vale para los dos ejes a la vez, porque la restriccion es
--! sobre el modulo conjunto del vector.
--!
--! VHDL-93 + numeric_std a proposito: asi lo puede simular GHDL 0.29, que no
--! soporta VHDL-2008 ni ieee.fixed_pkg.
--!
--! Verificado bit a bit contra SW/python/ModeloControlPR.py (tb_PR_2int).
entity PR_2int is
    port (
        i_clk : in  std_logic;
        i_rst : in  std_logic;
        i_en  : in  std_logic;                     --! un pulso por Ts
        i_sat : in  std_logic;                     --! congela la entrada
        i_k   : in  signed(24 downto 0);           --! Q1.24
        i_b   : in  signed(31 downto 0);           --! Q8.24, vale Kr*Ts
        i_kp  : in  signed(31 downto 0);           --! Q8.24
        i_e   : in  signed(31 downto 0);           --! Q8.24
        o_u   : out signed(31 downto 0);           --! Q8.24
        o_x1  : out signed(47 downto 0);           --! Q8.40
        o_x2  : out signed(47 downto 0)            --! Q8.40
    );
end entity PR_2int;

architecture rtl of PR_2int is
    signal x1 : signed(47 downto 0) := (others => '0');
    signal x2 : signed(47 downto 0) := (others => '0');
    signal u  : signed(31 downto 0) := (others => '0');

    --! k (Q1.24) * x (Q8.40) = Q9.64 en 73 bits; el bit i pesa 2^(i-64), asi
    --! que Q8.40 arranca en el 24 y son 48 bits: 71 downto 24.
    function k_por_x (k : signed(24 downto 0);
                      x : signed(47 downto 0)) return signed is
        variable p : signed(72 downto 0);
    begin
        p := k * x;
        return p(71 downto 24);
    end function k_por_x;

    --! a (Q8.24) * b (Q8.24) = Q16.48 en 64 bits; el bit i pesa 2^(i-48),
    --! asi que Q8.40 arranca en el 8: 55 downto 8.
    function q824_por_q824_a_q840 (a : signed(31 downto 0);
                                   b : signed(31 downto 0)) return signed is
        variable p : signed(63 downto 0);
    begin
        p := a * b;
        return p(55 downto 8);
    end function q824_por_q824_a_q840;

    --! El mismo producto, pero devuelto en Q8.24: arranca en el bit 24.
    function q824_por_q824_a_q824 (a : signed(31 downto 0);
                                   b : signed(31 downto 0)) return signed is
        variable p : signed(63 downto 0);
    begin
        p := a * b;
        return p(55 downto 24);
    end function q824_por_q824_a_q824;

begin

    o_x1 <= x1;
    o_x2 <= x2;
    o_u  <= u;

    proceso : process (i_clk)
        variable k_x2 : signed(47 downto 0);
        variable b_e  : signed(47 downto 0);
        variable x1_v : signed(47 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                x1 <= (others => '0');
                x2 <= (others => '0');
                u  <= (others => '0');
            elsif i_en = '1' then
                k_x2 := k_por_x(i_k, x2);

                if i_sat = '1' then
                    b_e := (others => '0');
                else
                    b_e := q824_por_q824_a_q840(i_b, i_e);
                end if;

                x1_v := x1 - k_x2 + b_e;
                x1 <= x1_v;
                x2 <= x2 + k_por_x(i_k, x1_v);

                -- x1_v es Q8.40 (el bit 40 pesa 2^0); a Q8.24 (el bit 24
                -- pesa 2^0) hay que tomar 47 downto 16, que es el >>16 del
                -- modelo de Python.
                u  <= q824_por_q824_a_q824(i_kp, i_e) + x1_v(47 downto 16);
            end if;
        end if;
    end process proceso;

end architecture rtl;
