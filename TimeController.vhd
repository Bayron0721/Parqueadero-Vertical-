library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TimeController is
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        start_door_timer : in STD_LOGIC;
        door_timeout : out STD_LOGIC;
        door_timer_active : out STD_LOGIC;
        door_time_left : out integer range 0 to 99;
        servo_open : out STD_LOGIC;
        servo_close : out STD_LOGIC;
        parking_timer_active : out STD_LOGIC;
        parking_time_left : out integer range 0 to 99;
        start_stepper_motor : out STD_LOGIC;
        tick_1Hz : out STD_LOGIC
    );
end TimeController;

architecture Behavioral of TimeController is
    -- Constantes y contadores
    constant CNT_1S_MAX : integer := 49999999; -- 50 MHz -> 1 Hz
    signal counter_1Hz : integer range 0 to CNT_1S_MAX := 0;
    signal second_pulse : STD_LOGIC := '0';

    -- Timer de puerta (primer timer)
    signal door_counter : integer range 0 to 99 := 0;
    signal door_active : STD_LOGIC := '0';
    signal door_timeout_pulse : STD_LOGIC := '0';

    -- Timer de parking (segundo timer)
    signal parking_counter : integer range 0 to 99 := 0;
    signal parking_active : STD_LOGIC := '0';
    signal parking_timeout_pulse : STD_LOGIC := '0';

    -- Detección de flanco rising-edge de start_door_timer (2-FF)
    signal start_sync : STD_LOGIC_VECTOR(1 downto 0) := "00";
    signal start_detected : STD_LOGIC := '0';

    -- Señal registrada para arrancar el stepper
    signal start_stepper_r : STD_LOGIC := '0';

begin
    ----------------------------------------------------------------
    -- Generador 1 Hz (pulso de 1 ciclo) y exportar tick_1Hz
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            counter_1Hz <= 0;
            second_pulse <= '0';
        elsif rising_edge(clk) then
            second_pulse <= '0';
            if counter_1Hz >= CNT_1S_MAX then
                counter_1Hz <= 0;
                second_pulse <= '1';
            else
                counter_1Hz <= counter_1Hz + 1;
            end if;
        end if;
    end process;

    tick_1Hz <= second_pulse;

    ----------------------------------------------------------------
    -- Sincronización / detección de flanco de start_door_timer
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            start_sync <= "00";
            start_detected <= '0';
        elsif rising_edge(clk) then
            start_sync <= start_sync(0) & start_door_timer; -- {prev, curr}
            if start_sync = "01" then
                start_detected <= '1';
            else
                start_detected <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Control de timers (primer timer = door, segundo = parking)
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            door_counter <= 0;
            door_active <= '0';
            door_timeout_pulse <= '0';
            parking_counter <= 0;
            parking_active <= '0';
            parking_timeout_pulse <= '0';
            start_stepper_r <= '0';
        elsif rising_edge(clk) then
            -- por defecto limpiar pulsos registrados cada ciclo
            door_timeout_pulse <= '0';
            parking_timeout_pulse <= '0';
            start_stepper_r <= '0';

            -- Inicio primer timer por flanco detectado
            if start_detected = '1' and door_active = '0' and parking_active = '0' then
                door_counter <= 5;  -- 10 segundos para pruebas (ajustable)
                door_active <= '1';
            elsif door_active = '1' and second_pulse = '1' then
                if door_counter > 0 then
                    door_counter <= door_counter - 1;
                else
                    door_active <= '0';
                    door_timeout_pulse <= '1'; -- indicar apertura de puerta
                    -- Iniciar segundo timer de parking inmediatamente
                    parking_counter <= 5;     -- 10 segundos para pruebas (ajustable)
                    parking_active <= '1';
                end if;
            end if;

            -- Segundo timer: parking countdown
            if parking_active = '1' and second_pulse = '1' then
                if parking_counter > 0 then
                    parking_counter <= parking_counter - 1;
                else
                    parking_active <= '0';
                    parking_timeout_pulse <= '1'; -- indicar cierre de puerta
                    start_stepper_r <= '1';       -- pulso registrado para arrancar stepper
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Salidas
    ----------------------------------------------------------------
    door_timeout <= door_timeout_pulse;
    door_timer_active <= door_active;
    door_time_left <= door_counter when door_active = '1' else 0;
    servo_open <= door_timeout_pulse;
    servo_close <= parking_timeout_pulse;
    start_stepper_motor <= start_stepper_r;
    parking_timer_active <= parking_active;
    parking_time_left <= parking_counter;

end Behavioral;