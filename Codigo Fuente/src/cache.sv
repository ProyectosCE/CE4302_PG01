import types_pkg::*;

class Cache;

    int cache_id;
    localparam NUM_LINES = 64;

    // Mailboxes
    CoreReq_mbx from_core;
    BusReq_mbx  to_bus;
    BusEvt_mbx  from_bus;
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

        if (from_core == null || to_bus == null || from_mem == null || from_bus == null) begin
            $fatal(1, "[Cache %0d] Mailboxes no inicializados", cache_id);
        end

        $display("@%0t [Cache %0d] Iniciando", $time, cache_id);

        fork
            handle_core_requests();
            handle_bus_snoop();
        join

    endtask

    // CORE
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

            if (hit) begin

                if (req.req_type == PrRd) begin
                    $display("@%0t [Cache %0d] PrRd %h -> HIT (%0d)",
                        $time, cache_id, req.address, line.state);
                end
                else begin
                    $display("@%0t [Cache %0d] PrWr %h -> HIT (%0d)",
                        $time, cache_id, req.address, line.state);

                    if (line.state == S) begin
                        bus_req = new(BusRdX, req.address, cache_id);
                        to_bus.put(bus_req);

                        from_mem.get(mem_resp);

                        lines[index].state = M;
                    end
                end

            end
            else begin

                if (req.req_type == PrRd) begin

                    $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                        $time, cache_id, req.address);

                    bus_req = new(BusRd, req.address, cache_id);
                    to_bus.put(bus_req);

                    from_mem.get(mem_resp);

                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = S;

                end
                else begin

                    $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                        $time, cache_id, req.address);

                    bus_req = new(BusRdX, req.address, cache_id);
                    to_bus.put(bus_req);

                    from_mem.get(mem_resp);

                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = M;

                end
            end
        end
    endtask

    // SNOOP
    task handle_bus_snoop();

        BusEvent evt;
        int index;
        logic [31:0] tag;
        cache_line_t line;

        forever begin
            from_bus.get(evt);

            // ignorar eventos propios
            if (evt.src_core_id == cache_id)
                continue;

            index = get_index(evt.address);
            tag   = get_tag(evt.address);
            line  = lines[index];

            if (!(line.valid && line.tag == tag))
                continue;

            case (evt.req_type)

                BusRd: begin
                    if (line.state == M) begin
                        $display("@%0t [Cache %0d] SNOOP BusRd -> M->S (WB)",
                            $time, cache_id);
                        lines[index].state = S;
                    end
                end

                BusRdX: begin
                    if (line.state == S) begin
                        $display("@%0t [Cache %0d] SNOOP BusRdX -> S->I",
                            $time, cache_id);
                        lines[index].state = I;
                        lines[index].valid = 0;
                    end
                    else if (line.state == M) begin
                        $display("@%0t [Cache %0d] SNOOP BusRdX -> M->I (WB)",
                            $time, cache_id);
                        lines[index].state = I;
                        lines[index].valid = 0;
                    end
                end

                BusUpd: begin
                    if (line.state == S) begin
                        $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece S",
                            $time, cache_id);
                    end
                end

            endcase
        end
    endtask

endclass