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

        hit = (line.valid && line.tag == tag && line.state != Invalid);

        // HIT
        if (hit) begin
            if (req.req_type == PrRd) begin
            end
            else begin // PrWr
                // Escritura sobre línea compartida: update por BusUpd
                if (line.state == Shared) begin
                    bus_req = new(BusUpd, req.address, cache_id);
                    to_bus.put(bus_req);

                    // Permanece en estado Shared (Firefly)
                end
            end
        end

        // MISS
        else begin
            if (req.req_type == PrRd) begin
                bus_req = new(BusRd, req.address, cache_id);
                to_bus.put(bus_req);
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = Shared;
            end
            else begin // PrWr
                bus_req = new(BusRdX, req.address, cache_id);
                to_bus.put(bus_req);
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = Modified;
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
                if (line.state == Modified)
                    line.state = Shared;
            end

            // BusRdX
            BusRdX: begin
                if (line.state == Shared || line.state == Modified) begin
                    line.state = Invalid;
                    line.valid = 0;
                end
            end

            // BusUpd
            BusUpd: begin
            end
        endcase

    endtask

endclass
