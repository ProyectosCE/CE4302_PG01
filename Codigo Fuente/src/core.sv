class Core;

    // Parámetros
    int core_id;

    // Comunicación (IPC)
    CoreReq_mbx to_cache;  // mailbox hacia la cache

    // Constructor
    function new(int core_id);
        this.core_id = core_id;
    endfunction

    // Tarea principal
    virtual task run();

        CoreRequest req;

        if (to_cache == null) begin
            $fatal(1, "[Core %0d] Mailbox to_cache no inicializado", core_id);
        end

        $display("@%0t [Core %0d] Iniciando ejecución", $time, core_id);

        // Secuencia de prueba (dummy)
        // Write 0x1000
        req = new(PrWr, 32'h1000, core_id);
        $display("@%0t [Core %0d] PrWr addr=%h", $time, core_id, req.address);
        to_cache.put(req);
        #10;

        // Read 0x1000
        req = new(PrRd, 32'h1000, core_id);
        $display("@%0t [Core %0d] PrRd addr=%h", $time, core_id, req.address);
        to_cache.put(req);
        #10;

        // Write 0x2000
        req = new(PrWr, 32'h2000, core_id);
        $display("@%0t [Core %0d] PrWr addr=%h", $time, core_id, req.address);
        to_cache.put(req);
        #10;

        // Read 0x2000
        req = new(PrRd, 32'h2000, core_id);
        $display("@%0t [Core %0d] PrRd addr=%h", $time, core_id, req.address);
        to_cache.put(req);
        #10;

        $display("@%0t [Core %0d] Finalizó generación de requests", $time, core_id);

    endtask

endclass