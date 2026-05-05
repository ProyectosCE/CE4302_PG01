
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
 *
 * NOTA DE TIEMPO:
 *   - El testbench configura formato en ns y usa $realtime para mostrar
 *     marcas temporales con precisión fraccional cuando aplique.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
`timescale 1ns/1ns

module core_tb;

    import types_pkg::*;
    import model_pkg::*;

    Core core;

    CoreReq_mbx core_to_cache_mbx;
    CoreResp_mbx cache_to_core_mbx;

    initial begin
        CoreRequest req;

        // Formato de impresión temporal en ns para trazas más legibles.
        $timeformat(-9, 3, " ns", 10);

        $display("[%0t] [TB] START TEST core_trace_player", $realtime);

        // mailbox para comunicación core-cache
        core_to_cache_mbx = new();
        cache_to_core_mbx = new();

        // crear core y asociar mailbox
        core = new(0);
        core.to_cache = core_to_cache_mbx;
        core.from_cache = cache_to_core_mbx;

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
                CoreResponse resp;
                core_to_cache_mbx.get(rcv);

                $display("[%0t] [TB] DUMMY_CACHE rx type=%s addr=%s core=%0d",
                    $realtime,
                    core_req_name(rcv.req_type),
                    fmt_addr(rcv.address),
                    rcv.src_core_id);

                // Respuesta inmediata para desbloquear el core.
                resp = new(rcv.req_type, rcv.address, rcv.src_core_id);
                cache_to_core_mbx.put(resp);
            end

        join_none

        #200;
        $finish;
    end

endmodule