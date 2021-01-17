
library IEEE;
use IEEE.STD_LOGIC_1164.all;
entity M_Sensor1_Controller is
  generic (
    GSlaveAddr : std_logic_vector(6 downto 0) := "1000000";
    PISysEnable     :  std_logic := '1'
  );
  port (
    PISysClk        : in std_logic;
    PIOSysSDA       : inout std_logic;
    PIOSysSCL       : inout std_logic
  );
end M_Sensor1_Controller;

architecture Behavioral of M_Sensor1_Controller is

  component M_I2C_Controller is
    generic (
      G_SysClk : integer := 100_000_000;
      G_BusClk : integer := 100_000);

    port (
      PIClk         : in std_logic;
      PIOSDA        : inout std_logic;
      PIOSCL        : inout std_logic;
      PIEnable      : in std_logic;
      PIReset       : in std_logic;
      PISlaveAddr   : in std_logic_vector(6 downto 0);
      PICommandAddr : in std_logic_vector(7 downto 0);
      POBusy        : out std_logic;
      PODouble      : out std_logic_vector(15 downto 0)
    );
  end component;

  type machine_command is (temp, hum);
  signal state_command : machine_command := temp;
  
  type machine is (start, read, stop);
  signal state : machine := start;

  signal SCommandAddr : std_logic_vector(7 downto 0) := (others => '0');
  signal SBusy   : std_logic;
  signal  SReset       : std_logic;

  signal SEnable      : std_logic;
  signal STempData    : std_logic_vector(15 downto 0);
  signal SHumData     : std_logic_vector(15 downto 0);
  signal SDoubleData  : std_logic_vector(15 downto 0);
  signal SPrevBusy    : std_logic;

  signal POSysTemHumData : std_logic_vector(31 downto 0);
  signal POSysDataReady  : std_logic;

  attribute mark_debug : string;
  attribute mark_debug of POSysDataReady : signal is "true";
  attribute mark_debug of POSysTemHumData : signal is "true";
  

begin

process (PISysClk)
begin
if (PISysClk'event and PISysClk = '1') then
    if PISysEnable = '1' then
        case state is
            when start =>
                POSysDataReady <= '0';
                state_command <= temp;
                SReset <= '1';
                state <= read;
            
            when read =>
                SPrevBusy <= SBusy;
                case state_command is
                    when temp =>
                        SEnable      <= '1';
                        SCommandAddr <= x"E3";
                        if (SBusy = '0' and SPrevBusy = '1') then
                        STempData <= SDoubleData;
                        SReset <= '0';
                        state_command <= hum;
                        end if;

                    when hum  =>
                        SReset <= '1';
                        SCommandAddr <= x"E5";
                        if (SBusy = '0' and SPrevBusy = '1') then
                        SHumData <= SDoubleData;
                        SEnable <= '0';
                        SReset <= '0';
                        state <= stop;
                        end if;
                end case;
            when stop =>
                POSysDataReady <= '1';
                POSysTemHumData <= STempData & SHumData;
                state <= start;
            
            end case;
    end if;
end if;
end process;

I2C_Master_Controller : M_I2C_Controller
port map(
  PIClk         => PISysClk,
  PIOSDA        => PIOSysSDA,
  PIOSCL        => PIOSysSCL,
  PIReset       => SReset,
  PISlaveAddr   => GSlaveAddr,
  PICommandAddr => SCommandAddr,
  POBusy        => SBusy,
  PIEnable      => SEnable,
  PODouble      => SDoubleData
);

end Behavioral;