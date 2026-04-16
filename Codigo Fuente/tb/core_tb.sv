`timescale 1ns/1ns

module core_tb;

    import types_pkg::*;
    import model_pkg::*;

    Core core;

    CoreReq_mbx core_to_cache_mbx;

    initial begin
        CoreRequest req;

        $display("=================================");
        $display(" TEST CORE (TRACE PLAYER)");
        $display("=================================");

        // mailbox
        core_to_cache_mbx = new();

        // crear core
        core = new(0);
        core.to_cache = core_to_cache_mbx;

        // cargar "programa"
        req = new(PrRd, 32'h1000, 0); core.add_request(req);
        req = new(PrWr, 32'h1000, 0); core.add_request(req);
        req = new(PrRd, 32'h2000, 0); core.add_request(req);
        req = new(PrWr, 32'h3000, 0); core.add_request(req);

        // ejecutar
        fork
            core.run();

            // "dummy cache" solo imprime lo que recibe
            forever begin
                CoreRequest rcv;
                core_to_cache_mbx.get(rcv);

                $display("@%0t [DUMMY CACHE] Recibido %s addr=%h core=%0d",
                    $time,
                    (rcv.req_type == PrRd) ? "PrRd" : "PrWr",
                    rcv.address,
                    rcv.src_core_id);
            end

        join_none

        #200;
        $finish;
    end

endmodule