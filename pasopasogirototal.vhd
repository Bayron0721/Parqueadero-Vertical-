library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pasopasogirototal is
    generic (
     
    CLK_FREQ        : integer := 50000000;
    STEPS_PER_REV   : integer := 1480;
    STEP_DELAY      : integer := 100000    -- 2 ms @ 50MHz (aumentado desde 25000)
);

   
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        start_rotation : in STD_LOGIC;          -- Pulso de 1 ciclo para iniciar rotación
        motor_A : out STD_LOGIC;                -- Salidas hacia el motor
        motor_B : out STD_LOGIC;
        motor_C : out STD_LOGIC;
        motor_D : out STD_LOGIC;
        rotation_complete : out STD_LOGIC;      -- Pulso de 1 ciclo cuando completa la vuelta
        motor_busy : out STD_LOGIC              -- '1' mientras está girando
    );
end pasopasogirototal;

architecture Behavioral of pasopasogirototal is
    
    -- Estados del motor
    type motor_state_t is (ST_IDLE, ST_ROTATING, ST_DONE);
    signal current_state : motor_state_t := ST_IDLE;
    
    -- Secuencia de medio paso (half-step) para 28BYJ-48
    -- Orden: A, B, C, D (conectados a IN1, IN2, IN3, IN4 del ULN2003)
    type step_sequence_t is array (0 to 7) of STD_LOGIC_VECTOR(3 downto 0);
    constant HALF_STEP_SEQ : step_sequence_t := (
        "1000",  -- Paso 0: A
        "1100",  -- Paso 1: A+B
        "0100",  -- Paso 2: B
        "0110",  -- Paso 3: B+C
        "0010",  -- Paso 4: C
        "0011",  -- Paso 5: C+D
        "0001",  -- Paso 6: D
        "1001"   -- Paso 7: D+A
    );
    
    -- Contadores y señales
    signal step_index : integer range 0 to 7 := 0;
    signal step_counter : integer range 0 to STEPS_PER_REV := 0;
    signal delay_counter : integer range 0 to STEP_DELAY := 0;
    
    -- Señales de salida del motor
    signal motor_outputs : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    
    -- Señales de control
    signal rotation_complete_r : STD_LOGIC := '0';
    signal motor_busy_r : STD_LOGIC := '0';
    
begin
    
    ----------------------------------------------------------------
    -- Máquina de estados para control del motor paso a paso
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= ST_IDLE;
            step_index <= 0;
            step_counter <= 0;
            delay_counter <= 0;
            motor_outputs <= "0000";
            rotation_complete_r <= '0';
            motor_busy_r <= '0';
            
        elsif rising_edge(clk) then
            -- Por defecto, limpiar pulso de completado
            rotation_complete_r <= '0';
            
            case current_state is
                
                when ST_IDLE =>
                    motor_outputs <= "0000";  -- Motor desactivado
                    motor_busy_r <= '0';
                    step_counter <= 0;
                    step_index <= 0;
                    delay_counter <= 0;
                    
                    -- Detectar pulso de inicio
                    if start_rotation = '1' then
                        current_state <= ST_ROTATING;
                        motor_busy_r <= '1';
                        step_counter <= 0;
                        step_index <= 0;
                        delay_counter <= 0;
                    end if;
                
                when ST_ROTATING =>
                    motor_busy_r <= '1';
                    
                    -- Aplicar la secuencia de pasos actual
                    motor_outputs <= HALF_STEP_SEQ(step_index);
                    
                    -- Contador de retardo entre pasos
                    if delay_counter < STEP_DELAY then
                        delay_counter <= delay_counter + 1;
                    else
                        delay_counter <= 0;
                        
                        -- Avanzar al siguiente paso en la secuencia
                        if step_index < 7 then
                            step_index <= step_index + 1;
                        else
                            step_index <= 0;  -- Volver al inicio de la secuencia
                        end if;
                        
                        -- Incrementar contador de pasos totales
                        if step_counter < STEPS_PER_REV - 1 then
                            step_counter <= step_counter + 1;
                        else
                            -- Completó una revolución completa
                            current_state <= ST_DONE;
                            rotation_complete_r <= '1';
                        end if;
                    end if;
                
                when ST_DONE =>
                    -- Mantener la última posición por un ciclo
                    motor_outputs <= HALF_STEP_SEQ(step_index);
                    motor_busy_r <= '0';
                    current_state <= ST_IDLE;
                
                when others =>
                    current_state <= ST_IDLE;
                    
            end case;
        end if;
    end process;
    
    ----------------------------------------------------------------
    -- Asignación de salidas
    ----------------------------------------------------------------
    motor_A <= motor_outputs(3);
    motor_B <= motor_outputs(2);
    motor_C <= motor_outputs(1);
    motor_D <= motor_outputs(0);
    
    rotation_complete <= rotation_complete_r;
    motor_busy <= motor_busy_r;
    
end Behavioral;
