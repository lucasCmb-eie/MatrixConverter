library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_Promediador is
	generic (
		-- Parameters of Axi Slave Bus Interface S0_AXI_PROMEDIOS
		C_S0_AXI_PROMEDIOS_DATA_WIDTH	: integer	:= 32;
		C_S0_AXI_PROMEDIOS_ADDR_WIDTH	: integer	:= 4
	);
	port (
		-- Users to add ports here
		axi_clk : in std_logic;
		sync_trigger : in std_logic;
		enable : in std_logic;
		i_data_1 : in std_logic_vector(31 downto 0);
		i_data_2 : in std_logic_vector(31 downto 0);
		i_data_3 : in std_logic_vector(31 downto 0);

		o_irq : out std_logic;
		-- User ports ends
		-- Do not modify the ports beyond this line


		-- Ports of Axi Slave Bus Interface S0_AXI_PROMEDIOS
		s0_axi_promedios_aresetn	: in std_logic;
		s0_axi_promedios_awaddr	: in std_logic_vector(C_S0_AXI_PROMEDIOS_ADDR_WIDTH-1 downto 0);
		s0_axi_promedios_awprot	: in std_logic_vector(2 downto 0);
		s0_axi_promedios_awvalid	: in std_logic;
		s0_axi_promedios_awready	: out std_logic;
		s0_axi_promedios_wdata	: in std_logic_vector(C_S0_AXI_PROMEDIOS_DATA_WIDTH-1 downto 0);
		s0_axi_promedios_wstrb	: in std_logic_vector((C_S0_AXI_PROMEDIOS_DATA_WIDTH/8)-1 downto 0);
		s0_axi_promedios_wvalid	: in std_logic;
		s0_axi_promedios_wready	: out std_logic;
		s0_axi_promedios_bresp	: out std_logic_vector(1 downto 0);
		s0_axi_promedios_bvalid	: out std_logic;
		s0_axi_promedios_bready	: in std_logic;
		s0_axi_promedios_araddr	: in std_logic_vector(C_S0_AXI_PROMEDIOS_ADDR_WIDTH-1 downto 0);
		s0_axi_promedios_arprot	: in std_logic_vector(2 downto 0);
		s0_axi_promedios_arvalid	: in std_logic;
		s0_axi_promedios_arready	: out std_logic;
		s0_axi_promedios_rdata	: out std_logic_vector(C_S0_AXI_PROMEDIOS_DATA_WIDTH-1 downto 0);
		s0_axi_promedios_rresp	: out std_logic_vector(1 downto 0);
		s0_axi_promedios_rvalid	: out std_logic;
		s0_axi_promedios_rready	: in std_logic
	);
end AXI_Promediador;

architecture arch_imp of AXI_Promediador is

	-- component declaration
	component AXI_Promediador_slave_lite_v1_0_S0_AXI_PROMEDIOS is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 4
		);
		port (
		S_AXI_ACLK	: in std_logic;
		S_AXI_ARESETN	: in std_logic;
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		S_AXI_AWVALID	: in std_logic;
		S_AXI_AWREADY	: out std_logic;
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		S_AXI_WVALID	: in std_logic;
		S_AXI_WREADY	: out std_logic;
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		S_AXI_BVALID	: out std_logic;
		S_AXI_BREADY	: in std_logic;
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		S_AXI_ARVALID	: in std_logic;
		S_AXI_ARREADY	: out std_logic;
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		S_AXI_RVALID	: out std_logic;
		S_AXI_RREADY	: in std_logic;

		i_prom_1 : in std_logic_vector(31 downto 0);
		i_prom_2 : in std_logic_vector(31 downto 0);
		i_prom_3 : in std_logic_vector(31 downto 0)
		);
	end component AXI_Promediador_slave_lite_v1_0_S0_AXI_PROMEDIOS;

	constant N_LOG2 : integer := 11; -- 2048 muestras
    
    signal acc_1 : signed(47 downto 0) := (others => '0');
    signal acc_2 : signed(47 downto 0) := (others => '0');
    signal acc_3 : signed(47 downto 0) := (others => '0');
    
    signal counter      : unsigned(N_LOG2-1 downto 0) := (others => '0');
    signal trigger_prev : std_logic := '1';
    
    -- Señales intermedias para conectar Lógica -> AXI
    signal result_avg_1 : std_logic_vector(31 downto 0);
    signal result_avg_2 : std_logic_vector(31 downto 0);
    signal result_avg_3 : std_logic_vector(31 downto 0);
    
    signal result_valid : std_logic := '0';

begin

-- Instantiation of Axi Bus Interface S0_AXI_PROMEDIOS
AXI_Promediador_slave_lite_v1_0_S0_AXI_PROMEDIOS_inst : AXI_Promediador_slave_lite_v1_0_S0_AXI_PROMEDIOS
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S0_AXI_PROMEDIOS_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S0_AXI_PROMEDIOS_ADDR_WIDTH
	)
	port map (
		S_AXI_ACLK	=> axi_clk,
		S_AXI_ARESETN	=> s0_axi_promedios_aresetn,
		S_AXI_AWADDR	=> s0_axi_promedios_awaddr,
		S_AXI_AWPROT	=> s0_axi_promedios_awprot,
		S_AXI_AWVALID	=> s0_axi_promedios_awvalid,
		S_AXI_AWREADY	=> s0_axi_promedios_awready,
		S_AXI_WDATA	=> s0_axi_promedios_wdata,
		S_AXI_WSTRB	=> s0_axi_promedios_wstrb,
		S_AXI_WVALID	=> s0_axi_promedios_wvalid,
		S_AXI_WREADY	=> s0_axi_promedios_wready,
		S_AXI_BRESP	=> s0_axi_promedios_bresp,
		S_AXI_BVALID	=> s0_axi_promedios_bvalid,
		S_AXI_BREADY	=> s0_axi_promedios_bready,
		S_AXI_ARADDR	=> s0_axi_promedios_araddr,
		S_AXI_ARPROT	=> s0_axi_promedios_arprot,
		S_AXI_ARVALID	=> s0_axi_promedios_arvalid,
		S_AXI_ARREADY	=> s0_axi_promedios_arready,
		S_AXI_RDATA	=> s0_axi_promedios_rdata,
		S_AXI_RRESP	=> s0_axi_promedios_rresp,
		S_AXI_RVALID	=> s0_axi_promedios_rvalid,
		S_AXI_RREADY	=> s0_axi_promedios_rready,

		i_prom_1 => result_avg_1,
		i_prom_2 => result_avg_2,
		i_prom_3 => result_avg_3
	);

-- LÓGICA DE PROCESAMIENTO
    process(axi_clk)
    begin
        if rising_edge(axi_clk) then
            if (s0_axi_promedios_aresetn = '0' or enable = '0') then
                -- Reset
                acc_1   <= (others => '0');
                acc_2   <= (others => '0');
                acc_3   <= (others => '0');
                counter <= (others => '0');
                result_valid <= '0';
                trigger_prev <= '1';
                
                result_avg_1 <= (others => '0');
                result_avg_2 <= (others => '0');
                result_avg_3 <= (others => '0');
            else
                result_valid <= '0';
                
                -- Detección de Flanco Descendente (Trigger)
                if (trigger_prev = '1' and sync_trigger = '0') then
                    -- Resync
                    acc_1   <= (others => '0');
                    acc_2   <= (others => '0');
                    acc_3   <= (others => '0');
                    counter <= (others => '0');
                    trigger_prev <= sync_trigger;
                else
                    trigger_prev <= sync_trigger;

                    if counter = (2**N_LOG2) - 1 then 
                        -- Publicar Resultados en las señales intermedias
                        result_avg_1 <= std_logic_vector(resize((acc_1 + signed(i_data_1)) / (2**N_LOG2), 32));
                        result_avg_2 <= std_logic_vector(resize((acc_2 + signed(i_data_2)) / (2**N_LOG2), 32));
                        result_avg_3 <= std_logic_vector(resize((acc_3 + signed(i_data_3)) / (2**N_LOG2), 32));
                        
                        result_valid <= '1'; -- Interrupción
                        
                        -- Reset acumuladores
                        acc_1   <= (others => '0');
                        acc_2   <= (others => '0');
                        acc_3   <= (others => '0');
                        counter <= (others => '0');
                    else
                        -- Acumular
                        acc_1   <= acc_1 + signed(i_data_1);
                        acc_2   <= acc_2 + signed(i_data_2);
                        acc_3   <= acc_3 + signed(i_data_3);
                        counter <= counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Conectamos la interrupción directo a la salida del Top
    o_irq <= result_valid;


end arch_imp;
