library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_Modulador_v1_0 is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S_AXI_DIRECCS
		C_S_AXI_DIRECCS_TDATA_WIDTH	: integer	:= 32;

		-- Parameters of Axi Slave Bus Interface S_AXI_PARAMS
		C_S_AXI_PARAMS_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_PARAMS_ADDR_WIDTH	: integer	:= 5
	);
	port (
		-- Users to add ports here

		-- User ports ends
		-- Do not modify the ports beyond this line


		-- Ports of Axi Slave Bus Interface S_AXI_DIRECCS
		s_axi_direccs_aclk	: in std_logic;
		s_axi_direccs_aresetn	: in std_logic;
		s_axi_direccs_tready	: out std_logic;
		s_axi_direccs_tdata	: in std_logic_vector(C_S_AXI_DIRECCS_TDATA_WIDTH-1 downto 0);
		s_axi_direccs_tstrb	: in std_logic_vector((C_S_AXI_DIRECCS_TDATA_WIDTH/8)-1 downto 0);
		s_axi_direccs_tlast	: in std_logic;
		s_axi_direccs_tvalid	: in std_logic;

		-- Ports of Axi Slave Bus Interface S_AXI_PARAMS
		s_axi_params_aclk	: in std_logic;
		s_axi_params_aresetn	: in std_logic;
		s_axi_params_awaddr	: in std_logic_vector(C_S_AXI_PARAMS_ADDR_WIDTH-1 downto 0);
		s_axi_params_awprot	: in std_logic_vector(2 downto 0);
		s_axi_params_awvalid	: in std_logic;
		s_axi_params_awready	: out std_logic;
		s_axi_params_wdata	: in std_logic_vector(C_S_AXI_PARAMS_DATA_WIDTH-1 downto 0);
		s_axi_params_wstrb	: in std_logic_vector((C_S_AXI_PARAMS_DATA_WIDTH/8)-1 downto 0);
		s_axi_params_wvalid	: in std_logic;
		s_axi_params_wready	: out std_logic;
		s_axi_params_bresp	: out std_logic_vector(1 downto 0);
		s_axi_params_bvalid	: out std_logic;
		s_axi_params_bready	: in std_logic;
		s_axi_params_araddr	: in std_logic_vector(C_S_AXI_PARAMS_ADDR_WIDTH-1 downto 0);
		s_axi_params_arprot	: in std_logic_vector(2 downto 0);
		s_axi_params_arvalid	: in std_logic;
		s_axi_params_arready	: out std_logic;
		s_axi_params_rdata	: out std_logic_vector(C_S_AXI_PARAMS_DATA_WIDTH-1 downto 0);
		s_axi_params_rresp	: out std_logic_vector(1 downto 0);
		s_axi_params_rvalid	: out std_logic;
		s_axi_params_rready	: in std_logic
	);
end AXI_Modulador_v1_0;

architecture arch_imp of AXI_Modulador_v1_0 is

	-- component declaration
	component AXI_Modulador_v1_0_S_AXI_DIRECCS is
		generic (
		C_S_AXIS_TDATA_WIDTH	: integer	:= 32
		);
		port (
		S_AXIS_ACLK	: in std_logic;
		S_AXIS_ARESETN	: in std_logic;
		S_AXIS_TREADY	: out std_logic;
		S_AXIS_TDATA	: in std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0);
		S_AXIS_TSTRB	: in std_logic_vector((C_S_AXIS_TDATA_WIDTH/8)-1 downto 0);
		S_AXIS_TLAST	: in std_logic;
		S_AXIS_TVALID	: in std_logic
		);
	end component AXI_Modulador_v1_0_S_AXI_DIRECCS;

	component AXI_Modulador_v1_0_S_AXI_PARAMS is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 5
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
		S_AXI_RREADY	: in std_logic
		);
	end component AXI_Modulador_v1_0_S_AXI_PARAMS;

begin

-- Instantiation of Axi Bus Interface S_AXI_DIRECCS
AXI_Modulador_v1_0_S_AXI_DIRECCS_inst : AXI_Modulador_v1_0_S_AXI_DIRECCS
	generic map (
		C_S_AXIS_TDATA_WIDTH	=> C_S_AXI_DIRECCS_TDATA_WIDTH
	)
	port map (
		S_AXIS_ACLK	=> s_axi_direccs_aclk,
		S_AXIS_ARESETN	=> s_axi_direccs_aresetn,
		S_AXIS_TREADY	=> s_axi_direccs_tready,
		S_AXIS_TDATA	=> s_axi_direccs_tdata,
		S_AXIS_TSTRB	=> s_axi_direccs_tstrb,
		S_AXIS_TLAST	=> s_axi_direccs_tlast,
		S_AXIS_TVALID	=> s_axi_direccs_tvalid
	);

-- Instantiation of Axi Bus Interface S_AXI_PARAMS
AXI_Modulador_v1_0_S_AXI_PARAMS_inst : AXI_Modulador_v1_0_S_AXI_PARAMS
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S_AXI_PARAMS_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S_AXI_PARAMS_ADDR_WIDTH
	)
	port map (
		S_AXI_ACLK	=> s_axi_params_aclk,
		S_AXI_ARESETN	=> s_axi_params_aresetn,
		S_AXI_AWADDR	=> s_axi_params_awaddr,
		S_AXI_AWPROT	=> s_axi_params_awprot,
		S_AXI_AWVALID	=> s_axi_params_awvalid,
		S_AXI_AWREADY	=> s_axi_params_awready,
		S_AXI_WDATA	=> s_axi_params_wdata,
		S_AXI_WSTRB	=> s_axi_params_wstrb,
		S_AXI_WVALID	=> s_axi_params_wvalid,
		S_AXI_WREADY	=> s_axi_params_wready,
		S_AXI_BRESP	=> s_axi_params_bresp,
		S_AXI_BVALID	=> s_axi_params_bvalid,
		S_AXI_BREADY	=> s_axi_params_bready,
		S_AXI_ARADDR	=> s_axi_params_araddr,
		S_AXI_ARPROT	=> s_axi_params_arprot,
		S_AXI_ARVALID	=> s_axi_params_arvalid,
		S_AXI_ARREADY	=> s_axi_params_arready,
		S_AXI_RDATA	=> s_axi_params_rdata,
		S_AXI_RRESP	=> s_axi_params_rresp,
		S_AXI_RVALID	=> s_axi_params_rvalid,
		S_AXI_RREADY	=> s_axi_params_rready
	);

	-- Add user logic here

	-- User logic ends

end arch_imp;
