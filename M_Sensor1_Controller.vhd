
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;

entity M_Sensor1_Controller is
  generic (
    GSlaveAddr : std_logic_vector(6 downto 0) := "1000000"
  );
  port (
    PISysClk        : in std_logic;
    PIOSysSDA       : inout std_logic;
    PIOSysSCL       : inout std_logic;
    PISysEnable     : in std_logic;
    PISysReset      : in std_logic;
    PIAlarmReset    : in std_logic;
    POSysTemHumData : out std_logic_vector(31 downto 0);
    POSysDataReady  : out std_logic;
    POAlarm         : out std_logic_vector(1 downto 0)
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
  signal SBusy        : std_logic;
  signal SReset       : std_logic;
  signal SEnable      : std_logic;
  signal STempData    : std_logic_vector(15 downto 0);
  signal SHumData     : std_logic_vector(15 downto 0);
  signal SDoubleData  : std_logic_vector(15 downto 0);
  signal SPrevBusy    : std_logic;
  signal SAlarmCounter : integer range 0 to 100_000_000 := 0;
  signal SAlarmClk    : std_logic := '0';
  signal SAlarmCheckData : std_logic_vector(31 downto 0);
  signal temprealvalue_fixed : integer;
  signal temprealvalue : integer;
  signal humrealvalue_fixed : integer;
  signal humrealvalue : integer;
  signal STempHumBuffer : std_logic_vector(31 downto 0);


  attribute mark_debug                         : string;
  attribute mark_debug of temprealvalue_fixed : signal is "true";
  attribute mark_debug of humrealvalue_fixed : signal is "true";
  attribute mark_debug of SAlarmClk : signal is "true";

begin

  process (PISysClk, PISysReset)
  begin
    if (PISysReset = '0') then
    state <= start;
    state_command <= temp;
    POSysDataReady <= '0';
    SReset <= '0';
    SCommandAddr <= (others => '0');
    STempData <= (others => '0');
    SHumData  <= (others => '0');
    elsif (PISysClk'event and PISysClk = '1') then
        case state is
          when start =>
          if PISysEnable = '1' then
            POSysDataReady <= '0';
            SAlarmClk       <= '0';
            state_command  <= temp;
            SReset         <= '1';
            state          <= read;
          else
            POSysDataReady <= '0';
            SAlarmClk       <= '0';
            SReset         <= '0';
            state <= start;
          end if;
          when read =>
            SPrevBusy <= SBusy;
            case state_command is
              when temp =>
                SEnable      <= '1';
                SCommandAddr <= x"E3";
                if (SBusy = '0' and SPrevBusy = '1') then
                  STempData     <= SDoubleData;
                  SReset        <= '0';
                  state_command <= hum;
                end if;

              when hum =>
                SReset       <= '1';
                SCommandAddr <= x"E5";
                if (SBusy = '0' and SPrevBusy = '1') then
                  SHumData <= SDoubleData;
                  SEnable  <= '0';
                  SReset   <= '0';
                  state    <= stop;
                end if;
            end case;
          when stop =>
            POSysDataReady  <= '1';
            SAlarmClk       <= '1';
            POSysTemHumData <= STempData & SHumData;
            STempHumBuffer <= STempData & SHumData;
            state           <= start;
        end case;
    end if;
  end process;


  -- ALARM_CLK : process (PISysClk, PISysReset)
  -- begin
  --   if (PISysReset = '0') then
  --   SAlarmCounter <= 0;
  --   elsif PISysClk'event and PISysClk = '1' then
  --       if SAlarmCounter = 50_000_000 then        --1sn Clk
  --         SAlarmClk <= not SAlarmClk;
  --         SAlarmCounter <= 0;
  --       else
  --       SAlarmCounter <= SAlarmCounter + 1;
  --       end if;
  --   end if;
  -- end process;

  -- ALARM_CHECK_DATA : process (SAlarmClk, PISysReset)
  -- begin
  --   if (PISysReset = '0') then
  --   SAlarmCheckData <= (others => '0');

  --   elsif SAlarmClk'event and SAlarmClk = '0' then
  --     SAlarmCheckData <= STempData & SHumData;
  --   end if;
  -- end process;

  ALARM_CHECK : process (PISysClk, SAlarmClk, PISysReset)
  begin
    if (PISysReset = '0') then

    elsif SAlarmClk'event and SAlarmClk = '1' then
      temprealvalue <= to_integer(unsigned(STempHumBuffer(31 downto 16)));
      temprealvalue_fixed <= (temprealvalue*17572) / 6553600 - 47;

      humrealvalue <= to_integer(unsigned(STempHumBuffer(15 downto 0)));
      humrealvalue_fixed <= (humrealvalue*125) / 65536 - 6;    

        if temprealvalue_fixed > 30 then
          POAlarm(1) <= '1';
        elsif temprealvalue_fixed < 0 then
          POAlarm(1) <= '1';
        end if;

        if (humrealvalue_fixed < 20) then 
          POAlarm(0) <= '1';
        elsif (humrealvalue_fixed > 50) then
          POAlarm(0) <= '1';
        end if;
    end if;
    if PISysClk'event and PISysClk = '1' then     --reset operation
      if PIAlarmReset = '1' then
        POAlarm <= (others => '0');
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