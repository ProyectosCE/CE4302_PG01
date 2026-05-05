
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

    // COMPONENTES DEL SISTEMA
    Core  cores   [NUM_CORES];
    Cache caches  [NUM_CORES];
    Bus   bus;
    Memory mem;

    // Mailboxes para comunicación entre módulos
    CoreReq_mbx core_to_cache [NUM_CORES];
    CoreResp_mbx cache_to_core [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    BusReq_mbx bus_mbx;
    BusReq_mbx bus_to_mem;

    /**
     * @brief Inicializa el sistema: crea instancias, mailboxes y conecta todos los módulos.
     *        Lanza en paralelo la ejecución de caches y el bus real.
     */
    task setup_system();

        bus_mbx = new();
        bus_to_mem = new();

        foreach (core_to_cache[i]) core_to_cache[i] = new();
        foreach (cache_to_core[i]) cache_to_core[i] = new();
        foreach (bus_evt_mbx[i])  bus_evt_mbx[i]  = new();
        foreach (mem_mbx[i])      mem_mbx[i]      = new();

        foreach (cores[i]) begin
            caches[i] = new(i, Cache::MSI);
            cores[i]  = new(i);

            cores[i].to_cache = core_to_cache[i];
            cores[i].from_cache = cache_to_core[i];

            caches[i].from_core = core_to_cache[i];
            caches[i].to_core   = cache_to_core[i];
            caches[i].to_bus    = bus_mbx;
            caches[i].from_bus  = bus_evt_mbx[i];
            caches[i].from_mem  = mem_mbx[i];
        end

        // BUS REAL: arbitraje, broadcast y respuesta de memoria modelada.
        bus = new(bus_mbx, bus_evt_mbx, mem_mbx, NUM_CORES);
        bus.bus_to_mem = bus_to_mem;
        // Optional snoop-ack handshake is disabled in this TB to avoid blocking on acks.

        // MEMORIA REAL: punto unico de respuesta.
        mem = new(NUM_CORES);
        mem.from_bus = bus_to_mem;
        mem.to_cache = new[NUM_CORES];
        for (int i = 0; i < NUM_CORES; i++) begin
            mem.to_cache[i] = mem_mbx[i];
        end

        // CACHES en paralelo
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();
        join_none

        // BUS y MEMORIA en ejecucion concurrente.
        fork
            bus.run();
            mem.run();
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
     * @brief Espera a que memoria procese todas las solicitudes pendientes.
     */
    task wait_for_memory_idle();
        wait (mem.req_mbx.num() == 0);
        #1;
        wait (mem.total_requests == mem.total_responses);
    endtask

    /**
     * @brief Espera a que el bus y la memoria queden sin solicitudes pendientes.
     */
    task wait_for_system_idle();
        wait (bus_mbx.num() == 0);
        wait (!bus.has_pending_requests());
        wait_for_memory_idle();
        #1;
    endtask

    // TEST
    initial begin

        CoreRequest req;

        // Formato temporal global del testbench de integración (ns con 1 decimal).
        $timeformat(-9, 3, " ns", 10);

        $display("========================================");
        $display("SISTEMA MULTICORE COMPLETO");
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
        wait_for_system_idle();

        bus.print_metrics();
        mem.print_metrics();
        $display("CACHE METRICS PER CORE");
        for (int i = 0; i < NUM_CORES; i++) begin
            caches[i].print_metrics();
        end

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
        wait_for_system_idle();

        bus.print_metrics();
        mem.print_metrics();
        $display("CACHE METRICS PER CORE");
        for (int i = 0; i < NUM_CORES; i++) begin
            caches[i].print_metrics();
        end

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
        wait_for_system_idle();

        bus.print_metrics();
        mem.print_metrics();
        $display("CACHE METRICS PER CORE");
        for (int i = 0; i < NUM_CORES; i++) begin
            caches[i].print_metrics();
        end

        $display("\n========== FIN DEMO ==========");
        $finish;

    end

endmodule