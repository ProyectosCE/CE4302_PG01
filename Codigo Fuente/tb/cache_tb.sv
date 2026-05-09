
/*
 * ============================================
 * ARCHIVO: cache_tb.sv
 * DESCRIPCIÓN GENERAL:
 *   Testbench para validar el funcionamiento de la clase Cache bajo los protocolos
 *   MSI (write-invalidate) y Firefly (write-update) en un entorno multicore.
 *
 * ESCENARIOS PROBADOS:
 *   - MSI: Transiciones I->S, S->M, M->S, invalidaciones y compartición.
 *   - Firefly: Transiciones I->S, actualizaciones por BusUpd, compartición sin invalidación.
 *
 * COMPORTAMIENTO ESPERADO:
 *   - Se observan logs de hits, misses, transiciones de estado y eventos de bus.
 *   - Se valida la correcta interacción entre caches, bus y memoria.
 *
 * NOTA DE TIEMPO:
 *   - Se fija el formato temporal en ns y se usa $realtime para que los logs
 *     reflejen con precisión cualquier fracción de tiempo de simulación.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
`timescale 1ns/1ns

module cache_tb;

    import types_pkg::*;
    import model_pkg::*;

    localparam BUS_MBX_DEPTH = 4;
    // 4 CACHES: Dos con MSI, dos con Firefly
    Cache cache0; // MSI
    Cache cache1; // MSI
    Cache cache2; // Firefly
    Cache cache3; // Firefly
    Bus   bus;
    EventMonitor fsm_monitor;

    // MAILBOXES para comunicación core-cache
    CoreReq_mbx core_mbx[4];

    // BUS: mailboxes para solicitudes y eventos
    BusReq_mbx  bus_mbx;
    BusEvt_mbx  bus_evt_mbx[4];

    // MEM: mailboxes para respuestas de memoria
    MemResp_mbx mem_mbx[4];

    initial begin
        CoreRequest req;
        BusRequest  bus_req;
        // Formato de impresión temporal en ns para trazas coherentes en consola.
        $timeformat(-9, 3, " ns", 10);

        $display("========================================");
        $display(" TEST CACHE (MSI + FIREFLY COMPLETO)");
        $display("========================================");

        // Crear mailboxes para comunicación
        foreach (core_mbx[i]) core_mbx[i] = new();
        foreach (bus_evt_mbx[i]) bus_evt_mbx[i] = new();
        foreach (mem_mbx[i]) mem_mbx[i] = new();

        bus_mbx = new();

        // Crear instancias de caches con diferentes protocolos
        cache0 = new(0, Cache::MSI, BUS_MBX_DEPTH);
        cache1 = new(1, Cache::MSI, BUS_MBX_DEPTH);
        cache2 = new(2, Cache::FIREFLY, BUS_MBX_DEPTH);
        cache3 = new(3, Cache::FIREFLY, BUS_MBX_DEPTH);

        fsm_monitor = new();
        fsm_monitor.enable_transition_export("Codigo Fuente/sim_results/fsm_transitions_cache_tb.csv");
        cache0.fsm_monitor = fsm_monitor;
        cache1.fsm_monitor = fsm_monitor;
        cache2.fsm_monitor = fsm_monitor;
        cache3.fsm_monitor = fsm_monitor;

        // Conexiones core-cache y bus
        cache0.from_core = core_mbx[0];
        cache1.from_core = core_mbx[1];
        cache2.from_core = core_mbx[2];
        cache3.from_core = core_mbx[3];

        cache0.to_bus = bus_mbx;
        cache1.to_bus = bus_mbx;
        cache2.to_bus = bus_mbx;
        cache3.to_bus = bus_mbx;

        // Cada caché recibe eventos de su propio mailbox
        cache0.from_bus = bus_evt_mbx[0];
        cache1.from_bus = bus_evt_mbx[1];
        cache2.from_bus = bus_evt_mbx[2];
        cache3.from_bus = bus_evt_mbx[3];

        // Cada caché recibe respuestas de memoria de su propio mailbox
        cache0.from_mem = mem_mbx[0];
        cache1.from_mem = mem_mbx[1];
        cache2.from_mem = mem_mbx[2];
        cache3.from_mem = mem_mbx[3];

        bus = new(bus_mbx, bus_evt_mbx, mem_mbx, 4);

        fork
            cache0.run();
            cache1.run();
            cache2.run();
            cache3.run();
        join_none

        bus.run();

        #10;

        // MSI TEST (cache0 y cache1)
        $display("\nMSI TEST");

        // I -> S
        req = new(PrRd, 32'h1000, 0); core_mbx[0].put(req); #20;

        // S -> S (mismo core)
        req = new(PrRd, 32'h1000, 0); core_mbx[0].put(req); #20;

        // otro core lee → ambos en S
        req = new(PrRd, 32'h1000, 1); core_mbx[1].put(req); #20;

        // write -> S -> M + invalidate
        req = new(PrWr, 32'h1000, 0); core_mbx[0].put(req); #40;

        // otro lee -> M -> S
        req = new(PrRd, 32'h1000, 1); core_mbx[1].put(req); #40;

        // write del otro -> invalida
        req = new(PrWr, 32'h1000, 1); core_mbx[1].put(req); #40;

        // FIREFLY TEST (cache2 y cache3)
        $display("\nFIREFLY TEST");

        // I -> S
        req = new(PrRd, 32'h2000, 2); core_mbx[2].put(req); #20;
        req = new(PrRd, 32'h2000, 3); core_mbx[3].put(req); #20;

        // WRITE -> UPDATE (NO invalidate)
        req = new(PrWr, 32'h2000, 3); core_mbx[3].put(req); #40;

        // ambos siguen en S
        req = new(PrRd, 32'h2000, 2); core_mbx[2].put(req); #20;
        req = new(PrRd, 32'h2000, 3); core_mbx[3].put(req); #20;

        // otro update
        req = new(PrWr, 32'h2000, 2); core_mbx[2].put(req); #40;

        $display("\nFIN TEST COMPLETO");
        #50;
        cache0.print_metrics();
        cache1.print_metrics();
        cache2.print_metrics();
        cache3.print_metrics();
        bus.print_metrics();
        if (fsm_monitor != null) begin
            fsm_monitor.close();
        end
        $finish;
    end

endmodule