library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_TriRL is
	generic (
		-- Parameters of Axi Slave Bus Interface S0_AXI_PARAMETROS
		C_S0_AXI_PARAMETROS_DATA_WIDTH	: integer	:= 32;
		C_S0_AXI_PARAMETROS_ADDR_WIDTH	: integer	:= 4
	);
	port (

		-- Reset asíncrono activo a nivel bajo
		i_rst  : in  std_logic; 

		-- Tensiones de la carga RL 
		i_U : in std_logic_vector(31 downto 0);
		i_V : in std_logic_vector(31 downto 0);
		i_W : in std_logic_vector(31 downto 0);

		-- Corrientes de la carga RL a enviar al PS
		o_Iu : out std_logic_vector(31 downto 0);
		o_Iv : out std_logic_vector(31 downto 0);
		o_Iw : out std_logic_vector(31 downto 0);

		axi_aclk : in std_logic;

		-- Ports of Axi Slave Bus Interface S0_AXI_PARAMETROS
		s0_axi_parametros_aresetn	: in std_logic;
		s0_axi_parametros_awaddr	: in std_logic_vector(C_S0_AXI_PARAMETROS_ADDR_WIDTH-1 downto 0);
		s0_axi_parametros_awprot	: in std_logic_vector(2 downto 0);
		s0_axi_parametros_awvalid	: in std_logic;
		s0_axi_parametros_awready	: out std_logic;
		s0_axi_parametros_wdata	: in std_logic_vector(C_S0_AXI_PARAMETROS_DATA_WIDTH-1 downto 0);
		s0_axi_parametros_wstrb	: in std_logic_vector((C_S0_AXI_PARAMETROS_DATA_WIDTH/8)-1 downto 0);
		s0_axi_parametros_wvalid	: in std_logic;
		s0_axi_parametros_wready	: out std_logic;
		s0_axi_parametros_bresp	: out std_logic_vector(1 downto 0);
		s0_axi_parametros_bvalid	: out std_logic;
		s0_axi_parametros_bready	: in std_logic;
		s0_axi_parametros_araddr	: in std_logic_vector(C_S0_AXI_PARAMETROS_ADDR_WIDTH-1 downto 0);
		s0_axi_parametros_arprot	: in std_logic_vector(2 downto 0);
		s0_axi_parametros_arvalid	: in std_logic;
		s0_axi_parametros_arready	: out std_logic;
		s0_axi_parametros_rdata	: out std_logic_vector(C_S0_AXI_PARAMETROS_DATA_WIDTH-1 downto 0);
		s0_axi_parametros_rresp	: out std_logic_vector(1 downto 0);
		s0_axi_parametros_rvalid	: out std_logic;
		s0_axi_parametros_rready	: in std_logic
	);
end AXI_TriRL;

architecture arch_imp of AXI_TriRL is

	-- component declaration
	component AXI_TriRL_slave_lite_v1_0_S0_AXI_PARAMETROS is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 4
		);
		port (
		COEF_a0 	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		COEF_a1 	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		COEF_b0 	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
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
		S_AXI_RREADY	: in std_logic
		);
	end component AXI_TriRL_slave_lite_v1_0_S0_AXI_PARAMETROS;
	-- Declaración del componente de la carga RL
	component RL_wrapper is
		generic (
			INT_BITS    : integer := 8;
			FRAC_BITS   : integer := 24
		);
		port (
			-- Señales de control
			i_clk   : in  std_logic;
			i_rst   : in  std_logic; -- Reset asíncrono activo a nivel bajo

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
	end component RL_wrapper;
	
	-- Señales personalizadas
	signal w_c_a0 : std_logic_vector(31 downto 0);
	signal w_c_a1 : std_logic_vector(31 downto 0);
	signal w_c_b1 : std_logic_vector(31 downto 0);

	--Señales de corrientes
	signal w_Iu : std_logic_vector(31 downto 0);
	signal w_Iv : std_logic_vector(31 downto 0);
	signal w_Iw : std_logic_vector(31 downto 0);
begin

-- Instantiation of Axi Bus Interface S0_AXI_PARAMETROS
AXI_TriRL_slave_lite_v1_0_S0_AXI_PARAMETROS_inst : AXI_TriRL_slave_lite_v1_0_S0_AXI_PARAMETROS
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S0_AXI_PARAMETROS_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S0_AXI_PARAMETROS_ADDR_WIDTH
	)
	port map (
		COEF_a0 	=> w_c_a0,
		COEF_a1 	=> w_c_a1,
		COEF_b0 	=> w_c_b1,
		S_AXI_ACLK	=> axi_aclk,
		S_AXI_ARESETN	=> s0_axi_parametros_aresetn,
		S_AXI_AWADDR	=> s0_axi_parametros_awaddr,
		S_AXI_AWPROT	=> s0_axi_parametros_awprot,
		S_AXI_AWVALID	=> s0_axi_parametros_awvalid,
		S_AXI_AWREADY	=> s0_axi_parametros_awready,
		S_AXI_WDATA	=> s0_axi_parametros_wdata,
		S_AXI_WSTRB	=> s0_axi_parametros_wstrb,
		S_AXI_WVALID	=> s0_axi_parametros_wvalid,
		S_AXI_WREADY	=> s0_axi_parametros_wready,
		S_AXI_BRESP	=> s0_axi_parametros_bresp,
		S_AXI_BVALID	=> s0_axi_parametros_bvalid,
		S_AXI_BREADY	=> s0_axi_parametros_bready,
		S_AXI_ARADDR	=> s0_axi_parametros_araddr,
		S_AXI_ARPROT	=> s0_axi_parametros_arprot,
		S_AXI_ARVALID	=> s0_axi_parametros_arvalid,
		S_AXI_ARREADY	=> s0_axi_parametros_arready,
		S_AXI_RDATA	=> s0_axi_parametros_rdata,
		S_AXI_RRESP	=> s0_axi_parametros_rresp,
		S_AXI_RVALID	=> s0_axi_parametros_rvalid,
		S_AXI_RREADY	=> s0_axi_parametros_rready
	);

-- Instancia de la Carga RL
AXI_TriRL_inst : RL_wrapper
	generic map (
		INT_BITS    => 8,
		FRAC_BITS   => 24
	)
	port map (
		i_clk     => axi_aclk,
		i_rst     => i_rst,
		i_c_a0    => w_c_a0,
		i_c_a1    => w_c_a1,
		i_c_b1    => w_c_b1,
		i_U       => i_U,
		i_V       => i_V,
		i_W       => i_W,
		o_Iu      => w_Iu,
		o_Iv      => w_Iv,
		o_Iw      => w_Iw
	);
	

o_Iu <= w_Iu;
o_Iv <= w_Iv;
o_Iw <= w_Iw;

end arch_imp;
