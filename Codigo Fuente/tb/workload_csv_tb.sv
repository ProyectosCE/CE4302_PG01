
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

    // COMPONENTES DEL SISTEMA
    Core  cores   [NUM_CORES];
    Cache caches  [NUM_CORES];

    // Mailboxes para comunicación entre módulos
    CoreReq_mbx core_to_cache [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    BusReq_mbx bus_mbx;

    /**
     * @brief Inicializa el sistema: crea instancias, mailboxes y conecta todos los módulos.
     *        Lanza en paralelo la ejecución de caches y el bus/memoria.
     */
    task setup_system();

        bus_mbx = new();

        foreach (core_to_cache[i]) core_to_cache[i] = new();
        foreach (bus_evt_mbx[i])  bus_evt_mbx[i]  = new();
        foreach (mem_mbx[i])      mem_mbx[i]      = new();

        foreach (cores[i]) begin
            caches[i] = new(i, Cache::MSI);
            cores[i]  = new(i);

            cores[i].to_cache = core_to_cache[i];

            caches[i].from_core = core_to_cache[i];
            caches[i].to_bus    = bus_mbx;
            caches[i].from_bus  = bus_evt_mbx[i];
            caches[i].from_mem  = mem_mbx[i];
        end

        // CACHES y BUS/MEMORIA en paralelo
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();

            // BUS + MEMORIA: simula el bus compartido y la memoria principal
            forever begin
                BusRequest  bus_req;
                BusEvent    evt;
                MemResponse mem_resp;

                bus_mbx.get(bus_req);

                $display("@%0t [BUS] type=%0d addr=%h core=%0d",
                    $realtime, bus_req.req_type, bus_req.address, bus_req.src_core_id);

                evt = new(bus_req.req_type, bus_req.address, bus_req.src_core_id);

                bus_evt_mbx[0].put(evt);
                bus_evt_mbx[1].put(evt);
                bus_evt_mbx[2].put(evt);
                bus_evt_mbx[3].put(evt);

                #10.5;

                mem_resp = new(bus_req.address, bus_req.src_core_id);
                mem_mbx[bus_req.src_core_id].put(mem_resp);
            end
        join_none

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
        static string default_trace = "../traces/workload_contention.csv";

        // Si no se proporciona archivo, usa default
        if (trace_file == "") begin
            trace_file = default_trace;
        end

        $display("[TopTB] Cargando traces desde: %s", trace_file);

        loader= new(trace_file);
        loader.load_into_cores(cores);
    endtask

    // TEST
    initial begin

        string trace_file;

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

        // Ejecuta un único escenario cargando desde archivo
        setup_system();

        load_traces_from_file(trace_file);

        $display("\n========== EJECUTANDO TRACES ==========\n");

        run_cores();
        #100;

        $display("\n========== FIN SIMULACION ==========");
        $finish;

    end

endmodule