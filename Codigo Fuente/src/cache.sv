import types_pkg::*;
class Cache;

    // Parámetros
    int cache_id;

    localparam NUM_LINES = 64;

    // Comunicación (IPC)
    CoreReq_mbx from_core;
    BusReq_mbx  to_bus;      // no se usa aún 
    BusEvt_mbx  from_bus;    // no se usa aún
    MemResp_mbx from_mem;    // no se usa aún

    // Estados de coherencia (simple)
    typedef enum {I, S, M} state_e;

    // Línea de caché
    typedef struct {
        logic [31:0] tag;
        state_e state;
        bit valid;
    } cache_line_t;

    cache_line_t lines[NUM_LINES];

    // Constructor
    function new(int cache_id);
        this.cache_id = cache_id;

        // Inicializar cache en estado inválido
        foreach (lines[i]) begin
            lines[i].valid = 0;
            lines[i].state = I;
            lines[i].tag   = 0;
        end
    endfunction

    // Helpers (address decoding)
    function int get_index(logic [31:0] addr);
        return addr[10:5]; // 6 bits
    endfunction

    function logic [31:0] get_tag(logic [31:0] addr);
        return addr[31:11];
    endfunction

    // MAIN
    virtual task run();

        if (from_core == null) begin
            $fatal(1, "[Cache %0d] Mailbox from_core no inicializado", cache_id);
        end

        $display("@%0t [Cache %0d] Iniciando", $time, cache_id);

        fork
            handle_core_requests();
        join

    endtask

    // Manejo de requests del core
    task handle_core_requests();
        CoreRequest req;
        int index;
        logic [31:0] tag;
        cache_line_t line;
        bit hit;
        forever begin
            from_core.get(req);
            index = get_index(req.address);
            tag = get_tag(req.address);
            line = lines[index];
            hit = (line.valid && line.tag == tag && line.state != I);
            // HIT
            if (hit) begin
                if (req.req_type == PrRd) begin
                    $display("@%0t [Cache %0d] PrRd %h -> HIT (state=%0d)",
                        $time, cache_id, req.address, line.state);
                end
                else begin
                    $display("@%0t [Cache %0d] PrWr %h -> HIT (state=%0d)",
                        $time, cache_id, req.address, line.state);
                    // Upgrade simple a M
                    lines[index].state = M;
                end
            end
            // MISS
            else begin
                if (req.req_type == PrRd) begin
                    $display("@%0t [Cache %0d] PrRd %h -> MISS -> carga en S",
                        $time, cache_id, req.address);
                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = S;
                end
                else begin
                    $display("@%0t [Cache %0d] PrWr %h -> MISS -> carga en M",
                        $time, cache_id, req.address);
                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = M;
                end
            end
        end
    endtask

endclass