library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_Modulador_v1_0 is
	generic (
		-- Parameters of Axi Slave Bus Interface S_AXI_PARAMS
		C_S_AXI_PARAMS_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_PARAMS_ADDR_WIDTH	: integer	:= 5
	);
	port (
		--Puerto Ts para indicar el inicio del XADC
		o_fin_calc_ts 	: out std_logic;

		--Coeficientes para realizar el producto posterior con el seno trifasico de entrada 
		o_coef_matriz	: out std_logic_vector(8 downto 0);
		
		-- Ports of Axi Slave Bus Interface S_AXI_PARAMS
		s_axi_params_aclk		: in std_logic;
		s_axi_params_aresetn	: in std_logic;
		s_axi_params_awaddr		: in std_logic_vector(C_S_AXI_PARAMS_ADDR_WIDTH-1 downto 0);
		s_axi_params_awprot		: in std_logic_vector(2 downto 0);
		s_axi_params_awvalid	: in std_logic;
		s_axi_params_awready	: out std_logic;
		s_axi_params_wdata		: in std_logic_vector(C_S_AXI_PARAMS_DATA_WIDTH-1 downto 0);
		s_axi_params_wstrb		: in std_logic_vector((C_S_AXI_PARAMS_DATA_WIDTH/8)-1 downto 0);
		s_axi_params_wvalid		: in std_logic;
		s_axi_params_wready		: out std_logic;
		s_axi_params_bresp		: out std_logic_vector(1 downto 0);
		s_axi_params_bvalid		: out std_logic;
		s_axi_params_bready		: in std_logic;
		s_axi_params_araddr		: in std_logic_vector(C_S_AXI_PARAMS_ADDR_WIDTH-1 downto 0);
		s_axi_params_arprot		: in std_logic_vector(2 downto 0);
		s_axi_params_arvalid	: in std_logic;
		s_axi_params_arready	: out std_logic;
		s_axi_params_rdata		: out std_logic_vector(C_S_AXI_PARAMS_DATA_WIDTH-1 downto 0);
		s_axi_params_rresp		: out std_logic_vector(1 downto 0);
		s_axi_params_rvalid		: out std_logic;
		s_axi_params_rready		: in std_logic
	);
end AXI_Modulador_v1_0;

architecture arch_imp of AXI_Modulador_v1_0 is
	-- component declaration
	component AXI_Modulador_v1_0_S_AXI_PARAMS is
		generic 
		(
			C_S_AXI_DATA_WIDTH	: integer	:= 32;
			C_S_AXI_ADDR_WIDTH	: integer	:= 5
		);
		port 
		(
			S_ENABLE_MOD	: out 	 std_logic;
			S_ALPHA_O		: out    std_logic_vector(10 downto 0);
			S_BETA_I		: out    std_logic_vector(10 downto 0);
			S_Q_I			: out    std_logic_vector(8 downto 0);
			S_PHI_I			: out    std_logic_vector(10 downto 0);
		
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
	end component AXI_Modulador_v1_0_S_AXI_PARAMS;

	component Modulador is
		port 
		(
    		i_reloj     : in    std_logic;                     --! Entrada de 200 MHz
			i_enable	: in 	std_logic;
    		i_al_o      : in    std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
    		i_be_i      : in    std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
    		i_q_i       : in    std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
    		i_phi_i     : in    std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

    		o_fin_ciclo    : out   std_logic;                     --! Indica Fin de Ciclo
    		o_inicio_ciclo : out   std_logic;                     --! Indica Inicio de Ciclo
    		o_fin_calc_ts  : out   std_logic;                     --! Indica que el calculo de las salidas finalizo (Ts)
    		o_direcciones  : out   std_logic_vector(17 downto 0) --! Salida con las señales de las conmutaciones
  		);
	end component Modulador;

	--Creacion de señales Modulador - Puertos Axi
	signal w_enable : std_logic;
	signal w_alpha 	: std_logic_vector(10 downto 0);
	signal w_beta 	: std_logic_vector(10 downto 0);
	signal w_qi 	: std_logic_vector(8 downto 0);
	signal w_phi_i 	: std_logic_vector(10 downto 0);
	signal w_dirrecs : std_logic_vector(17 downto 0);
	signal w_fin_calc_ts : std_logic;

begin

-- Instantiation of Axi Bus Interface S_AXI_PARAMS
	AXI_Modulador_v1_0_S_AXI_PARAMS_inst : AXI_Modulador_v1_0_S_AXI_PARAMS
		generic map 
		(
			C_S_AXI_DATA_WIDTH	=> C_S_AXI_PARAMS_DATA_WIDTH,
			C_S_AXI_ADDR_WIDTH	=> C_S_AXI_PARAMS_ADDR_WIDTH
		)
		port map 
		(
			S_ENABLE_MOD => w_enable,
			S_ALPHA_O => w_alpha,
			S_BETA_I  => w_beta,
			S_Q_I => w_qi,	
			S_PHI_I => w_phi_i,

			S_AXI_ACLK		=> s_axi_params_aclk,
			S_AXI_ARESETN	=> s_axi_params_aresetn,
			S_AXI_AWADDR	=> s_axi_params_awaddr,
			S_AXI_AWPROT	=> s_axi_params_awprot,
			S_AXI_AWVALID	=> s_axi_params_awvalid,
			S_AXI_AWREADY	=> s_axi_params_awready,
			S_AXI_WDATA		=> s_axi_params_wdata,
			S_AXI_WSTRB		=> s_axi_params_wstrb,
			S_AXI_WVALID	=> s_axi_params_wvalid,
			S_AXI_WREADY	=> s_axi_params_wready,
			S_AXI_BRESP		=> s_axi_params_bresp,
			S_AXI_BVALID	=> s_axi_params_bvalid,
			S_AXI_BREADY	=> s_axi_params_bready,
			S_AXI_ARADDR	=> s_axi_params_araddr,
			S_AXI_ARPROT	=> s_axi_params_arprot,
			S_AXI_ARVALID	=> s_axi_params_arvalid,
			S_AXI_ARREADY	=> s_axi_params_arready,
			S_AXI_RDATA		=> s_axi_params_rdata,
			S_AXI_RRESP		=> s_axi_params_rresp,
			S_AXI_RVALID	=> s_axi_params_rvalid,
			S_AXI_RREADY	=> s_axi_params_rready
		);


-- Instanciacion del Modulador
	Modulador_inst: Modulador
		port map (
			i_reloj     => s_axi_params_aclk,
			i_enable	=> w_enable,
    		i_al_o      => w_alpha,
    		i_be_i      => w_beta,
    		i_q_i       => w_qi,
    		i_phi_i     => w_phi_i,

    		o_fin_ciclo    => open,                     
    		o_inicio_ciclo => open,
    		o_fin_calc_ts  => w_fin_calc_ts,
    		o_direcciones  => w_dirrecs 
		);
	
	-- Add user logic here
	
	o_fin_calc_ts <= w_fin_calc_ts;
	o_coef_matriz <= w_dirrecs(8 downto 0);
	-- User logic ends



end arch_imp;
