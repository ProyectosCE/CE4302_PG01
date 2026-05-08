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
        input MemResp_mbx from_mem,

        ref int read_hits,
        ref int read_misses,

        ref int write_hits,
        ref int write_misses,

        ref int bus_stall_count,
        ref real total_bus_stall_time,
        input int BUS_MBX_DEPTH
    );
        BusRequest bus_req;
        MemResponse mem_resp;
        bit hit;

        hit = (line.valid && line.tag == tag && line.state != Invalid);

        // HIT
        if (hit) begin
            if (req.req_type == PrRd) begin
                read_hits++;
                $display("@%0t [Cache %0d] PrRd %h -> HIT (%0d)",
                    $realtime, cache_id, req.address, line.state);
            end
            else begin // PrWr
                write_hits++;
                $display("@%0t [Cache %0d] PrWr %h -> HIT (%0d)",
                    $realtime, cache_id, req.address, line.state);

                // Escritura sobre línea compartida: update por BusUpd
                if (line.state == Shared) begin
                    bus_req = new(BusUpd, req.address, cache_id);
                    send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);

                    // Permanece en estado Shared (Firefly)
                end
            end
        end

        // MISS
        else begin
            if (req.req_type == PrRd) begin
                read_misses++;
                $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRd, req.address, cache_id);
                send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = Shared;
            end
            else begin // PrWr
                write_misses++;
                $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRdX, req.address, cache_id);
                send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);
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
        ref cache_line_t line,

        ref int snoop_busrd,
        ref int snoop_busrdx,
        ref int snoop_busupd,

        ref int invalidations_received,
        ref int updates_received,

        ref int writebacks
    );
        // Solo procesa si la línea es válida y el tag coincide
        if (!(line.valid && line.tag == tag)) begin
            return;
        end

        case (evt.req_type)
            // BusRd
            BusRd: begin
                snoop_busrd++;
                if (line.state == Modified) begin
                    $display("@%0t [Cache %0d] SNOOP BusRd -> Modified -> Shared (WB)",
                        $realtime, cache_id);
                    writebacks++;
                    line.state = Shared;
                end
            end

            // BusRdX
            BusRdX: begin
                snoop_busrdx++;
                if (line.state == Shared || line.state == Modified) begin
                    $display("@%0t [Cache %0d] SNOOP BusRdX -> Invalid",
                        $realtime, cache_id);
                    invalidations_received++;
                    line.state = Invalid;
                    line.valid = 0;
                end
            end

            // BusUpd
            BusUpd: begin
                snoop_busupd++;
                updates_received++;
                if (line.state == Shared) begin
                    $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece Shared",
                        $realtime, cache_id);
                end
            end
        endcase

    endtask

endclass
