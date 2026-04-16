`timescale 1ns/1ns

module top_tb;

    import types_pkg::*;
    import model_pkg::*;

    // CONFIG
    localparam NUM_CORES = 4;

    // COMPONENTES
    Core  cores   [NUM_CORES];
    Cache caches  [NUM_CORES];

    CoreReq_mbx core_to_cache [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    BusReq_mbx bus_mbx;

    // CREAR SISTEMA LIMPIO
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

        // CACHES EN PARALELO 
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();

            // BUS + MEMORIA
            forever begin
                BusRequest  bus_req;
                BusEvent    evt;
                MemResponse mem_resp;

                bus_mbx.get(bus_req);

                $display("@%0t [BUS] type=%0d addr=%h core=%0d",
                    $time, bus_req.req_type, bus_req.address, bus_req.src_core_id);

                evt = new(bus_req.req_type, bus_req.address, bus_req.src_core_id);

                bus_evt_mbx[0].put(evt);
                bus_evt_mbx[1].put(evt);
                bus_evt_mbx[2].put(evt);
                bus_evt_mbx[3].put(evt);

                #10;

                mem_resp = new(bus_req.address, bus_req.src_core_id);
                mem_mbx[bus_req.src_core_id].put(mem_resp);
            end
        join_none

        #10;

    endtask

    // EJECUTAR CORES
    task run_cores();
        fork
            cores[0].run();
            cores[1].run();
            cores[2].run();
            cores[3].run();
        join
    endtask

    // TEST
    initial begin

        CoreRequest req;

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

        $display("\n========== FIN DEMO ==========");
        $finish;

    end

endmodule