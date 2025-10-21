library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PaymentSystem is
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        
        -- Control de timing (usado por TopLevel para sincronizaciÃ³n)
        start_timing : in STD_LOGIC;
        stop_timing : in STD_LOGIC;
        
        -- Espacio seleccionado y tiempo real desde ParkingTimeManager
        selected_space : in integer range 0 to 10;
        parking_time_seconds : in integer range 0 to 999999;
        
        -- Estado de espacios
        space_occupied : in STD_LOGIC_VECTOR(9 downto 0);
        
        -- Monedas
        coin_500 : in STD_LOGIC;
        coin_1000 : in STD_LOGIC;
        
        -- Salidas de pago
        payment_complete : out STD_LOGIC;
        total_cost : out integer range 0 to 720000;
        amount_paid : out integer range 0 to 720000;
        change_due : out integer range 0 to 720000;
        payment_pending : out STD_LOGIC;
        
        -- InformaciÃ³n de tiempo (para compatibilidad)
        parking_minutes : out integer range 0 to 1440;
        entry_times : out STD_LOGIC_VECTOR(159 downto 0)
    );
end PaymentSystem;

architecture Behavioral of PaymentSystem is
    -- Constantes
    constant RATE_PER_MINUTE : integer := 500;
    
    -- SeÃ±ales de tiempo
    signal current_time_minutes : integer range 0 to 1440 := 0;
    
    -- Sistema de pago
    signal current_payment : integer range 0 to 720000 := 0;
    signal required_payment : integer range 0 to 720000 := 0;
    signal payment_in_progress : STD_LOGIC := '0';
    signal selected_space_valid : STD_LOGIC := '0';
    
    -- Estados del sistema de pago
    type payment_state is (IDLE, CALCULATING, WAITING_PAYMENT, PAYMENT_OK);
    signal pay_state : payment_state := IDLE;
    
    -- Registro de espacios que tuvieron pago completado
    type paid_spaces_array is array (1 to 10) of STD_LOGIC;
    signal paid_spaces : paid_spaces_array := (others => '0');
    
begin

    -- =====================================================================
    -- CONVERSIÃ“N DE TIEMPO: Segundos a Minutos (Redondeo hacia arriba)
    -- =====================================================================
    process(parking_time_seconds)
    begin
        if parking_time_seconds = 0 then
            current_time_minutes <= 1; -- MÃ­nimo 1 minuto
        else
            -- Redondeo hacia arriba: (segundos + 59) / 60
            current_time_minutes <= (parking_time_seconds + 59) / 60;
        end if;
    end process;
    
    -- =====================================================================
    -- VALIDACIÃ“N DEL ESPACIO SELECCIONADO
    -- =====================================================================
    selected_space_valid <= '1' when (selected_space >= 1 and 
                                      selected_space <= 10 and 
                                      space_occupied(selected_space-1) = '1') 
                            else '0';
    
    -- =====================================================================
    -- MÃQUINA DE ESTADOS DEL SISTEMA DE PAGO
    -- =====================================================================
    process(clk, rst)
    begin
        if rst = '1' then
            pay_state <= IDLE;
            current_payment <= 0;
            required_payment <= 0;
            payment_in_progress <= '0';
            paid_spaces <= (others => '0');
            
        elsif rising_edge(clk) then
            case pay_state is
                
                when IDLE =>
                    -- âœ… NO resetear current_payment aquÃ­
                    payment_in_progress <= '0';
                    
                    -- Iniciar proceso de pago cuando se selecciona espacio vÃ¡lido
                    if stop_timing = '1' and selected_space_valid = '1' then
                        pay_state <= CALCULATING;
                        payment_in_progress <= '1';
                        current_payment <= 0;  -- âœ… Resetear solo al iniciar nuevo pago
                    end if;
                    
                when CALCULATING =>
                    -- Calcular costo total basado en tiempo real
                    if current_time_minutes = 0 then
                        required_payment <= RATE_PER_MINUTE; -- MÃ­nimo 1 minuto
                    elsif current_time_minutes > 1440 then
                        required_payment <= 720000; -- MÃ¡ximo 24 horas
                    else
                        required_payment <= current_time_minutes * RATE_PER_MINUTE;
                    end if;
                    pay_state <= WAITING_PAYMENT;
                    
                when WAITING_PAYMENT =>
                    -- Acumular pagos recibidos
                    if coin_500 = '1' then
                        if current_payment <= 719500 then
                            current_payment <= current_payment + 500;
                        end if;
                    elsif coin_1000 = '1' then
                        if current_payment <= 719000 then
                            current_payment <= current_payment + 1000;
                        end if;
                    end if;
                    
                    -- Verificar si el pago es suficiente
                    if current_payment >= required_payment then
                        pay_state <= PAYMENT_OK;
                        paid_spaces(selected_space) <= '1';
                    end if;
                    
                when PAYMENT_OK =>
                    -- Mantener estado hasta prÃ³xima transacciÃ³n
                    if stop_timing = '1' and selected_space_valid = '1' then
                        -- Nueva transacciÃ³n
                        pay_state <= CALCULATING;
                        current_payment <= 0;
                        required_payment <= 0;
                    elsif stop_timing = '0' then
                        -- Volver a IDLE cuando se suelta la tecla
                        pay_state <= IDLE;
                    end if;
                    
            end case;
        end if;
    end process;
    
    -- =====================================================================
    -- PROCESO: LIMPIAR ESTADO CUANDO ESPACIO SE LIBERA
    -- =====================================================================
    process(clk, rst)
    begin
        if rst = '1' then
            paid_spaces <= (others => '0');
        elsif rising_edge(clk) then
            for i in 1 to 10 loop
                if space_occupied(i-1) = '0' then
                    paid_spaces(i) <= '0';
                end if;
            end loop;
        end if;
    end process;
    
    -- =====================================================================
    -- GENERACIÃ“N DEL ARRAY DE TIEMPOS DE ENTRADA (Compatibilidad)
    -- =====================================================================
    process(clk, rst)
    begin
        if rst = '1' then
            entry_times <= (others => '0');
        elsif rising_edge(clk) then
            for i in 1 to 10 loop
                if space_occupied(i-1) = '1' then
                    entry_times(16*i-1 downto 16*(i-1)) <= (others => '1');
                else
                    entry_times(16*i-1 downto 16*(i-1)) <= (others => '0');
                end if;
            end loop;
        end if;
    end process;
    
    -- =====================================================================
    -- ASIGNACIÃ“N DE SALIDAS
    -- =====================================================================
    parking_minutes <= current_time_minutes;
    total_cost <= required_payment;
    amount_paid <= current_payment;
    
    -- Calcular cambio
    change_due <= current_payment - required_payment 
                  when (current_payment >= required_payment and pay_state = PAYMENT_OK) 
                  else 0;
    
    -- Estado de pago
    payment_complete <= '1' when pay_state = PAYMENT_OK else '0';
    payment_pending <= '1' when (pay_state = WAITING_PAYMENT or pay_state = CALCULATING) else '0';
    
end Behavioral;