import types_pkg::*;

class Core;

    int core_id;

    // Comunicación
    CoreReq_mbx to_cache;

    // "Programa" = lista de requests
    CoreRequest trace_queue[$];

    // Constructor
    function new(int core_id);
        this.core_id = core_id;
    endfunction

    // Cargar trace manual (para testbench o futuro parser)
    function void add_request(CoreRequest req);
        trace_queue.push_back(req);
    endfunction

    // MAIN
    virtual task run();

        if (to_cache == null) begin
            $fatal(1, "[Core %0d] Mailbox to_cache no inicializado", core_id);
        end

        $display("@%0t [Core %0d] Iniciando ejecucion (%0d requests)",
            $time, core_id, trace_queue.size());

        foreach (trace_queue[i]) begin
            CoreRequest req = trace_queue[i];

            $display("@%0t [Core %0d] Enviando %s addr=%h",
                $time, core_id,
                (req.req_type == PrRd) ? "PrRd" : "PrWr",
                req.address);

            to_cache.put(req);

            #10; // delay entre instrucciones (simulación)
        end

        $display("@%0t [Core %0d] Finalizo ejecucion", $time, core_id);

    endtask

endclass