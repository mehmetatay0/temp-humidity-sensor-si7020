
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity M_I2C_Controller is
  generic (
    GSysClk : integer := 100_000_000;
    GBusClk : integer := 100_000);

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
end M_I2C_Controller;

architecture Behavioral of M_I2C_Controller is

  component I2CMaster is
    generic (
      input_clk : integer := 100_000_000;
      bus_clk   : integer := 100_000);
    port (
      clk       : in std_logic;
      reset_n   : in std_logic;
      ena       : in std_logic;
      addr      : in std_logic_vector(6 downto 0);
      rw        : in std_logic;
      data_wr   : in std_logic_vector(7 downto 0);
      busy      : out std_logic;
      data_rd   : out std_logic_vector(7 downto 0);
      ack_error : buffer std_logic;
      sda       : inout std_logic;
      scl       : inout std_logic);
  end component;

  type machine is(ready, start, set_command, read_data, output_result);
  signal state             : machine;
  signal SAddr             : std_logic_vector(6 downto 0);
  signal SRW               : std_logic;
  signal SDataWr           : std_logic_vector(7 downto 0);
  signal SBusy             : std_logic;
  signal SDataRd           : std_logic_vector(7 downto 0);
  signal SEnable           : std_logic;
  signal SBusyPrev         : std_logic;
  signal SDoubleDataBuffer : std_logic_vector(15 downto 0);
  signal SAckError         : std_logic;

begin

  process (PIClk, PIReset)
    variable busy_cnt : integer range 0 to 2           := 0;
    variable counter  : integer range 0 to GSysClk/10 := 0;
  begin
      if (PIReset = '0') then
        counter := 0;
        SEnable <= '0';
        busy_cnt := 0;
        PODouble    <= (others => '0');
        state       <= ready;
        POBusy <= '0';
      elsif (PIClk'EVENT and PIClk = '1') then
        case state is

          when ready =>
            if (PIEnable = '1') then
              state <= start;
              POBusy <= '1';
            else
              state <= ready;
            end if;
          
          when start =>
            if (counter < GSysClk/10) then
              counter := counter + 1;
            else
              counter := 0;
              state <= set_command;
            end if;

          -- push to command
          when set_command =>
            SBusyPrev <= SBusy;

            if (SBusyPrev = '0' and SBusy = '1') then
              busy_cnt := busy_cnt + 1;
            end if;
            case busy_cnt is
              when 0 =>
                SEnable <= '1';
                SAddr   <= PISlaveAddr;
                SRW     <= '0';   --write
                SDataWr <= PICommandAddr;
              when 1 =>
                SEnable <= '0';
                if (SBusy = '0') then
                  busy_cnt := 0;
                  state <= read_data;
                end if;
              when others => null;
            end case;

          -- reading operation
          when read_data =>
            SBusyPrev   <= SBusy;
            POBusy  <= '1';

            if (SBusyPrev = '0' and SBusy = '1') then
              busy_cnt := busy_cnt + 1;
            end if;
            case busy_cnt is
              when 0 =>
                SEnable <= '1';
                SAddr   <= PISlaveAddr;
                SRW     <= '1';     -- read
              when 1 =>
                if (SBusy = '0') then
                  SDoubleDataBuffer(15 downto 8) <= SDataRd;
                end if;
              when 2 =>
                SEnable <= '0';
                if (SBusy = '0') then
                  SDoubleDataBuffer(7 downto 0) <= SDataRd;
                  busy_cnt := 0;
                  state <= output_result;
                end if;
              when others => null;
            end case;

            --output the temperature or humidity data
          when output_result =>
            PODouble    <= SDoubleDataBuffer(15 downto 0);
            POBusy <= '0';
            if (PIEnable = '0') then    -- if en => 1 then that is continue to read 
              state <= ready;
            else
              state <= read_data;
            end if;

          when others =>
            state <= ready;

        end case;
      end if;
  end process;

  Master : I2CMaster
  generic map(
    input_clk => GSysClk,
    bus_clk   => GBusClk)

  port map(
    clk       => PIClk,
    reset_n   => PIReset,
    ena       => SEnable,
    addr      => SAddr,
    rw        => SRW,
    data_wr   => SDataWr,
    busy      => SBusy,
    data_rd   => SDataRd,
    ack_error => SAckError,
    sda       => PIOSDA,
    scl       => PIOSCL
  );

end Behavioral;