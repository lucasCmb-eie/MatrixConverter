library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXI_TriRL_master_stream_v1_0_M0_AXIS_CORRIENTES is
	generic (
		-- Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
		C_M_AXIS_TDATA_WIDTH	: integer	:= 128
	);
	port (

		--Corrientes de carga que se envian
		CORRIENTE_U : in std_logic_vector(31 downto 0);
		CORRIENTE_V : in std_logic_vector(31 downto 0);
		CORRIENTE_W : in std_logic_vector(31 downto 0);
		
		--Pulso muestreo
        ENVIAR_DATOS : std_logic;

		-- Global ports
		M_AXIS_ACLK	: in std_logic;
		-- 
		M_AXIS_ARESETN	: in std_logic;
		-- Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
		M_AXIS_TVALID	: out std_logic;
		-- TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
		M_AXIS_TDATA	: out std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
		-- TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
		M_AXIS_TSTRB	: out std_logic_vector((C_M_AXIS_TDATA_WIDTH/8)-1 downto 0);
		-- TLAST indicates the boundary of a packet.
		M_AXIS_TLAST	: out std_logic;
		-- TREADY indicates that the slave can accept a transfer in the current cycle.
		M_AXIS_TREADY	: in std_logic
	);
end AXI_TriRL_master_stream_v1_0_M0_AXIS_CORRIENTES;

architecture implementation of AXI_TriRL_master_stream_v1_0_M0_AXIS_CORRIENTES is
	
	
	constant ZERO : std_logic_vector(31 downto 0) := (others => '0');                                                                                                                                                        
	-- Define the states of state machine                                             
	-- The control state machine oversees the writing of input streaming data to the FIFO,
	-- and outputs the streaming data from the FIFO                                   
	type t_state is ( IDLE,        -- This is the initial/idle state     
	                SEND_STREAM);  -- In this state the                               
	                             -- stream data is output through M_AXIS_TDATA        
	                             
	-- State variable                                                                 
	signal  state : t_state := IDLE;  
	 
	signal tvalid_reg : std_logic := '0';
    signal tlast_reg  : std_logic := '0';
    signal tdata_reg : std_logic_vector(C_M_AXIS_TDATA_WIDTH - 1 downto 0);

    signal enviar_datos_sync : std_logic := '0';
    signal enviar_datos_prev : std_logic := '0';
    signal enviar_datos_pulse : std_logic := '0';

begin
	------------------------------------------------------------
    -- Sincronización + detección de flanco del pulso
    ------------------------------------------------------------
    process(M_AXIS_ACLK)
    begin
        if rising_edge(M_AXIS_ACLK) then
            if M_AXIS_ARESETN = '0' then
                enviar_datos_sync <= '0';
                enviar_datos_prev <= '0';
            else
                enviar_datos_sync <= ENVIAR_DATOS;
                enviar_datos_prev <= enviar_datos_sync;
            end if;
        end if;
    end process;

    enviar_datos_pulse <= '1' when (enviar_datos_sync = '1' and enviar_datos_prev = '0') else '0';

	-- Control state machine implementation                                               
	process(M_AXIS_ACLK)                                                                        
	begin                                                                                       
	  if (rising_edge (M_AXIS_ACLK)) then                                                       
	    if(M_AXIS_ARESETN = '0') then  
	       state <= IDLE;
           tvalid_reg <= '0';
           tlast_reg  <= '0';   
                                                         
	    else                                                                                    
	      case (state) is                                                              
	        when IDLE =>                                                       
	            -- Esperamos un pulso de muestreo
                tvalid_reg <= '0';
                tlast_reg  <= '0';
                if enviar_datos_pulse = '1' then
                    -- Preparar datos y activar TVALID
                    tvalid_reg <= '1';
                    tlast_reg  <= '1';
                    tdata_reg <= (others => '0');
                    state <= SEND_STREAM;
                end if;
	                                                                                  
	        when SEND_STREAM  =>                                             
	           -- Esperamos que el receptor acepte los datos
               if tvalid_reg = '1' and M_AXIS_TREADY = '1' then
                   -- Transferencia completada
                   tvalid_reg <= '0';
                   tlast_reg  <= '0';
                   tdata_reg <= ZERO & CORRIENTE_U & CORRIENTE_V & CORRIENTE_W;
                   state <= IDLE;
               end if;                                                     
	                                                                                          
	      end case;                                                                             
	    end if;                                                                                 
	  end if;                                                                                   
	end process;                                                                                

	-- TDATA siempre disponible cuando TVALID=1
    M_AXIS_TDATA <= tdata_reg;
    -- 96/8 = 12 bytes → STRB = 12 valid (1) + padding si fuese 128b
    M_AXIS_TSTRB <= (others => '1');
    M_AXIS_TVALID <= tvalid_reg;
    M_AXIS_TLAST  <= tlast_reg;

end implementation;
