
/*
 * ============================================
 * ARCHIVO: types_tb.sv
 * DESCRIPCIÓN GENERAL:
 *   Testbench unitario para validar la correcta construcción y funcionamiento
 *   de los tipos y clases definidos en types_pkg.sv.
 *
 * ESCENARIO PROBADO:
 *   - Construcción e impresión de CoreRequest, BusRequest, BusEvent y MemResponse.
 *   - Prueba de funcionamiento de los mailboxes tipados.
 *
 * COMPORTAMIENTO ESPERADO:
 *   - Se deben observar impresiones correctas de cada tipo.
 *   - El mailbox debe transmitir correctamente una solicitud.
 *
 * NOTA DE TIEMPO:
 *   - Se configura $timeformat para mostrar tiempos en ns con una cifra decimal.
 *   - Aunque este test no imprime marcas temporales, se mantiene el mismo criterio
 *     de precisión temporal para consistencia entre testbenches.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
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

        // Formato de impresión temporal unificado para todos los testbenches.
        $timeformat(-9, 3, " ns", 10);

        $display("TEST types_pkg");

        // Test CoreRequest: Debe imprimir correctamente los campos
        cr = new(PrRd, 32'h1000, 0);
        cr.print();

        // Test BusRequest: Debe imprimir correctamente los campos
        br = new(BusRdX, 32'h2000, 1);
        br.print();

        // Test BusEvent: Debe imprimir correctamente los campos
        be = new(BusUpd, 32'h3000, 2);
        be.print();

        // Test MemResponse: Debe imprimir correctamente los campos
        mr = new(32'h4000, 3);
        mr.print();

        // Test Mailbox: Debe transmitir correctamente una solicitud
        mbx = new();
        mbx.put(cr);
        mbx.get(cr2);
        $display("Mailbox test -> recibido:");
        cr2.print();

        $display("TEST PASSED");
        $finish;
    end

endmodule