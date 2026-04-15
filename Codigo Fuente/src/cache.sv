import types_pkg::*;

class Cache;

    int cache_id;
    localparam NUM_LINES = 64;

    // Mailboxes
    CoreReq_mbx from_core;
    BusReq_mbx  to_bus;
    BusEvt_mbx  from_bus;   // aún no usado
    MemResp_mbx from_mem;

    typedef enum {I, S, M} state_e;

    typedef struct {
        logic [31:0] tag;
        state_e state;
        bit valid;
    } cache_line_t;

    cache_line_t lines[NUM_LINES];

    function new(int cache_id);
        this.cache_id = cache_id;

        foreach (lines[i]) begin
            lines[i].valid = 0;
            lines[i].state = I;
            lines[i].tag   = 0;
        end
    endfunction

    function int get_index(logic [31:0] addr);
        return addr[10:5];
    endfunction

    function logic [31:0] get_tag(logic [31:0] addr);
        return addr[31:11];
    endfunction

    virtual task run();

        if (from_core == null || to_bus == null || from_mem == null) begin
            $fatal(1, "[Cache %0d] Mailboxes no inicializados", cache_id);
        end

        $display("@%0t [Cache %0d] Iniciando", $time, cache_id);

        fork
            handle_core_requests();
        join

    endtask

    task handle_core_requests();

        CoreRequest req;
        BusRequest bus_req;
        MemResponse mem_resp;

        int index;
        logic [31:0] tag;
        cache_line_t line;
        bit hit;

        forever begin
            from_core.get(req);

            index = get_index(req.address);
            tag   = get_tag(req.address);
            line  = lines[index];

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

                    // Upgrade S -> M
                    if (line.state == S) begin
                        lines[index].state = M;
                    end
                end

            end

            // MISS
            else begin

                if (req.req_type == PrRd) begin

                    $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                        $time, cache_id, req.address);

                    bus_req = new(BusRd, req.address, cache_id);
                    to_bus.put(bus_req);

                    // esperar memoria
                    from_mem.get(mem_resp);

                    $display("@%0t [Cache %0d] MemResp recibido -> cargar en S",
                        $time, cache_id);

                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = S;

                end
                else begin

                    $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                        $time, cache_id, req.address);

                    bus_req = new(BusRdX, req.address, cache_id);
                    to_bus.put(bus_req);

                    // esperar memoria
                    from_mem.get(mem_resp);

                    $display("@%0t [Cache %0d] MemResp recibido -> cargar en M",
                        $time, cache_id);

                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = M;

                end
            end
        end
    endtask

endclass