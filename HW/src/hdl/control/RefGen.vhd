library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sine_lut_pkg.all;

--! Generador de la referencia de corriente, directo en alfa/beta.
--!
--! Un acumulador de fase de 32 bits avanza i_paso por cada pulso de i_en
--! (uno por Ts). Los 11 bits altos direccionan SINE_TABLE, la misma LUT que
--! ya usa el resto del diseno: 2048 entradas de una vuelta completa, en
--! Q8.24 con amplitud 1,0.
--!
--! Se genera DIRECTO en alfa/beta y no en abc pasado por una Clarke: ahorra
--! una transformada y el error de cuantizacion de ida y vuelta.
--!
--! Convencion, la misma que el modelo de Python:
--!     alfa = A*cos(theta) = A*SINE_TABLE[theta + 512]
--!     beta = A*sen(theta) = A*SINE_TABLE[theta]
--! Si se invirtieran, la referencia seria de secuencia negativa y el lazo
--! perseguiria una corriente en contrafase.
--!
--! VHDL-93 + numeric_std a proposito: asi lo puede simular GHDL 0.29.
entity RefGen is
    port (
        i_clk   : in  std_logic;
        i_rst   : in  std_logic;
        i_en    : in  std_logic;                   --! un pulso por Ts
        i_paso  : in  unsigned(31 downto 0);       --! avance de fase por Ts
        i_amp   : in  signed(31 downto 0);         --! Q8.24
        o_alfa  : out signed(31 downto 0);         --! Q8.24
        o_beta  : out signed(31 downto 0);         --! Q8.24
        o_theta : out unsigned(10 downto 0)
    );
end entity RefGen;

architecture rtl of RefGen is
    signal fase : unsigned(31 downto 0) := (others => '0');
    signal alfa : signed(31 downto 0) := (others => '0');
    signal beta : signed(31 downto 0) := (others => '0');

    --! amp (Q8.24) * muestra (Q8.24) = Q16.48 en 64 bits; el bit i pesa
    --! 2^(i-48), asi que Q8.24 arranca en el 24: 55 downto 24. Es el mismo
    --! reescalado que usa PR_2int.
    function escalar (amp : signed(31 downto 0);
                      s   : signed(31 downto 0)) return signed is
        variable p : signed(63 downto 0);
    begin
        p := amp * s;
        return p(55 downto 24);
    end function escalar;

begin

    o_alfa  <= alfa;
    o_beta  <= beta;
    o_theta <= fase(31 downto 21);

    proceso : process (i_clk)
        variable dir : integer range 0 to LUT_DEPTH - 1;
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                fase <= (others => '0');
                alfa <= (others => '0');
                beta <= (others => '0');
            elsif i_en = '1' then
                dir  := to_integer(fase(31 downto 21));
                alfa <= escalar(i_amp, SINE_TABLE((dir + 512) mod LUT_DEPTH));
                beta <= escalar(i_amp, SINE_TABLE(dir));
                fase <= fase + i_paso;
            end if;
        end if;
    end process proceso;

end architecture rtl;
