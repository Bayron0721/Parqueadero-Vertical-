library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ParkingSystem_TopLevel is
    Port (
        clk_50MHz : in STD_LOGIC;
        rst_btn : in STD_LOGIC;
        vehicle_sensor : in STD_LOGIC;
        kp_row_pins : in  STD_LOGIC_VECTOR(3 downto 0);
        kp_col_drive : out STD_LOGIC_VECTOR(3 downto 0);
        coin_500_pin  : in STD_LOGIC;
        coin_1000_pin : in STD_LOGIC;
        Display_D1 : out STD_LOGIC_VECTOR(6 downto 0);
        Display_D2 : out STD_LOGIC_VECTOR(6 downto 0);
        Display_D3 : out STD_LOGIC_VECTOR(6 downto 0);
        Display_D4 : out STD_LOGIC_VECTOR(6 downto 0);
        LED_VERDE : out STD_LOGIC;
        LED_AMARILLO : out STD_LOGIC;
        LED_ROJO : out STD_LOGIC;
        SERVO_PWM_PIN : out STD_LOGIC;
        STEPPER_A : out STD_LOGIC;
        STEPPER_B : out STD_LOGIC;
        STEPPER_C : out STD_LOGIC;
        STEPPER_D : out STD_LOGIC;
        debug_leds : out STD_LOGIC_VECTOR(7 downto 0);
        SERVO_GIRO_PWM_PIN : out STD_LOGIC
    );
end ParkingSystem_TopLevel;

architecture Structural of ParkingSystem_TopLevel is
    -- SeÃ±ales globales
    signal rst_global : STD_LOGIC;
    signal vehicle_present_i : STD_LOGIC;

    -- TimeController signals
    signal start_door_timer_i : STD_LOGIC;
    signal door_timeout_i : STD_LOGIC;
    signal door_timer_active_i : STD_LOGIC;
    signal door_time_left_i : integer range 0 to 99;
    signal servo_open_sig : STD_LOGIC;
    signal servo_close_sig : STD_LOGIC;
    signal parking_timer_active_i : STD_LOGIC;
    signal parking_time_left_i : integer range 0 to 99;
    signal tick_1Hz_sig : STD_LOGIC;

    -- ParkingTimeManager signals
    signal start_slot_idx_sig : STD_LOGIC_VECTOR(3 downto 0);
    signal start_slot_valid_sig : STD_LOGIC;
    signal stop_slot_idx_sig : STD_LOGIC_VECTOR(3 downto 0);
    signal stop_slot_valid_sig : STD_LOGIC;
    signal read_idx_sig : STD_LOGIC_VECTOR(3 downto 0);
    signal read_valid_sig : STD_LOGIC;
    signal read_time_sig : integer range 0 to 999999;
    signal read_ready_sig : STD_LOGIC;
    signal slot_active_sig : STD_LOGIC_VECTOR(9 downto 0);

    -- ParkingController signals
    signal start_door_timer_ctrl : STD_LOGIC;
    signal free_slot_idx_sig : STD_LOGIC_VECTOR(3 downto 0);
    signal free_slot_valid_sig : STD_LOGIC;
    signal free_slots_export : STD_LOGIC_VECTOR(9 downto 0);
    signal led_verde_sig : STD_LOGIC;
    signal led_amarillo_sig : STD_LOGIC;
    signal led_rojo_sig : STD_LOGIC;

    -- Keypad signals
    signal kp_key_valid : STD_LOGIC;
    signal kp_key_code : STD_LOGIC_VECTOR(3 downto 0);
    signal kp_key_ascii : STD_LOGIC_VECTOR(7 downto 0);

    -- Coin synchronization signals
    signal coin_500_sync1 : STD_LOGIC;
    signal coin_500_sync2 : STD_LOGIC;
    signal coin_500_prev : STD_LOGIC;
    signal coin_1000_sync1 : STD_LOGIC;
    signal coin_1000_sync2 : STD_LOGIC;
    signal coin_1000_prev : STD_LOGIC;

    -- PaymentManager signals (sin usar directamente ahora)
    signal pm_start_payment : STD_LOGIC;
    signal pm_cancel : STD_LOGIC;
    signal pm_coin_500 : STD_LOGIC;
    signal pm_coin_1000 : STD_LOGIC;
    signal amount_due_sig : integer range 0 to 1000000;
    signal pm_balance : integer range 0 to 1000000;
    signal pm_change_out : integer range 0 to 1000000;
    signal pm_payment_confirmed : STD_LOGIC;
    signal pm_payment_pending : STD_LOGIC;
    signal pm_coin_return : STD_LOGIC;

    -- Display signals
    signal display_value : integer range 0 to 9999;
    signal d_tens : integer range 0 to 9;
    signal d_units : integer range 0 to 9;
    signal bcd_high : STD_LOGIC_VECTOR(3 downto 0);
    signal bcd_low : STD_LOGIC_VECTOR(3 downto 0);

    -- Main servo signals
    signal main_servo_open_pulse : std_logic;
    signal main_servo_close_pulse : std_logic;
    signal main_servo_movement_complete_sig : std_logic;
    signal main_servo_in_position_sig : std_logic;

    -- Stepper motor signals
    signal pasogirototal_start : STD_LOGIC;
    signal pasogirototal_busy : STD_LOGIC;
    signal pasogirototal_complete : STD_LOGIC;

    -- SeÃ±ales para PaymentSystem
    signal ps_selected_space : integer range 0 to 10 := 0;
    signal ps_start_timing : STD_LOGIC := '0';
    signal ps_stop_timing : STD_LOGIC := '0';
    signal ps_total_cost : integer range 0 to 720000 := 0;
    signal ps_amount_paid : integer range 0 to 720000 := 0;
    signal ps_change_due : integer range 0 to 720000 := 0;
    signal ps_payment_complete : STD_LOGIC := '0';
    signal ps_payment_pending : STD_LOGIC := '0';

    -- SeÃ±ales de tiempo real desde ParkingTimeManager
    signal parking_time_seconds : integer range 0 to 999999 := 0;
    signal parking_time_minutes : integer range 0 to 16666 := 0;

    -- Display signals para pagos
    signal payment_display_value : integer range 0 to 9999 := 0;
    signal payment_thousands : integer range 0 to 9 := 0;
    signal payment_hundreds : integer range 0 to 9 := 0;
    signal payment_tens : integer range 0 to 9 := 0;
    signal payment_units : integer range 0 to 9 := 0;
    signal payment_bcd_high : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal payment_bcd_low : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');

begin
    -- Asignaciones globales
    rst_global <= rst_btn;
    vehicle_present_i <= vehicle_sensor;
    start_door_timer_i <= start_door_timer_ctrl;

    -- Debug LEDs
    debug_leds(0) <= ps_payment_pending;
    debug_leds(1) <= pasogirototal_busy;
    debug_leds(2) <= slot_active_sig(0);
    debug_leds(3) <= door_timer_active_i;
    debug_leds(4) <= parking_timer_active_i;
    debug_leds(5) <= pm_coin_500;
    debug_leds(6) <= pm_coin_1000;
    debug_leds(7) <= main_servo_in_position_sig;

    -- Salidas finales
    LED_VERDE <= led_verde_sig;
    LED_AMARILLO <= led_amarillo_sig;
    LED_ROJO <= led_rojo_sig;
    free_slots_export <= slot_active_sig;
    SERVO_GIRO_PWM_PIN <= '0';

    -- =====================================================================
    -- SINCRONIZACIÃ“N Y DETECCIÃ“N DE FLANCOS PARA SENSORES DE MONEDAS
    -- =====================================================================
-- =====================================================================
-- SINCRONIZACIÓN Y DETECCIÓN DE FLANCOS PARA SENSORES DE MONEDAS
-- =====================================================================
process(clk_50MHz, rst_global)
begin
    if rst_global = '1' then
        coin_500_sync1 <= '0';
        coin_500_sync2 <= '0';
        coin_500_prev <= '0';
        coin_1000_sync1 <= '0';
        coin_1000_sync2 <= '0';
        coin_1000_prev <= '0';
        pm_coin_500 <= '0';
        pm_coin_1000 <= '0';
    elsif rising_edge(clk_50MHz) then
        -- Sincronización de doble flip-flop
        coin_500_sync1 <= coin_500_pin;
        coin_500_sync2 <= coin_500_sync1;
        coin_500_prev <= coin_500_sync2;

        coin_1000_sync1 <= coin_1000_pin;
        coin_1000_sync2 <= coin_1000_sync1;
        coin_1000_prev <= coin_1000_sync2;

        -- ✅ DETECCIÓN DE FLANCOS DE SUBIDA (0 → 1) - SENSORES ACTIVOS EN ALTO
        if coin_500_sync2 = '1' and coin_500_prev = '0' then
            pm_coin_500 <= '1';
        else
            pm_coin_500 <= '0';
        end if;

        if coin_1000_sync2 = '1' and coin_1000_prev = '0' then
            pm_coin_1000 <= '1';
        else
            pm_coin_1000 <= '0';
        end if;
    end if;
end process;


    -- =====================================================================
    -- SISTEMA DE PAGO (PaymentSystem)
    -- =====================================================================
    U_PaymentSystem: entity work.PaymentSystem
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        selected_space => ps_selected_space,
        parking_time_seconds => parking_time_seconds,  -- âœ… CONECTAR TIEMPO REAL
        space_occupied => slot_active_sig,
        coin_500 => pm_coin_500,
        coin_1000 => pm_coin_1000,
        total_cost => ps_total_cost,
        amount_paid => ps_amount_paid,
        change_due => ps_change_due,
        payment_complete => ps_payment_complete,
        payment_pending => ps_payment_pending,
        start_timing => ps_start_timing,
        stop_timing => ps_stop_timing,
        parking_minutes => open,
        entry_times => open
    );

    -- =====================================================================
    -- CONTROLADOR DE TIEMPO (TimeController)
    -- =====================================================================
    U_TimeController: entity work.TimeController
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        start_door_timer => start_door_timer_i,
        door_timeout => door_timeout_i,
        door_timer_active => door_timer_active_i,
        door_time_left => door_time_left_i,
        servo_open => servo_open_sig,
        servo_close => servo_close_sig,
        parking_timer_active => parking_timer_active_i,
        parking_time_left => parking_time_left_i,
        start_stepper_motor => open,
        tick_1Hz => tick_1Hz_sig
    );

    -- =====================================================================
    -- MOTOR PASO A PASO (pasopasogirototal)
    -- =====================================================================
    U_PasoGiroTotal: entity work.pasopasogirototal
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        start_rotation => pasogirototal_start,
        motor_A => STEPPER_A,
        motor_B => STEPPER_B,
        motor_C => STEPPER_C,
        motor_D => STEPPER_D,
        rotation_complete => pasogirototal_complete,
        motor_busy => pasogirototal_busy
    );

    -- =====================================================================
    -- CONTROLADOR PRINCIPAL FSM (ParkingController)
    -- =====================================================================
    U_ParkingController: entity work.ParkingController
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        vehicle_present => vehicle_present_i,
        start_door_timer => start_door_timer_ctrl,
        door_timeout => door_timeout_i,
        start_slot_idx => start_slot_idx_sig,
        start_slot_valid => start_slot_valid_sig,
        free_slot_idx => free_slot_idx_sig,
        free_slot_valid => free_slot_valid_sig,
        free_slots_out => free_slots_export,
        led_verde => led_verde_sig,
        led_amarillo => led_amarillo_sig,
        led_rojo => led_rojo_sig
    );

    -- =====================================================================
    -- GESTOR DE TIEMPO DE ESPACIOS (ParkingTimeManager)
    -- =====================================================================
    U_ParkingTimeManager: entity work.ParkingTimeManager
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        tick_1Hz => tick_1Hz_sig,
        start_slot => start_slot_idx_sig,
        start_slot_valid => start_slot_valid_sig,
        stop_slot => stop_slot_idx_sig,
        stop_slot_valid => stop_slot_valid_sig,
        reset_slot => (others => '0'),
        reset_slot_valid => '0',
        reset_all => '0',
        read_index => read_idx_sig,
        read_valid => read_valid_sig,
        read_time => read_time_sig,
        read_ready => read_ready_sig,
        slot_active => slot_active_sig
    );

    -- =====================================================================
    -- GESTOR DE PAGOS (PaymentManager) - MANTENIDO PARA COMPATIBILIDAD
    -- =====================================================================

    -- =====================================================================
    -- TECLADO MATRICIAL (Keypad)
    -- =====================================================================
    U_Keypad: entity work.Keypad
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        row_pins => kp_row_pins,
        col_drive => kp_col_drive,
        key_valid => kp_key_valid,
        key_code => kp_key_code,
        key_ascii => kp_key_ascii
    );

    -- =====================================================================
    -- SERVO PRINCIPAL DE BARRERA (Main_servo)
    -- =====================================================================
    U_MainServo: entity work.Main_servo
    port map (
        clk => clk_50MHz,
        rst => rst_global,
        open_door => main_servo_open_pulse,
        close_door => main_servo_close_pulse,
        servo_pwm => SERVO_PWM_PIN,
        servo_movement_complete => main_servo_movement_complete_sig,
        servo_in_position => main_servo_in_position_sig
    );

    -- =====================================================================
    -- PROCESO: GENERACIÃ“N DE PULSOS PARA SERVO Y MOTOR PASO A PASO
    -- =====================================================================
    process(clk_50MHz, rst_global)
        variable prev_servo_open : std_logic := '0';
        variable prev_servo_close : std_logic := '0';
        variable prev_movement_complete : std_logic := '0';
    begin
        if rst_global = '1' then
            main_servo_open_pulse <= '0';
            main_servo_close_pulse <= '0';
            pasogirototal_start <= '0';
            prev_servo_open := '0';
            prev_servo_close := '0';
            prev_movement_complete := '0';
        elsif rising_edge(clk_50MHz) then
            -- Detectar flanco de subida de servo_open_sig
            if servo_open_sig = '1' and prev_servo_open = '0' then
                main_servo_open_pulse <= '1';
            else
                main_servo_open_pulse <= '0';
            end if;

            -- Detectar flanco de subida de servo_close_sig
            if servo_close_sig = '1' and prev_servo_close = '0' then
                main_servo_close_pulse <= '1';
            else
                main_servo_close_pulse <= '0';
            end if;

            -- Iniciar motor paso a paso cuando servo completa movimiento
            if main_servo_movement_complete_sig = '1' and prev_movement_complete = '0' 
               and parking_timer_active_i = '0' then
                pasogirototal_start <= '1';
            else
                pasogirototal_start <= '0';
            end if;

            prev_servo_open := servo_open_sig;
            prev_servo_close := servo_close_sig;
            prev_movement_complete := main_servo_movement_complete_sig;
        end if;
    end process;

    -- =====================================================================
    -- PROCESO: INTEGRACIÃ“N CON PARKINGTIMEMANAGER
    -- Leer tiempo real del slot seleccionado cuando se presiona tecla
    -- =====================================================================
    process(clk_50MHz, rst_global)
        variable read_state : integer range 0 to 2 := 0;
    begin
        if rst_global = '1' then
            read_idx_sig <= (others => '0');
            read_valid_sig <= '0';
            parking_time_seconds <= 0;
            parking_time_minutes <= 0;
            read_state := 0;
        elsif rising_edge(clk_50MHz) then
            read_valid_sig <= '0'; -- Default

            case read_state is
                when 0 => -- IDLE, esperando selecciÃ³n de espacio
                    if ps_stop_timing = '1' and ps_selected_space >= 1 and ps_selected_space <= 10 then
                        -- Solicitar lectura del tiempo del slot seleccionado
                        read_idx_sig <= std_logic_vector(to_unsigned(ps_selected_space - 1, 4));
                        read_valid_sig <= '1';
                        read_state := 1;
                    end if;

                when 1 => -- Esperando respuesta
                    if read_ready_sig = '1' then
                        parking_time_seconds <= read_time_sig;
                        -- Convertir segundos a minutos (redondear hacia arriba)
                        if read_time_sig = 0 then
                            parking_time_minutes <= 1; -- MÃ­nimo 1 minuto
                        else
                            parking_time_minutes <= (read_time_sig + 59) / 60; -- Redondeo hacia arriba
                        end if;
                        read_state := 2;
                    end if;

                when 2 => -- Mantener valor hasta nueva lectura
                    if ps_stop_timing = '0' then
                        read_state := 0;
                    end if;

                when others =>
                    read_state := 0;
            end case;
        end if;
    end process;

    -- =====================================================================
    -- PROCESO: CÃLCULO DE COSTO BASADO EN TIEMPO REAL
    -- =====================================================================
    process(parking_time_minutes)
    begin
        -- Calcular costo: 500 pesos por minuto
        if parking_time_minutes > 1440 then -- MÃ¡ximo 24 horas = 720,000 pesos
            payment_display_value <= 9999; -- Mostrar mÃ¡ximo en display
        else
            payment_display_value <= (parking_time_minutes * 500) / 100; -- Convertir a decenas para display
        end if;
    end process;

    -- =====================================================================
    -- PROCESO: INICIAR CONTEO CUANDO SE ASIGNA SLOT
    -- =====================================================================
    process(clk_50MHz, rst_global)
    begin
        if rst_global = '1' then
            ps_start_timing <= '0';
        elsif rising_edge(clk_50MHz) then
            ps_start_timing <= '0'; -- Pulso de 1 ciclo
            
            -- Cuando se asigna un slot nuevo (ParkingController activa start_slot_valid)
            if start_slot_valid_sig = '1' then
                ps_start_timing <= '1';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- PROCESO: TECLADO Y SELECCIÃ“N DE ESPACIO
    -- =====================================================================
    process(clk_50MHz, rst_global)
    begin
        if rst_global = '1' then
            ps_selected_space <= 0;
            ps_stop_timing <= '0';
            stop_slot_idx_sig <= (others => '0');
            stop_slot_valid_sig <= '0';
        elsif rising_edge(clk_50MHz) then
            ps_stop_timing <= '0';
            stop_slot_valid_sig <= '0';
            
            if kp_key_valid = '1' then
                if kp_key_ascii >= x"31" and kp_key_ascii <= x"39" then
                    -- Teclas 1-9
                    ps_selected_space <= to_integer(unsigned(kp_key_code));
                    ps_stop_timing <= '1';
                    stop_slot_idx_sig <= kp_key_code;
                    stop_slot_valid_sig <= '1';
                elsif kp_key_ascii = x"30" then
                    -- Tecla 0 = espacio 10
                    ps_selected_space <= 10;
                    ps_stop_timing <= '1';
                    stop_slot_idx_sig <= std_logic_vector(to_unsigned(9, 4));
                    stop_slot_valid_sig <= '1';
                end if;
            end if;
        end if;
    end process;

    -- =====================================================================
    -- PROCESO: ACTUALIZACIÃ“N DE DISPLAYS 7 SEGMENTOS
    -- =====================================================================
    process(door_timer_active_i, door_time_left_i, 
            parking_timer_active_i, parking_time_left_i)
    begin
        if door_timer_active_i = '1' then
            display_value <= door_time_left_i;
        elsif parking_timer_active_i = '1' then
            display_value <= parking_time_left_i;
        else
            display_value <= 0;
        end if;
        
        d_tens <= (display_value / 10) mod 10;
        d_units <= display_value mod 10;
        bcd_high <= std_logic_vector(to_unsigned(d_tens, 4));
        bcd_low <= std_logic_vector(to_unsigned(d_units, 4));
    end process;

    -- =====================================================================
    -- PROCESO: DISPLAYS DE PAGO (mostrar costo en pesos)
    -- =====================================================================
    process(ps_payment_pending, payment_display_value, parking_time_minutes)
    begin
        if ps_payment_pending = '1' or ps_stop_timing = '1' then
            -- Mostrar costo total en displays D3 y D4
            -- payment_display_value ya estÃ¡ en decenas (dividido por 100)
            payment_tens <= (payment_display_value / 10) mod 10;
            payment_units <= payment_display_value mod 10;
        else
            payment_tens <= 0;
            payment_units <= 0;
        end if;
        
        payment_bcd_high <= std_logic_vector(to_unsigned(payment_tens, 4));
        payment_bcd_low <= std_logic_vector(to_unsigned(payment_units, 4));
    end process;

    -- =====================================================================
    -- DECODIFICADORES 7 SEGMENTOS
    -- =====================================================================
    -- Displays D1 y D2: Timers de puerta/parking
    U_DEC_HIGH: entity work.decodificador_7seg 
        port map(bcd => bcd_high, segmentos => Display_D1);	

    U_DEC_LOW: entity work.decodificador_7seg 
        port map(bcd => bcd_low, segmentos => Display_D2);

    -- Displays D3 y D4: Costo de pago
    U_DEC_PAYMENT_HIGH: entity work.decodificador_7seg 
        port map(bcd => payment_bcd_high, segmentos => Display_D3);
    
    U_DEC_PAYMENT_LOW: entity work.decodificador_7seg 
        port map(bcd => payment_bcd_low, segmentos => Display_D4);

end Structural;