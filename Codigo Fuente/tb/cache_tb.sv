`timescale 1ns/1ns

module cache_tb;

    import types_pkg::*;
    import model_pkg::*;

    Cache cache0;
    Cache cache1;

    CoreReq_mbx core0_mbx;
    CoreReq_mbx core1_mbx;

    BusReq_mbx  bus_mbx;
    BusEvt_mbx  bus_evt_mbx[2];

    MemResp_mbx mem_mbx[2];

    initial begin
        CoreRequest req;
        BusRequest  bus_req;
        BusEvent    evt;
        MemResponse mem_resp;

        $display("TEST CACHE (MSI + SNOOP)");

        core0_mbx = new();
        core1_mbx = new();
        bus_mbx   = new();

        foreach (bus_evt_mbx[i]) bus_evt_mbx[i] = new();
        foreach (mem_mbx[i]) mem_mbx[i] = new();

        cache0 = new(0);
        cache1 = new(1);

        // conexiones
        cache0.from_core = core0_mbx;
        cache1.from_core = core1_mbx;

        cache0.to_bus = bus_mbx;
        cache1.to_bus = bus_mbx;

        cache0.from_bus = bus_evt_mbx[0];
        cache1.from_bus = bus_evt_mbx[1];

        cache0.from_mem = mem_mbx[0];
        cache1.from_mem = mem_mbx[1];

        fork
            cache0.run();
            cache1.run();

            // BUS GLOBAL
            forever begin
                bus_mbx.get(bus_req);

                $display("@%0t [BUS] req type=%0d addr=%h from core=%0d",
                    $time, bus_req.req_type, bus_req.address, bus_req.src_core_id);

                // broadcast
                evt = new(bus_req.req_type, bus_req.address, bus_req.src_core_id);
                bus_evt_mbx[0].put(evt);
                bus_evt_mbx[1].put(evt);

                #10;

                mem_resp = new(bus_req.address, bus_req.src_core_id);
                mem_mbx[bus_req.src_core_id].put(mem_resp);
            end

        join_none

        #10;

        // ESCENARIO DE COHERENCIA
        req = new(PrRd, 32'h1000, 0); core0_mbx.put(req); #20;
        req = new(PrRd, 32'h1000, 1); core1_mbx.put(req); #20;
        req = new(PrWr, 32'h1000, 1); core1_mbx.put(req); #40;

        $display("FIN TEST");
        #50;
        $finish;
    end

endmodule