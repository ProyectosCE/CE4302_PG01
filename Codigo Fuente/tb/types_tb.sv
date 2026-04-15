`timescale 1ns/1ns

module types_tb;

    import types_pkg::*;

    initial begin
        // Declaraciones de variables al inicio
        CoreRequest cr;
        BusRequest br;
        BusEvent be;
        MemResponse mr;
        mailbox #(CoreRequest) mbx;
        CoreRequest cr2;

        $display("TEST types_pkg");

        // Test CoreRequest
        cr = new(PrRd, 32'h1000, 0);
        $display("CoreRequest -> req_type=%0d addr=%h core=%0d",
             cr.req_type, cr.address, cr.src_core_id);

        // Test BusRequest
        br = new(BusRdX, 32'h2000, 1);
        $display("BusRequest -> req_type=%0d addr=%h core=%0d",
             br.req_type, br.address, br.src_core_id);

        // Test BusEvent
        be = new(BusUpd, 32'h3000, 2);
        $display("BusEvent -> req_type=%0d addr=%h core=%0d",
             be.req_type, be.address, be.src_core_id);

        // Test MemResponse
        mr = new(32'h4000, 3);
        $display("MemResponse -> addr=%h dest=%0d",
                 mr.address, mr.dest_core_id);

        // Test Mailbox
        mbx = new();
        mbx.put(cr);
        mbx.get(cr2);
        $display("Mailbox test -> received addr=%h core=%0d",
                 cr2.address, cr2.src_core_id);

        $display("TEST PASSED");
        $finish;
    end

endmodule