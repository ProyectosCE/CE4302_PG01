
/*
 * ============================================
 * ARCHIVO: top_tb.sv
 * DESCRIPCIÓN GENERAL:
 *   Testbench de integración para el sistema multicore completo.
 *   Instancia y conecta todos los componentes: cores, caches, bus y memoria.
 *   Simula escenarios de alta contención, productor-consumidor y migración de ownership.
 *
 * ESCENARIOS PROBADOS:
 *   1. Alta contención: Todos los cores acceden a la misma dirección.
 *   2. Productor-consumidor: Unos cores escriben y otros leen la misma dirección.
 *   3. Migración de ownership: Escrituras sucesivas por diferentes cores.
 *
 * COMPORTAMIENTO ESPERADO:
 *   - Se observan logs de solicitudes, transiciones de estado y eventos de bus.
 *   - Se valida la correcta interacción y coherencia entre todos los módulos.
 *
 * NOTA DE TIEMPO:
 *   - Se utiliza $realtime para trazas más precisas y se configura $timeformat
 *     para visualizar tiempos en ns de forma uniforme.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
`timescale 1ns/1ps

module workload_csv_tb;

    import types_pkg::*;
    import model_pkg::*;

    // CONFIGURACIÓN GLOBAL
    localparam NUM_CORES = 4;
    localparam BUS_MBX_DEPTH = 4;

    // COMPONENTES DEL SISTEMA
    Core  cores   [NUM_CORES];
    Cache caches  [NUM_CORES];
    Bus   bus;
    Memory memory;

    // Mailboxes para comunicación entre módulos
    CoreReq_mbx core_to_cache [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    // Acknowledgments del core para que no envíe solicitudes a la caché más rápido de lo que puede procesarlas
    CoreAck_mbx cache_to_core [NUM_CORES];

    BusReq_mbx bus_mbx;
    BusReq_mbx mem_req_mbx;
    
    // Mailbox para que la memoria notifique al bus cuando una transacción de memoria ha finalizado (opcional, dependiendo de la implementación del bus)
    MemResp_mbx mem_done_mbx;

    // Monitoreo FSM (transiciones de estado)
    EventMonitor fsm_monitor;

    /**
     * @brief Inicializa el sistema: crea instancias, mailboxes y conecta todos los módulos.
     *        Lanza en paralelo la ejecución de caches y el bus/memoria.
     */
    task setup_system(Cache::protocol_e protocol_sel);

        bus_mbx = new(BUS_MBX_DEPTH);
        mem_req_mbx = new(BUS_MBX_DEPTH);
        mem_done_mbx = new(BUS_MBX_DEPTH);

        if (fsm_monitor == null) begin
            fsm_monitor = new();
            fsm_monitor.enable_transition_export("../sim_results/fsm_transitions.csv");
        end

        foreach (core_to_cache[i]) core_to_cache[i] = new();
        foreach (bus_evt_mbx[i])  bus_evt_mbx[i]  = new();
        foreach (mem_mbx[i])      mem_mbx[i]      = new();

        foreach (cache_to_core[i]) cache_to_core[i] = new(1);

        foreach (cores[i]) begin
            caches[i] = new(i, protocol_sel, BUS_MBX_DEPTH);
            cores[i]  = new(i);

            caches[i].fsm_monitor = fsm_monitor;

            cores[i].to_cache = core_to_cache[i];

            caches[i].from_core = core_to_cache[i];
            caches[i].to_bus    = bus_mbx;
            caches[i].from_bus  = bus_evt_mbx[i];
            caches[i].from_mem  = mem_mbx[i];

            cores[i].from_cache = cache_to_core[i];
            caches[i].to_core   = cache_to_core[i];

        end

       
        bus = new(bus_mbx, bus_evt_mbx, mem_req_mbx, mem_done_mbx, NUM_CORES);

        // Instancia de Memory: 4 cores, 8 bytes/ns ancho de banda y mailbox para notificar al bus cuando una transacción de memoria ha finalizado.
        memory = new(mem_req_mbx, mem_mbx, mem_done_mbx, NUM_CORES, 8.0);

        // CACHES en paralelo
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();
        join_none

        // BUS real: arbitraje RR + broadcast + BW modelado + métricas
        bus.run();

        // MEMORIA real: procesa solicitudes con latencias modeladas
        memory.run();

        #10;

    endtask

    /**
     * @brief Ejecuta todos los cores en paralelo, procesando sus traces de solicitudes.
     */
    task run_cores();
        fork
            cores[0].run();
            cores[1].run();
            cores[2].run();
            cores[3].run();
        join
    endtask

    /**
     * @brief Carga traces desde archivo CSV e inyecta en los cores.
     *        Lee plusarg +TRACE_FILE; si no existe, usa default.
     * @param trace_file Ruta del archivo CSV (puede ser vacio para usar default)
     */
    task load_traces_from_file(string trace_file);
        TraceLoader loader;
        string pe_trace_file;
        static string default_trace = "../traces/fake/workload_contention_1000000";

        // Si no se proporciona archivo, usa default
        if (trace_file == "") begin
            trace_file = default_trace;
        end

        $display("[TopTB] Cargando workload base: %s", trace_file);

        foreach (cores[i]) begin
            pe_trace_file = $sformatf("%s_PE%0d.csv", trace_file, i);

            $display("[TopTB] Cargando PE%0d desde: %s", i, pe_trace_file);

            loader = new(pe_trace_file);
            loader.load_into_core(cores[i], i);
        end
endtask

    // TEST
    initial begin

        string trace_file;
        string protocol_name;
        Cache::protocol_e protocol_sel;

        // Formato temporal global del testbench de integración (ns con 1 decimal).
        $timeformat(-9, 3, " ns", 10);

        $display("========================================");
        $display("   DEMO 2 - SISTEMA MULTICORE COMPLETO");
        $display("           (Cargando desde traces)");
        $display("========================================");

        // Lee plusarg +TRACE_FILE, si no existe usa string vacío
        if (!$value$plusargs("TRACE_FILE=%s", trace_file)) begin
            trace_file = "";
        end

        protocol_name = "";
        if ($value$plusargs("PROTOCOL=%s", protocol_name)) begin
            if (protocol_name == "MSI" || protocol_name == "msi") begin
                $display("[TopTB] Protocolo seleccionado: MSI");
                protocol_sel = Cache::MSI;
            end else begin
                $display("[TopTB] Protocolo seleccionado: FIREFLY");
                protocol_sel = Cache::FIREFLY;
            end
        end else begin
            $display("[TopTB] +PROTOCOL no especificado");
            // salir
            $finish;
        end

        // Ejecuta un único escenario cargando desde archivo
        setup_system(protocol_sel);

        load_traces_from_file(trace_file);

        $display("\n========== EJECUTANDO TRACES ==========\n");

        // No se hace por tiempo, se espera a que cores procesen todo su trace y luego se espera a que bus y memoria terminen de procesar todas las solicitudes.

        run_cores();

        wait (
            caches[0].get_total_accesses() == cores[0].trace_queue.size() &&
            caches[1].get_total_accesses() == cores[1].trace_queue.size() &&
            caches[2].get_total_accesses() == cores[2].trace_queue.size() &&
            caches[3].get_total_accesses() == cores[3].trace_queue.size()
        );

        wait (bus.is_idle());
        wait (memory.is_idle());

        #50;

        $display("\n========== METRICAS CACHES ==========");
        foreach (caches[i]) begin
            caches[i].print_metrics();
        end

        $display("\n========== METRICAS BUS ==========");
        bus.print_metrics();

        $display("\n========== METRICAS MEMORIA ==========");
        memory.print_metrics();

        if (fsm_monitor != null) begin
            fsm_monitor.close();
        end

        

        $display("\n========== FIN SIMULACION ==========");
        $finish;

    end

endmodule