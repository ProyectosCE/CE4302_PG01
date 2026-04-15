`timescale 1ns/1ns

module types_tb;

    import types_pkg::*;

    initial begin
        // Declaraciones de variables al inicio
     CoreRequest cr;
     BusRequest br;
     BusEvent be;
     MemResponse mr;
     CoreReq_mbx mbx;
     CoreRequest cr2;

        $display("TEST types_pkg");

        // Test CoreRequest
        cr = new(PrRd, 32'h1000, 0);
        cr.print();

        // Test BusRequest
        br = new(BusRdX, 32'h2000, 1);
        br.print();

        // Test BusEvent
        be = new(BusUpd, 32'h3000, 2);
        be.print();

        // Test MemResponse
        mr = new(32'h4000, 3);
        mr.print();

        // Test Mailbox
        mbx = new();
        mbx.put(cr);
        mbx.get(cr2);
        $display("Mailbox test -> recibido:");
        cr2.print();

        $display("TEST PASSED");
        $finish;
    end

endmodule