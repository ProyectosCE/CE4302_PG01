
/*
 * ============================================
 * ARCHIVO: core_tb.sv
 * DESCRIPCIÓN GENERAL:
 *   Testbench unitario para la clase Core. Simula la generación de un trace de
 *   solicitudes de memoria y verifica que se envían correctamente a la caché.
 *
 * ESCENARIO PROBADO:
 *   - Secuencia de lecturas y escrituras generadas por un core.
 *   - Verificación de la transmisión de solicitudes a la caché mediante mailbox.
 *
 * COMPORTAMIENTO ESPERADO:
 *   - Se observan logs de envío de solicitudes y recepción en la "dummy cache".
 * ============================================
 */
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

        // mailbox para comunicación core-cache
        core_to_cache_mbx = new();

        // crear core y asociar mailbox
        core = new(0);
        core.to_cache = core_to_cache_mbx;

        // cargar "programa" (trace de solicitudes)
        req = new(PrRd, 32'h1000, 0); core.add_request(req);
        req = new(PrWr, 32'h1000, 0); core.add_request(req);
        req = new(PrRd, 32'h2000, 0); core.add_request(req);
        req = new(PrWr, 32'h3000, 0); core.add_request(req);

        // ejecutar: core y dummy cache en paralelo
        fork
            core.run();

            // "dummy cache": solo imprime lo que recibe del core
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