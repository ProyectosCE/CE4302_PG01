`timescale 1ns/1ns

module cache_tb;

    import types_pkg::*;
    import model_pkg::*;

    Cache cache;
    CoreReq_mbx core_mbx;

    initial begin

        CoreRequest req;

        $display("TEST CACHE");

        // Crear mailbox
        core_mbx = new();

        // Crear cache
        cache = new(0);
        cache.from_core = core_mbx;

        // Ejecutar cache en paralelo
        fork
            cache.run();
        join_none

        #10;

        // Secuencia de prueba
        req = new(PrRd, 32'h1000, 0);
        core_mbx.put(req);
        #10;

        req = new(PrRd, 32'h1000, 0);
        core_mbx.put(req);
        #10;

        req = new(PrWr, 32'h1000, 0);
        core_mbx.put(req);
        #10;

        req = new(PrRd, 32'h2000, 0);
        core_mbx.put(req);
        #10;

        req = new(PrWr, 32'h2000, 0);
        core_mbx.put(req);
        #10;

        $display("FIN TEST");
        #20;
        $finish;

    end

endmodule