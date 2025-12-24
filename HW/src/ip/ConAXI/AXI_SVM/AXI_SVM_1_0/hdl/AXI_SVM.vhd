library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_SVM is
	generic (
		-- Parameters of Axi Slave Bus Interface S0_AXI_PARAMETROS
		C_S0_AXI_PARAMETROS_DATA_WIDTH	: integer	:= 32;
		C_S0_AXI_PARAMETROS_ADDR_WIDTH	: integer	:= 4
	);
	port (
		-- Users to add ports here
        axi_aclk : in std_logic;
        enable : in std_logic;
        
        alpha_out : out std_logic_vector(10 downto 0);
        beta_inp  : out std_logic_vector(10 downto 0);
        q_inp : out std_logic_vector(8 downto 0);
        phi_inp : out std_logic_vector(10 downto 0);
        
        fin_ciclo    : out std_logic;                    
        inicio_ciclo : out std_logic;                    
        fin_calc_ts  : out std_logic;

        --Tensiones de entrada alimentacion
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
		--Tensiones de salida SVM
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0);

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
end AXI_SVM;

architecture arch_imp of AXI_SVM is

	-- component declaration
	component AXI_SVM_slave_lite_v1_0_S0_AXI_PARAMETROS is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 4
		);
		port (
		
		CONTROL_REG : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		ALPHA_O   : out std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
        BETA_I   : out std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
        Q_I    : out std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
        PHI_I  : out std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

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
	end component AXI_SVM_slave_lite_v1_0_S0_AXI_PARAMETROS;

	component SVM_Wrapper is
    port(
        i_clk    : in std_logic; --! Reloj de sistema
        i_enable : in std_logic; --! Habilitacion del modulador
        i_al_o   : in std_logic_vector(10 downto 0); --! Angulo alpha de la corriente de salida
        i_be_i   : in std_logic_vector(10 downto 0); --! Angulo beta de la tension de entrada
        i_q_i    : in std_logic_vector(8 downto 0);  --! Voltage Transfer Ratio
        i_phi_i  : in std_logic_vector(10 downto 0); --! Desfasaje entre corriente de salida y tension de entrada a la matriz

        o_fin_ciclo    : out std_logic;                    
        o_inicio_ciclo : out std_logic;                    
        o_fin_calc_ts  : out std_logic;

        --Tensiones 
        i_U : in std_logic_vector(31 downto 0);
        i_V : in std_logic_vector(31 downto 0);
        i_W : in std_logic_vector(31 downto 0);
        
        o_U : out std_logic_vector(31 downto 0);
        o_V : out std_logic_vector(31 downto 0);
        o_W : out std_logic_vector(31 downto 0)
    );
    end component SVM_Wrapper;
    
	--Control del SVM
    signal alpha_o : std_logic_vector(10 downto 0);
	signal beta_i : std_logic_vector(10 downto 0);
    signal q_tension : std_logic_vector(8 downto 0) := "100000000";
    signal phi_entrada : std_logic_vector(10 downto 0) := "00000000000";
    
begin

-- Instantiation of Axi Bus Interface S0_AXI_PARAMETROS
AXI_SVM_slave_lite_v1_0_S0_AXI_PARAMETROS_inst : AXI_SVM_slave_lite_v1_0_S0_AXI_PARAMETROS
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S0_AXI_PARAMETROS_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S0_AXI_PARAMETROS_ADDR_WIDTH
	)
	port map (
	    CONTROL_REG => open,
	    ALPHA_O => alpha_o,
	    BETA_I => beta_i,
	    Q_I => q_tension,
	    PHI_I => phi_entrada,
	    
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

-- Add user logic here
SVM_Wrapper_inst : SVM_Wrapper
    port map (
            i_clk    => axi_aclk,
            i_enable => enable,
            i_al_o   => alpha_o,
            i_be_i   => beta_i,
            i_q_i    => q_tension, 
            i_phi_i  => phi_entrada,
    
            o_fin_ciclo    => fin_ciclo,
            o_inicio_ciclo => inicio_ciclo,
            o_fin_calc_ts  => fin_calc_ts,
    
            i_U => i_U,
            i_V => i_V,
            i_W => i_W,
    
            o_U => o_U,
            o_V => o_V,
            o_W => o_W
        );

--Señales de salida
	alpha_out <= alpha_o;
	beta_inp <= beta_i;
	q_inp <= q_tension;
	phi_inp <= phi_entrada;

end arch_imp;
