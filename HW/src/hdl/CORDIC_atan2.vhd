library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CORDIC_atan2 is
    Generic (
        ITERATIONS : integer := 20  -- 20 iteraciones son suficientes para precisión de 11 bits
    );
    Port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        start    : in  std_logic;
        
        -- Entradas Q8.24 (32 bits signed)
        x_in     : in  signed(31 downto 0);
        y_in     : in  signed(31 downto 0);
        
        -- Salida Entero 11 bits
        -- El rango representa -PI a +PI
        angle_out : out unsigned(10 downto 0);
        done      : out std_logic
    );
end CORDIC_atan2;

architecture Behavioral of CORDIC_atan2 is

    -- Tipos y Señales
    type state_type is (IDLE, PRE_PROCESS, RUN, FINISH);
    signal state : state_type;
    
    -- Registros internos con precisión extendida para el cálculo
    signal x_reg, y_reg, z_reg : signed(31 downto 0);
    signal i_cnt : integer range 0 to ITERATIONS;

    -- Look-Up Table (LUT) de Arco Tangente
    -- Formato: Ángulos normalizados a 32 bits (BAM)
    -- Valor = arctan(2^-i) * 2^32 / (2*PI)
    type lut_type is array (0 to 19) of signed(31 downto 0);
    constant ATAN_TABLE : lut_type := (
        x"20000000", -- i=0,  45.00 deg
        x"12E4051D", -- i=1,  26.56 deg
        x"09FB385B", -- i=2,  14.03 deg
        x"051111D4", -- i=3,   7.12 deg
        x"028B0D43", -- i=4,   3.57 deg
        x"0145D7E1", -- i=5,   1.79 deg
        x"00A2F983", -- i=6,   0.89 deg
        x"00517CC1", -- i=7,   0.45 deg
        x"0028BE60", -- i=8,   0.22 deg
        x"00145F30", -- i=9,   0.11 deg
        x"000A2F98", -- i=10
        x"000517CC", -- i=11
        x"00028BE6", -- i=12
        x"000145F3", -- i=13
        x"0000A2F9", -- i=14
        x"0000517C", -- i=15
        x"000028BE", -- i=16
        x"0000145F", -- i=17
        x"00000A2F", -- i=18
        x"00000517"  -- i=19
    );

begin

    process(clk)
        variable x_shift, y_shift : signed(31 downto 0);
        variable angle_val : signed(31 downto 0);
        variable sign_y : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                x_reg <= (others => '0');
                y_reg <= (others => '0');
                z_reg <= (others => '0');
                done  <= '0';
                angle_out <= (others => '0');
            else
                case state is
                    when IDLE =>
                        done <= '0';
                        if start = '1' then
                            state <= PRE_PROCESS;
                        end if;

                    when PRE_PROCESS =>
                        -- Manejo de Cuadrantes 2 y 3 (Si X es negativo)
                        -- Truco: Invertimos X e Y para trabajar en Q1/Q4
                        -- e inicializamos el ángulo Z en 180 grados (0x80000000 es el bit de signo máximo)
                        if x_in < 0 then
                            x_reg <= -x_in;
                            y_reg <= -y_in;
                            z_reg <= x"80000000"; -- Equivalente a +PI o -PI en binario
                        else
                            x_reg <= x_in;
                            y_reg <= y_in;
                            z_reg <= (others => '0');
                        end if;
                        
                        i_cnt <= 0;
                        state <= RUN;

                    when RUN =>
                        -- Desplazamientos aritméticos (división por 2^i)
                        x_shift := shift_right(x_reg, i_cnt);
                        y_shift := shift_right(y_reg, i_cnt);
                        angle_val := ATAN_TABLE(i_cnt);
                        
                        -- Determinar dirección de rotación
                        -- Queremos llevar y_reg a 0.
                        -- Si y_reg es positivo, giramos horario (restamos ángulo a Y)
                        if y_reg(31) = '0' then -- y_reg >= 0
                            x_reg <= x_reg + y_shift;
                            y_reg <= y_reg - x_shift;
                            z_reg <= z_reg + angle_val;
                        else -- y_reg < 0
                            x_reg <= x_reg - y_shift;
                            y_reg <= y_reg + x_shift;
                            z_reg <= z_reg - angle_val;
                        end if;

                        if i_cnt = ITERATIONS - 1 then
                            state <= FINISH;
                        else
                            i_cnt <= i_cnt + 1;
                        end if;

                    when FINISH =>
                        -- Tomamos los 11 bits más significativos del acumulador de ángulo
                        angle_out <= unsigned(z_reg(31 downto 21));
                        done <= '1';
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

end Behavioral;