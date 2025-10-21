library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Main_servo is
    generic (
        CLK_FREQ        : integer := 50000000; -- Hz (informativo)
        PWM_PERIOD      : integer := 1000000;  -- ciclos de reloj (20 ms @50MHz)
        SERVO_CLOSED    : integer := 75000;    -- ciclos alto para posición cerrada (1.5 ms)
        SERVO_OPENED    : integer := 125000;   -- ciclos alto para posición abierta (2.5 ms)
        MOVEMENT_TIME   : integer := 100000000 -- ciclos para tiempo de movimiento (2 s @50MHz)
    );
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        open_door : in STD_LOGIC;    -- pulso 1 ciclo para iniciar apertura
        close_door : in STD_LOGIC;   -- pulso 1 ciclo para iniciar cierre
        servo_pwm : out STD_LOGIC;   -- PWM hacia hardware (único driver)
        servo_movement_complete : out STD_LOGIC; -- pulso 1 ciclo cuando alcanza posición
        servo_in_position : out STD_LOGIC       -- '1' cuando está en posición estable
    );
end Main_servo;

architecture Behavioral of Main_servo is
    constant PWM_MAX_IDX  : integer := PWM_PERIOD - 1;

    type servo_state is (ST_CLOSED, ST_OPENING, ST_OPENED, ST_CLOSING);
    signal current_state : servo_state := ST_CLOSED;

    signal pwm_counter    : integer range 0 to PWM_MAX_IDX := 0;
    signal pwm_high_for   : integer range 0 to PWM_MAX_IDX := SERVO_CLOSED;

    signal movement_timer : integer range 0 to MOVEMENT_TIME := 0;

    -- flag/pulse registers
    signal servo_movement_complete_r : std_logic := '0'; -- pulse 1 cycle when reached
    signal servo_in_position_r : std_logic := '1';      -- sustained while in stable pos

begin
    ----------------------------------------------------------------
    -- FSM de control de posición del servo (sincrónico)
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= ST_CLOSED;
            pwm_high_for <= SERVO_CLOSED;
            movement_timer <= 0;
            servo_movement_complete_r <= '0';
            servo_in_position_r <= '1';
        elsif rising_edge(clk) then
            -- default clear single-cycle pulse
            servo_movement_complete_r <= '0';

            case current_state is
                when ST_CLOSED =>
                    pwm_high_for <= SERVO_CLOSED;
                    movement_timer <= 0;
                    servo_in_position_r <= '1';
                    if open_door = '1' then
                        current_state <= ST_OPENING;
                        pwm_high_for <= SERVO_OPENED;
                        movement_timer <= 0;
                        servo_in_position_r <= '0';
                    end if;

                when ST_OPENING =>
                    -- during movement keep servo_in_position low
                    servo_in_position_r <= '0';
                    if movement_timer < MOVEMENT_TIME then
                        movement_timer <= movement_timer + 1;
                    else
                        current_state <= ST_OPENED;
                        movement_timer <= 0;
                        servo_movement_complete_r <= '1';
                        servo_in_position_r <= '1';
                    end if;

                when ST_OPENED =>
                    pwm_high_for <= SERVO_OPENED;
                    movement_timer <= 0;
                    servo_in_position_r <= '1';
                    if close_door = '1' then
                        current_state <= ST_CLOSING;
                        pwm_high_for <= SERVO_CLOSED;
                        movement_timer <= 0;
                        servo_in_position_r <= '0';
                    end if;

                when ST_CLOSING =>
                    servo_in_position_r <= '0';
                    if movement_timer < MOVEMENT_TIME then
                        movement_timer <= movement_timer + 1;
                    else
                        current_state <= ST_CLOSED;
                        movement_timer <= 0;
                        servo_movement_complete_r <= '1';
                        servo_in_position_r <= '1';
                    end if;

            end case;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Generador PWM (activo alto durante pwm_high_for ciclos)
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            pwm_counter <= 0;
            servo_pwm <= '0';
        elsif rising_edge(clk) then
            if pwm_counter < pwm_high_for then
                servo_pwm <= '1';
            else
                servo_pwm <= '0';
            end if;

            if pwm_counter < PWM_MAX_IDX then
                pwm_counter <= pwm_counter + 1;
            else
                pwm_counter <= 0;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Salidas
    ----------------------------------------------------------------
    servo_movement_complete <= servo_movement_complete_r;
    servo_in_position <= servo_in_position_r;

end Behavioral;