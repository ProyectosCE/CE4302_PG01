`timescale 1ns/1ns

module cache_tb;

    import types_pkg::*;
    import model_pkg::*;

    Cache cache;

    CoreReq_mbx core_mbx;
    BusReq_mbx  bus_mbx;
    MemResp_mbx mem_mbx;

    initial begin
        CoreRequest req;
        BusRequest  bus_req;
        MemResponse mem_resp;

        $display("TEST CACHE (MSI BASICO)");

        core_mbx = new();
        bus_mbx  = new();
        mem_mbx  = new();

        cache = new(0);
        cache.from_core = core_mbx;
        cache.to_bus    = bus_mbx;
        cache.from_mem  = mem_mbx;

        // correr cache
        fork
            cache.run();

            // Dummy BUS + MEMORY
            forever begin
                bus_mbx.get(bus_req);

                $display("@%0t [TB] Bus recibio req type=%0d addr=%h",
                    $time, bus_req.req_type, bus_req.address);

                #10;

                // responder memoria
                mem_resp = new(bus_req.address, bus_req.src_core_id);
                mem_mbx.put(mem_resp);
            end

        join_none

        #10;

        // TEST SECUENCIAL
        req = new(PrRd, 32'h1000, 0); core_mbx.put(req); #20;
        req = new(PrRd, 32'h1000, 0); core_mbx.put(req); #20;
        req = new(PrWr, 32'h1000, 0); core_mbx.put(req); #20;
        req = new(PrRd, 32'h2000, 0); core_mbx.put(req); #20;
        req = new(PrWr, 32'h2000, 0); core_mbx.put(req); #20;

        $display("FIN TEST");
        #50;
        $finish;
    end

endmodule