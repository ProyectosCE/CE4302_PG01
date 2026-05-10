`timescale 1ps/1ps

module memory_tb;

    import types_pkg::*;
    import model_pkg::*;

    localparam int NUM_CORES = 4;

    // Mailboxes
    BusReq_mbx  bus_mbx;
    MemResp_mbx mem_mbx[NUM_CORES];

    MemResp_mbx mem_done_mbx;

    // Memory instance
    Memory memory;

    initial begin
        BusRequest  bus_req;
        MemResponse mem_resp;
        int i;

        // Formato de impresión temporal en ns
        $timeformat(-9, 3, " ns", 10);

        $display("========================================");
        $display("   TEST MEMORIA (METRICS & RESPONSES)");
        $display("========================================");

        // Crear mailboxes
        bus_mbx = new();
        mem_done_mbx = new();
        for (i = 0; i < NUM_CORES; i++) begin
            mem_mbx[i] = new();
        end

        // Instancia de Memory: 4 cores, 8 bytes/ns ancho de banda
        memory = new(bus_mbx, mem_mbx, mem_done_mbx, NUM_CORES, 8.0);

        // Arrancar Memory
        memory.run();

        // ===== TEST 1: BusRd (Lectura) desde core 0 =====
        #10;
        $display("\n[TEST 1] Enviando BusRd desde core 0 a dirección 0x1000");
        bus_req = new(BusRd, 32'h00001000, 0);
        bus_mbx.put(bus_req);

        // Esperar respuesta
        mem_mbx[0].get(mem_resp);
        $display("[TEST 1] MemResponse recibida: addr=%h dest=%0d", mem_resp.address, mem_resp.dest_core_id);
        if (mem_resp.address == 32'h00001000 && mem_resp.dest_core_id == 0) begin
            $display("[TEST 1] ✓ PASS");
        end else begin
            $display("[TEST 1] ✗ FAIL");
        end

        // ===== TEST 2: BusRdX (Lectura Exclusiva) desde core 1 =====
        #10;
        $display("\n[TEST 2] Enviando BusRdX desde core 1 a dirección 0x2000");
        bus_req = new(BusRdX, 32'h00002000, 1);
        bus_mbx.put(bus_req);

        // Esperar respuesta
        mem_mbx[1].get(mem_resp);
        $display("[TEST 2] MemResponse recibida: addr=%h dest=%0d", mem_resp.address, mem_resp.dest_core_id);
        if (mem_resp.address == 32'h00002000 && mem_resp.dest_core_id == 1) begin
            $display("[TEST 2] ✓ PASS");
        end else begin
            $display("[TEST 2] ✗ FAIL");
        end

        // ===== TEST 3: BusUpd (Update) desde core 2 =====
        #10;
        $display("\n[TEST 3] Enviando BusUpd desde core 2 a dirección 0x3000");
        bus_req = new(BusUpd, 32'h00003000, 2);
        bus_mbx.put(bus_req);

        // BusUpd también genera respuesta en memory_tb
        mem_mbx[2].get(mem_resp);
        $display("[TEST 3] MemResponse recibida: addr=%h dest=%0d", mem_resp.address, mem_resp.dest_core_id);
        if (mem_resp.address == 32'h00003000 && mem_resp.dest_core_id == 2) begin
            $display("[TEST 3] ✓ PASS");
        end else begin
            $display("[TEST 3] ✗ FAIL");
        end

        // ===== TEST 4: Múltiples requests desde core 3 =====
        #10;
        $display("\n[TEST 4] Enviando 3 solicitudes desde core 3");
        for (int j = 0; j < 3; j++) begin
            bus_req = new(BusRd, 32'h00004000 + (j << 6), 3);
            bus_mbx.put(bus_req);
            $display("[TEST 4.%0d] BusRd a dirección %h", j, bus_req.address);
        end

        // Recibir 3 respuestas
        for (int j = 0; j < 3; j++) begin
            mem_mbx[3].get(mem_resp);
            $display("[TEST 4.%0d] MemResponse: addr=%h dest=%0d", j, mem_resp.address, mem_resp.dest_core_id);
        end
        $display("[TEST 4] ✓ PASS (3 responses received)");

        // Esperar a que terminen las transacciones pendientes
        #100;

        // Imprimir métricas de memoria
        $display("\n");
        memory.print_metrics();

        $display("\n========================================");
        $display("   TEST COMPLETADO");
        $display("========================================");

        $finish;
    end

endmodule