
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

module top_tb;

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
    EventMonitor fsm_monitor;

    // Mailboxes para comunicación entre módulos
    CoreReq_mbx core_to_cache [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    BusReq_mbx bus_mbx;
    BusReq_mbx mem_req_mbx;

    MemResp_mbx mem_done_mbx;


    /**
     * @brief Inicializa el sistema: crea instancias, mailboxes y conecta todos los módulos.
     *        Lanza en paralelo la ejecución de caches y el bus real.
     */
    task setup_system();

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

        foreach (cores[i]) begin
            caches[i] = new(i, Cache::FIREFLY, BUS_MBX_DEPTH); // Escoger entre: MSI o FIREFLY
            cores[i]  = new(i);

            caches[i].fsm_monitor = fsm_monitor;

            cores[i].to_cache = core_to_cache[i];

            caches[i].from_core = core_to_cache[i];
            caches[i].to_bus    = bus_mbx;
            caches[i].from_bus  = bus_evt_mbx[i];
            caches[i].from_mem  = mem_mbx[i];
        end

        // BUS REAL: arbitraje, broadcast y respuesta de memoria modelada.
        bus = new(bus_mbx, bus_evt_mbx, mem_req_mbx, mem_done_mbx, NUM_CORES);
        memory = new(mem_req_mbx, mem_mbx, mem_done_mbx, NUM_CORES, 8.0);

        // CACHES en paralelo
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();
        join_none

        // BUS REAL en ejecución concurrente.
        bus.run();
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
    * @brief Imprime métricas de todas las cachés.
    */
    task print_all_cache_metrics(string scenario_name);

        $display("");
        $display("======================================================");
        $display("METRICS REPORT: %s", scenario_name);
        $display("======================================================");

        foreach (caches[i]) begin
            caches[i].print_metrics();
        end

        $display("======================================================");
        $display("");

    endtask

    // TEST
    initial begin

        CoreRequest req;

        // Formato temporal global del testbench de integración (ns con 1 decimal).
        $timeformat(-9, 3, " ns", 10);

        $display("========================================");
        $display("   DEMO 2 - SISTEMA MULTICORE COMPLETO");
        $display("========================================");

        // ALTA CONTENCION
        setup_system();

        $display("\n========== ESCENARIO 1: ALTA CONTENCION ==========");

        foreach (cores[i]) begin
            req = new(PrRd, 32'h1000, i); cores[i].add_request(req);
            req = new(PrWr, 32'h1000, i); cores[i].add_request(req);
            req = new(PrRd, 32'h1000, i); cores[i].add_request(req);
        end

        run_cores();
        #100;

        print_all_cache_metrics("ESCENARIO 1 - ALTA CONTENCION");

        // PRODUCTOR - CONSUMIDOR
        setup_system();

        $display("\n========== ESCENARIO 2: PRODUCTOR - CONSUMIDOR ==========");

        // PRODUCTORES
        req = new(PrWr, 32'h2000, 0); cores[0].add_request(req);
        req = new(PrWr, 32'h2000, 1); cores[1].add_request(req);

        // CONSUMIDORES
        req = new(PrRd, 32'h2000, 2); cores[2].add_request(req);
        req = new(PrRd, 32'h2000, 3); cores[3].add_request(req);

        // repetición
        req = new(PrWr, 32'h2000, 0); cores[0].add_request(req);
        req = new(PrRd, 32'h2000, 2); cores[2].add_request(req);

        run_cores();
        #100;

        print_all_cache_metrics("ESCENARIO 2 - PRODUCTOR-CONSUMIDOR");

        // MIGRACION DE OWNERSHIP
        setup_system();

        $display("\n========== ESCENARIO 3: MIGRACION DE OWNERSHIP ==========");

        req = new(PrWr, 32'h3000, 0); cores[0].add_request(req);
        req = new(PrWr, 32'h3000, 1); cores[1].add_request(req);
        req = new(PrWr, 32'h3000, 2); cores[2].add_request(req);
        req = new(PrWr, 32'h3000, 3); cores[3].add_request(req);

        // repetir
        req = new(PrWr, 32'h3000, 0); cores[0].add_request(req);
        req = new(PrWr, 32'h3000, 1); cores[1].add_request(req);

        run_cores();
        #100;

        print_all_cache_metrics("ESCENARIO 3 - MIGRACION DE OWNERSHIP");

        $display("\n========== FIN DEMO ==========");
        if (fsm_monitor != null) begin
            fsm_monitor.close();
        end
        $finish;

    end

endmodule