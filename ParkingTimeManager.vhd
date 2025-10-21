library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ParkingTimeManager is
    Port (
        clk          : in  std_logic;               -- reloj principal (ej. 50 MHz)
        rst          : in  std_logic;               -- reset activo '1' (sincronico/asíncrono según tu convención)
        tick_1Hz     : in  std_logic;               -- pulso de 1 Hz para incrementar contadores (1 ciclo)
        start_slot   : in  std_logic_vector(3 downto 0); -- índice 0..9, válido cuando start_slot_valid='1'
        start_slot_valid : in std_logic;            -- pulso 1 ciclo para iniciar contador en start_slot
        stop_slot    : in  std_logic_vector(3 downto 0); -- índice 0..9, válido cuando stop_slot_valid='1'
        stop_slot_valid  : in std_logic;            -- pulso 1 ciclo para pausar contador en stop_slot
        reset_slot   : in  std_logic_vector(3 downto 0); -- índice 0..9, válido cuando reset_slot_valid='1'
        reset_slot_valid  : in std_logic;           -- pulso 1 ciclo para resetear contador en reset_slot
        reset_all    : in  std_logic;               -- limpía todos los contadores (sincrónico)
        -- lectura sencilla por índice
        read_index   : in  std_logic_vector(3 downto 0); -- índice a leer (0..9)
        read_valid   : in  std_logic;                -- pulso 1 ciclo para solicitar lectura
        read_time    : out integer range 0 to 999999;  -- tiempo en segundos del índice solicitado
        read_ready   : out std_logic;                -- '1' durante el ciclo en que read_time es válida
        -- señales de estado opcionales
        slot_active  : out std_logic_vector(9 downto 0) -- '1' = contador activo para cada plaza
    );
end ParkingTimeManager;

architecture Behavioral of ParkingTimeManager is
    constant N_SLOTS : integer := 10;
    -- ancho del contador en segundos; ajustar el rango máximo según necesidades
    subtype time_t is integer range 0 to 999999;

    type time_array_t is array (0 to N_SLOTS-1) of time_t;
    type active_array_t is array (0 to N_SLOTS-1) of std_logic;

    signal counters : time_array_t := (others => 0);
    signal active   : active_array_t := (others => '0');

    -- señales internas para index decodificado
    function to_int4(v: std_logic_vector(3 downto 0)) return integer is
        variable rv : integer := 0;
    begin
        rv := to_integer(unsigned(v));
        return rv;
    end function;

    -- Wires para salida slot_active
    signal slot_active_sig : std_logic_vector(9 downto 0) := (others => '0');

begin
    -- Asignar salida de estado (mapear array a vector)
    process(active)
        variable tmp : std_logic_vector(9 downto 0);
    begin
        for i in 0 to N_SLOTS-1 loop
            tmp(i) := active(i);
        end loop;
        slot_active_sig <= tmp;
    end process;

    slot_active <= slot_active_sig;

    ----------------------------------------------------------------
    -- Control principal: start/stop/reset por índices y tick incremental
    ----------------------------------------------------------------
    process(clk, rst)
        variable idx : integer;
    begin
        if rst = '1' then
            -- Reset global
            for i in 0 to N_SLOTS-1 loop
                counters(i) <= 0;
                active(i) <= '0';
            end loop;
            read_time <= 0;
            read_ready <= '0';
        elsif rising_edge(clk) then
            -- Clear read_ready por defecto
            read_ready <= '0';

            -- Reset global directo
            if reset_all = '1' then
                for i in 0 to N_SLOTS-1 loop
                    counters(i) <= 0;
                    active(i) <= '0';
                end loop;
            end if;

            -- Reset individual slot (prime el índice de reset_slot cuando su valid='1')
            if reset_slot_valid = '1' then
                idx := to_int4(reset_slot);
                if idx >= 0 and idx < N_SLOTS then
                    counters(idx) <= 0;
                    active(idx) <= '0';
                end if;
            end if;

            -- Start slot: habilitar contador si estaba inactivo
            if start_slot_valid = '1' then
                idx := to_int4(start_slot);
                if idx >= 0 and idx < N_SLOTS then
                    active(idx) <= '1';
                    -- opcional: si quieres reiniciar tiempo al asignar, descomenta la siguiente línea
                    -- counters(idx) <= 0;
                end if;
            end if;

            -- Stop slot: pausar contador (mantener valor)
            if stop_slot_valid = '1' then
                idx := to_int4(stop_slot);
                if idx >= 0 and idx < N_SLOTS then
                    active(idx) <= '0';
                end if;
            end if;

            -- Tick 1Hz: incrementar todos los counters activos
            if tick_1Hz = '1' then
                for i in 0 to N_SLOTS-1 loop
                    if active(i) = '1' then
                        if counters(i) < time_t'high then
                            counters(i) <= counters(i) + 1;
                        else
                            counters(i) <= counters(i); -- saturar en el máximo
                        end if;
                    end if;
                end loop;
            end if;

            -- Lectura puntual por índice (read_valid = '1' un ciclo)
            if read_valid = '1' then
                idx := to_int4(read_index);
                if idx >= 0 and idx < N_SLOTS then
                    read_time <= counters(idx);
                else
                    read_time <= 0;
                end if;
                read_ready <= '1';
            end if;
        end if;
    end process;

end Behavioral;