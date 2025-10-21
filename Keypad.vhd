library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Keypad is
    Port (
        clk       : in  std_logic;                       -- reloj del sistema (50 MHz)
        rst       : in  std_logic;                       -- reset activo '1'
        row_pins  : in  std_logic_vector(3 downto 0);    -- entradas de filas (leer)
        col_drive : out std_logic_vector(3 downto 0);    -- columnas que se pulsan (una a la vez)
        key_valid : out std_logic;                       -- pulso 1 ciclo cuando key_code válido
        key_code  : out std_logic_vector(3 downto 0);    -- código 0..15
        key_ascii : out std_logic_vector(7 downto 0)     -- ASCII (opcional, '0'..'9','A'..'F')
    );
end Keypad;

architecture Behavioral of Keypad is
    -- Escaneo: activar una columna a la vez en BAJO (one-hot invertido)
    signal col_idx : integer range 0 to 3 := 0;
    signal col_drive_r : std_logic_vector(3 downto 0) := "1110"; -- columna 0 activa en bajo
    
    -- Debounce / confirm: requiere N lecturas iguales consecutivas
    constant SCAN_DIVIDER : integer := 5000;
    signal scan_cnt : integer range 0 to SCAN_DIVIDER := 0;
    signal sample_row : std_logic_vector(3 downto 0) := (others => '1');

    -- Contador de inicialización (esperar ~100ms antes de leer teclado)
    constant INIT_DELAY : integer := 5000000; -- 100ms @ 50MHz
    signal init_counter : integer range 0 to INIT_DELAY := 0;
    signal init_done : std_logic := '0';

    -- Filtro de estabilidad para detectar teclas válidas
    constant STABLE_CHECKS : integer := 10; -- Requiere 10 lecturas estables
    signal stable_counter : integer range 0 to STABLE_CHECKS := 0;
    signal last_row_read : std_logic_vector(3 downto 0) := (others => '1');

    -- Estado de teclado
    type kp_state_t is (IDLE, DEBOUNCE_PRESS, WAIT_RELEASE);
    signal kp_state : kp_state_t := IDLE;
    signal pressed_row : std_logic_vector(3 downto 0) := (others => '1');
    signal pressed_col : integer range 0 to 3 := 0;

    -- Señal para indicar pulso de tecla detectada
    signal key_valid_r : std_logic := '0';
    signal key_code_r  : std_logic_vector(3 downto 0) := (others => '0');
    signal key_ascii_r : std_logic_vector(7 downto 0) := x"00";

    -- Helper: convertir fila/col a código (fila*4 + col)
    function encode_code(row_i: integer; col_i: integer) return std_logic_vector is
        variable idx : integer := row_i*4 + col_i;
    begin
        return std_logic_vector(to_unsigned(idx,4));
    end function;

    -- Helper: map code to ASCII (0..9,A..F)
    function code_to_ascii(code: std_logic_vector(3 downto 0)) return std_logic_vector is
        variable c : integer := to_integer(unsigned(code));
    begin
        if c <= 9 then
            return std_logic_vector(to_unsigned(character'pos('0') + c, 8));
        else
            return std_logic_vector(to_unsigned(character'pos('A') + (c - 10), 8));
        end if;
    end function;

begin
    col_drive <= col_drive_r;
    key_valid <= key_valid_r;
    key_code <= key_code_r;
    key_ascii <= key_ascii_r;

    -- PROCESO DE INICIALIZACIÓN: Esperar antes de leer teclado
    process(clk, rst)
    begin
        if rst = '1' then
            init_counter <= 0;
            init_done <= '0';
        elsif rising_edge(clk) then
            if init_counter < INIT_DELAY then
                init_counter <= init_counter + 1;
                init_done <= '0';
            else
                init_done <= '1';
            end if;
        end if;
    end process;

    -- Escaneo lento: avanza columna periódicamente (ACTIVO BAJO)
    process(clk, rst)
    begin
        if rst = '1' then
            scan_cnt <= 0;
            col_idx <= 0;
            col_drive_r <= "1110"; -- columna 0 activa en bajo
            sample_row <= (others => '1');
        elsif rising_edge(clk) then
            if scan_cnt < SCAN_DIVIDER then
                scan_cnt <= scan_cnt + 1;
            else
                scan_cnt <= 0;
                -- avanzar columna
                if col_idx < 3 then
                    col_idx <= col_idx + 1;
                else
                    col_idx <= 0;
                end if;
                -- ✅ MODIFICADO: column drive active LOW (0 = driven)
                case col_idx is
                    when 0 => col_drive_r <= "1110"; -- columna 0 en bajo
                    when 1 => col_drive_r <= "1101"; -- columna 1 en bajo
                    when 2 => col_drive_r <= "1011"; -- columna 2 en bajo
                    when others => col_drive_r <= "0111"; -- columna 3 en bajo
                end case;
            end if;
        end if;
    end process;

    -- Muestreo de filas con filtro de estabilidad (ACTIVO BAJO)
    process(clk, rst)
        variable row_bits : std_logic_vector(3 downto 0);
        variable r_idx : integer;
    begin
        if rst = '1' then
            kp_state <= IDLE;
            pressed_row <= (others => '1');
            pressed_col <= 0;
            key_valid_r <= '0';
            key_code_r <= (others => '0');
            key_ascii_r <= x"00";
            stable_counter <= 0;
            last_row_read <= (others => '1');
        elsif rising_edge(clk) then
            key_valid_r <= '0'; -- default clear pulse

            -- Solo leer teclado después de inicialización
            if init_done = '0' then
                kp_state <= IDLE;
                stable_counter <= 0;
                last_row_read <= (others => '1');
            else
                -- leer filas (active LOW con pull-up)
                row_bits := row_pins;

                case kp_state is
                    when IDLE =>
                        -- Verificar estabilidad antes de aceptar lectura
                        if row_bits = last_row_read then
                            if stable_counter < STABLE_CHECKS then
                                stable_counter <= stable_counter + 1;
                            end if;
                        else
                            stable_counter <= 0;
                            last_row_read <= row_bits;
                        end if;

                        -- ✅ MODIFICADO: Detectar tecla si lectura es estable y NO es "1111" (alguna fila en bajo)
                        if row_bits /= "1111" and stable_counter >= STABLE_CHECKS then
                            pressed_row <= row_bits;
                            pressed_col <= col_idx;
                            kp_state <= DEBOUNCE_PRESS;
                            stable_counter <= 0;
                        end if;

                    when DEBOUNCE_PRESS =>
                        -- confirmar que sigue presionado
                        if row_bits = pressed_row then
                            -- identificar fila index (first '0' para activo bajo)
                            r_idx := 0;
                            while r_idx < 4 loop
                                exit when pressed_row(r_idx) = '0'; -- ✅ MODIFICADO: buscar '0'
                                r_idx := r_idx + 1;
                            end loop;
                            if r_idx < 4 then
                                -- generar código y pulso
                                key_code_r <= encode_code(r_idx, pressed_col);
                                key_ascii_r <= code_to_ascii(key_code_r);
                                key_valid_r <= '1';
                                kp_state <= WAIT_RELEASE;
                            else
                                kp_state <= IDLE;
                            end if;
                        else
                            -- bouncing or transient, go back to idle
                            kp_state <= IDLE;
                        end if;

                    when WAIT_RELEASE =>
                        -- ✅ MODIFICADO: esperar liberación completa (filas = all '1')
                        if row_bits = "1111" then
                            kp_state <= IDLE;
                            stable_counter <= 0;
                            last_row_read <= (others => '1');
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
