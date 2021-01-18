
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity M_Top is
generic (
    GSysClk : integer := 100_000_000
);
  port (
    PIClk  : in std_logic;
    PIOSDA : inout std_logic;
    PIOSCL : inout std_logic;
    POTX   : out std_logic
  );
end M_Top;

architecture Behavioral of M_Top is

  component M_Sensor1_Controller is
    generic (
      GSlaveAddr : std_logic_vector(6 downto 0) := "1000000"
    );
    port (
      PISysClk        : in std_logic;
      PIOSysSDA       : inout std_logic;
      PIOSysSCL       : inout std_logic;
      PISysEnable     : in std_logic;
      POSysTemHumData : out std_logic_vector(31 downto 0);
      POSysDataReady  : out std_logic
    );
  end component;

  component UART_TX is
    generic (
      GI_SysCLK   : integer := 100_000_000;
      GI_BaudRate : integer := 9_600
    );
    port (
      PI_SysCLK : in std_logic;
      PI_Data   : in std_logic_vector(7 downto 0);
      PI_Rst    : in std_logic;
      PI_TxEn   : in std_logic;
      PO_Tx     : out std_logic;
      PO_TxBusy : out std_logic
    );
  end component;

  signal SSensor1En       : std_logic;
  signal SSensorDataOut   : std_logic_vector(31 downto 0);
  signal SSensorDataReady : std_logic;

  signal SSensorDataOutBuffer : std_logic_vector(31 downto 0);

  signal STxData     : std_logic_vector(7 downto 0);
  signal STxReset    : std_logic;
  signal STxEn       : std_logic;
  signal STxBusy     : std_logic;
  signal STxPrevBusy : std_logic;
  type machine is (delay, sensordata, uarttx);
  signal state : machine := sensordata;

  type txmachine is (data1, data2, data3, data4);
  signal txstate : txmachine := data1;

  attribute mark_debug                         : string;
  attribute mark_debug of SSensorDataReady     : signal is "true";
  attribute mark_debug of SSensorDataOut       : signal is "true";
  attribute mark_debug of SSensorDataOutBuffer : signal is "true";

begin

  STxReset <= '1';

  process (PIClk)
  variable counter  : integer range 0 to GSysClk := 0;
  begin
    if PIClk'event and PIClk = '1' then
      case state is

        when delay => 
            if (counter < GSysClk) then     -- 1sn delay
              counter := counter + 1;
            else
              counter := 0;
              state <= sensordata;
            end if;

        when sensordata =>
          SSensor1En <= '1';
          if (SSensorDataReady = '1') then
            SSensor1En <= '0';
            SSensorDataOutBuffer <= SSensorDataOut;
            state                <= uarttx;
            txstate              <= data1;
          end if;

        when uarttx =>
        STxPrevBusy <= STxBusy;
          case txstate is
            when data1 =>
              STxEn   <= '1';
              STxData <= SSensorDataOutBuffer(31 downto 24);
              if STxBusy = '0' and STxPrevBusy = '1' or STxPrevBusy = '0' then
                    STxEn   <= '0';
                    txstate <= data2;
              end if;
            when data2 =>
              STxEn   <= '1';
              STxData <= SSensorDataOutBuffer(23 downto 16);
              if STxBusy = '0' and STxPrevBusy = '1' then
                txstate <= data3;
                STxEn   <= '0';
              end if;
            when data3 =>
              STxEn   <= '1';
              STxData <= SSensorDataOutBuffer(15 downto 8);
              if STxBusy = '0' and STxPrevBusy = '1' then
                txstate <= data4;
                STxEn   <= '0';
              end if;
            when data4 =>
              STxEn   <= '1';
              STxData <= SSensorDataOutBuffer(7 downto 0);
              if STxBusy = '0' and STxPrevBusy = '1' then
                state <= delay;
                STxEn <= '0';
              end if;
            when others =>
              null;
          end case;

        when others =>
          null;
      end case;
    end if;
  end process;

  Sensor1Controller : M_Sensor1_Controller
  port map(
    PISysClk        => PIClk,
    PIOSysSDA       => PIOSDA,
    PIOSysSCL       => PIOSCL,
    PISysEnable     => SSensor1En,
    POSysTemHumData => SSensorDataOut,
    POSysDataReady  => SSensorDataReady
  );

  UART_Transmitter : UART_TX
  port map(
    PI_SysCLK => PIClk,
    PI_Data   => STxData,
    PI_Rst    => STxReset,
    PI_TxEn   => STxEn,
    PO_Tx     => POTX,
    PO_TxBusy => STxBusy
  );
end Behavioral;