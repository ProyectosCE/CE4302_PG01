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

    /** @brief Devuelve un nombre legible para el estado de coherencia. */
    function string state_name(state_e state);
        case (state)
            Invalid:  return "I";
            Shared:   return "S";
            Modified: return "M";
            default:  return "?";
        endcase
    endfunction

    /** @brief Devuelve un nombre legible para el tipo de evento de bus. */
    function string evt_name(bus_req_type_e req_type);
        case (req_type)
            BusRd:  return "BusRd";
            BusRdX: return "BusRdX";
            BusUpd: return "BusUpd";
            default: return "Unknown";
        endcase
    endfunction

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
                // Firefly write miss: request exclusive ownership and become Modified.
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
        state_e old_state;
        state_e new_state;

        if (evt.src_core_id == cache_id) begin
            return;
        end

        // Solo procesa si la línea es válida y el tag coincide
        if (!(line.valid && line.tag == tag)) begin
            return;
        end

        // Ignora eventos anteriores al llenado de la línea (causalidad).
        if (evt.t_broadcast < line.last_fill_time) begin
            $display("@%0t [Cache %0d] IGNORE stale evt type=%s addr=%h t_evt=%0t fill=%0t state=%s",
                $realtime,
                cache_id,
                evt_name(evt.req_type),
                evt.address,
                time'(evt.t_broadcast),
                time'(line.last_fill_time),
                state_name(line.state));
            return;
        end

        $display("@%0t [Cache %0d] APPLY evt type=%s addr=%h state_before=%s from core=%0d",
            $realtime,
            cache_id,
            evt_name(evt.req_type),
            evt.address,
            state_name(line.state),
            evt.src_core_id);

        old_state = line.state;

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
                if (line.state == Modified) begin
                    line.state = Shared;
                end
                if (line.state == Shared) begin
                    $display("@%0t [Cache %0d] SNOOP BusUpd addr=%h state=S",
                        $realtime, cache_id, evt.address);
                end
            end
        endcase

        new_state = line.state;
        if (new_state != old_state) begin
            $display("@%0t [Cache %0d] SNOOP TRANSITION: %s -> %s addr=%h due_to=%s from core=%0d",
                $realtime,
                cache_id,
                state_name(old_state),
                state_name(new_state),
                evt.address,
                evt_name(evt.req_type),
                evt.src_core_id);
        end

    endtask

endclass
