/*
 * ============================================
 * ARCHIVO: protocol_firefly.sv
 * DESCRIPCIÓN GENERAL:
 *   Implementación concreta del protocolo Firefly (write-update).
 *   Encapsula la lógica de coherencia para solicitudes del core y snooping.
 *
 * POLIMORFISMO:
 *   - Extiende ProtocolBase.
 *   - Cache delega en esta clase cuando se configura Cache::FIREFLY.
 * ============================================
 */

/**
 * ============================================
 * CLASE: ProtocolFirefly
 * DESCRIPCIÓN:
 *   Implementa exactamente la semántica Firefly previamente embebida en Cache.
 *
 * RESPONSABILIDAD:
 *   - Resolver hit/miss de PrRd y PrWr.
 *   - Emitir BusUpd en escrituras sobre estado S (write-update).
 *   - Atender snoop BusRd, BusRdX y BusUpd manteniendo compatibilidad.
 * ============================================
 */
class ProtocolFirefly extends ProtocolBase;

    /**
     * @brief Lógica Firefly para solicitudes del core.
     */
    virtual task handle_core_request(
        input int cache_id,
        input CoreRequest req,
        input int index,
        input logic [31:0] tag,
        ref cache_line_t line,
        input BusReq_mbx to_bus,
        input MemResp_mbx from_mem
    );
        BusRequest bus_req;
        MemResponse mem_resp;
        bit hit;

        hit = (line.valid && line.tag == tag && line.state != I);

        // HIT
        if (hit) begin
            if (req.req_type == PrRd) begin
                $display("@%0t [Cache %0d] PrRd %h -> HIT (%0d)",
                    $realtime, cache_id, req.address, line.state);
            end
            else begin // PrWr
                $display("@%0t [Cache %0d] PrWr %h -> HIT (%0d)",
                    $realtime, cache_id, req.address, line.state);

                // Escritura sobre línea compartida: update por BusUpd
                if (line.state == S) begin
                    bus_req = new(BusUpd, req.address, cache_id);
                    to_bus.put(bus_req);

                    // Permanece en estado S (Firefly)
                end
            end
        end

        // MISS
        else begin
            if (req.req_type == PrRd) begin
                $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRd, req.address, cache_id);
                to_bus.put(bus_req);
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = S;
            end
            else begin // PrWr
                $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRdX, req.address, cache_id);
                to_bus.put(bus_req);
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = M;
            end
        end
    endtask


    /**
     * @brief Lógica Firefly para eventos de snoop.
     */
    virtual task handle_snoop(
        input int cache_id,
        input BusEvent evt,
        input int index,
        input logic [31:0] tag,
        ref cache_line_t line
    );
        // Solo procesa si la línea es válida y el tag coincide
        if (!(line.valid && line.tag == tag)) begin
            return;
        end

        case (evt.req_type)
            // BusRd
            BusRd: begin
                if (line.state == M) begin
                    $display("@%0t [Cache %0d] SNOOP BusRd -> M->S (WB)",
                        $realtime, cache_id);
                    line.state = S;
                end
            end

            // BusRdX
            BusRdX: begin
                if (line.state == S || line.state == M) begin
                    $display("@%0t [Cache %0d] SNOOP BusRdX -> -> I",
                        $realtime, cache_id);
                    line.state = I;
                    line.valid = 0;
                end
            end

            // BusUpd
            BusUpd: begin
                if (line.state == S) begin
                    $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece S",
                        $realtime, cache_id);
                end
            end
        endcase

    endtask

endclass
