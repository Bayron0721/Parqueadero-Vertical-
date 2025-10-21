library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ParkingController is
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        vehicle_present : in STD_LOGIC;

        start_door_timer : out STD_LOGIC;
        door_timeout : in STD_LOGIC;

        start_slot_idx : out STD_LOGIC_VECTOR(3 downto 0);
        start_slot_valid : out STD_LOGIC;

        free_slot_idx  : in  STD_LOGIC_VECTOR(3 downto 0);
        free_slot_valid: in  STD_LOGIC;

        free_slots_out : out STD_LOGIC_VECTOR(9 downto 0);

        led_verde : out STD_LOGIC;
        led_amarillo : out STD_LOGIC;
        led_rojo : out STD_LOGIC
    );
end ParkingController;

architecture Behavioral of ParkingController is
    -- Estados de la FSM
    type simple_state is (IDLE, SPACE_CHECK, COUNTING, WAIT_MOTOR_COMPLETE, COOLDOWN);
    signal state : simple_state := IDLE;

    -- Detección de flanco del sensor de vehículo
    signal vehicle_prev : std_logic := '0';
    signal vehicle_rising_edge : std_logic := '0';

    signal start_pulse_r : std_logic := '0';

    signal free_slots : std_logic_vector(9 downto 0) := (others => '1');
    signal have_slot : std_logic := '0';
    signal assigned_slot : integer range 0 to 9 := 0;

    -- Tiempo de verificación de espacio (2 segundos a 50MHz)
    constant SPACE_CHECK_TIME : integer := 100000000;
    signal space_check_counter : integer range 0 to SPACE_CHECK_TIME := 0;

    -- Tiempo de espera después de completar el proceso (2 segundos a 50MHz)
    constant MOTOR_COMPLETE_TIME : integer := 100000000;
    signal motor_complete_counter : integer range 0 to MOTOR_COMPLETE_TIME := 0;

    -- Tiempo de cooldown para ignorar sensor después de procesar (2 segundos)
    constant COOLDOWN_TIME : integer := 100000000;
    signal cooldown_counter : integer range 0 to COOLDOWN_TIME := 0;

    signal start_slot_idx_r : std_logic_vector(3 downto 0) := (others => '0');
    signal start_slot_valid_r : std_logic := '0';

begin
    process(clk, rst)
        variable i : integer;
        variable free_count : integer := 0;
    begin
        if rst = '1' then
            state <= IDLE;
            start_pulse_r <= '0';
            space_check_counter <= 0;
            motor_complete_counter <= 0;
            cooldown_counter <= 0;
            free_slots <= (others => '1');
            have_slot <= '0';
            assigned_slot <= 0;
            start_slot_idx_r <= (others => '0');
            start_slot_valid_r <= '0';
            vehicle_prev <= '0';
            vehicle_rising_edge <= '0';
        elsif rising_edge(clk) then
            -- Detección de flanco de BAJADA del sensor (1 → 0, sensor activo en bajo)
            vehicle_prev <= vehicle_present;
            if vehicle_present = '0' and vehicle_prev = '1' then  -- ✅ INVERTIDO: detecta 1→0
                vehicle_rising_edge <= '1';
            else
                vehicle_rising_edge <= '0';
            end if;

            -- Por defecto, los pulsos duran 1 ciclo
            start_pulse_r <= '0';
            start_slot_valid_r <= '0';

            -- Actualizar slots libres cuando se recibe señal externa
            if free_slot_valid = '1' then
                i := to_integer(unsigned(free_slot_idx));
                if i >= 0 and i <= 9 then
                    free_slots(i) <= '1';
                    if have_slot = '1' and assigned_slot = i then
                        have_slot <= '0';
                    end if;
                end if;
            end if;

            -- Contar espacios libres
            free_count := 0;
            for i in 0 to 9 loop
                if free_slots(i) = '1' then
                    free_count := free_count + 1;
                end if;
            end loop;

            -- Máquina de estados
            case state is
                -- ESTADO IDLE: Esperando NUEVO vehículo (flanco de bajada)
                when IDLE =>
                    if vehicle_rising_edge = '1' then  -- Solo con NUEVO auto
                        state <= SPACE_CHECK;
                    end if;

                -- ESTADO SPACE_CHECK: Verificando espacio disponible (2 segundos)
                when SPACE_CHECK =>
                    if free_count = 0 then
                        -- No hay espacio, ir a cooldown antes de volver a IDLE
                        state <= COOLDOWN;
                    else
                        if space_check_counter < SPACE_CHECK_TIME then
                            space_check_counter <= space_check_counter + 1;
                        else
                            -- Asignar primer slot libre
                            for i in 0 to 9 loop
                                if free_slots(i) = '1' then
                                    free_slots(i) <= '0';
                                    assigned_slot <= i;
                                    have_slot <= '1';
                                    start_pulse_r <= '1';  -- Iniciar timer de puerta
                                    start_slot_idx_r <= std_logic_vector(to_unsigned(i, 4));
                                    start_slot_valid_r <= '1';
                                    exit;
                                end if;
                            end loop;
                            state <= COUNTING;
                            space_check_counter <= 0;
                        end if;
                    end if;

                -- ESTADO COUNTING: Timer de puerta activo (servo abre, auto entra, servo cierra)
                when COUNTING =>
                    if door_timeout = '1' then
                        -- Timer completado, ahora esperar a que motor complete movimiento
                        state <= WAIT_MOTOR_COMPLETE;
                    end if;

                -- ESTADO WAIT_MOTOR_COMPLETE: Esperar que motor paso a paso complete
                when WAIT_MOTOR_COMPLETE =>
                    if motor_complete_counter < MOTOR_COMPLETE_TIME then
                        motor_complete_counter <= motor_complete_counter + 1;
                    else
                        motor_complete_counter <= 0;
                        state <= COOLDOWN;
                    end if;

                -- ESTADO COOLDOWN: Ignorar sensor por 2 segundos antes de volver a IDLE
                -- Esto permite que el auto se aleje del sensor
                when COOLDOWN =>
                    if cooldown_counter < COOLDOWN_TIME then
                        cooldown_counter <= cooldown_counter + 1;
                    else
                        cooldown_counter <= 0;
                        -- Regresar a IDLE - Sensor nuevamente disponible
                        state <= IDLE;
                    end if;

            end case;
        end if;
    end process;

    -- Indicadores LED
    led_verde <= '1' when state = IDLE else '0';
    led_amarillo <= '1' when (state = SPACE_CHECK or state = COUNTING or 
                              state = WAIT_MOTOR_COMPLETE or state = COOLDOWN) else '0';
    led_rojo <= '1' when free_slots = "0000000000" else '0';

    -- Salidas
    start_door_timer <= start_pulse_r;
    start_slot_idx <= start_slot_idx_r;
    start_slot_valid <= start_slot_valid_r;
    free_slots_out <= free_slots;

end Behavioral;
