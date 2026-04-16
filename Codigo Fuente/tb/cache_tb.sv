
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
 * ============================================
 */
`timescale 1ns/1ns

module cache_tb;

    import types_pkg::*;
    import model_pkg::*;

    // 4 CACHES: Dos con MSI, dos con Firefly
    Cache cache0; // MSI
    Cache cache1; // MSI
    Cache cache2; // Firefly
    Cache cache3; // Firefly

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
        BusEvent    evt;
        MemResponse mem_resp;

        $display("========================================");
        $display(" TEST CACHE (MSI + FIREFLY COMPLETO)");
        $display("========================================");

        // Crear mailboxes para comunicación
        foreach (core_mbx[i]) core_mbx[i] = new();
        foreach (bus_evt_mbx[i]) bus_evt_mbx[i] = new();
        foreach (mem_mbx[i]) mem_mbx[i] = new();

        bus_mbx = new();

        // Crear instancias de caches con diferentes protocolos
        cache0 = new(0, Cache::MSI);
        cache1 = new(1, Cache::MSI);
        cache2 = new(2, Cache::FIREFLY);
        cache3 = new(3, Cache::FIREFLY);

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
        foreach (bus_evt_mbx[i]) begin
            cache0.from_bus = bus_evt_mbx[0];
            cache1.from_bus = bus_evt_mbx[1];
            cache2.from_bus = bus_evt_mbx[2];
            cache3.from_bus = bus_evt_mbx[3];
        end

        // Cada caché recibe respuestas de memoria de su propio mailbox
        foreach (mem_mbx[i]) begin
            cache0.from_mem = mem_mbx[0];
            cache1.from_mem = mem_mbx[1];
            cache2.from_mem = mem_mbx[2];
            cache3.from_mem = mem_mbx[3];
        end

        fork
            cache0.run();
            cache1.run();
            cache2.run();
            cache3.run();

            // BUS DUMMY GLOBAL: simula el bus compartido y la memoria
            forever begin
                bus_mbx.get(bus_req);

                $display("@%0t [BUS] type=%0d addr=%h core=%0d",
                    $time, bus_req.req_type, bus_req.address, bus_req.src_core_id);

                // broadcast a TODOS
                evt = new(bus_req.req_type, bus_req.address, bus_req.src_core_id);

                foreach (bus_evt_mbx[i]) begin
                    bus_evt_mbx[i].put(evt);
                end

                #10;

                // respuesta de memoria al core correcto
                mem_resp = new(bus_req.address, bus_req.src_core_id);
                mem_mbx[bus_req.src_core_id].put(mem_resp);
            end

        join_none

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
        $finish;
    end

endmodule