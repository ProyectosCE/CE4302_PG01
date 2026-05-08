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
        ref int bus_stall_count,
        ref real total_bus_stall_time,
        input int BUS_MBX_DEPTH
    );
        BusRequest bus_req;
        MemResponse mem_resp;
        bit hit;

        real t_put_start;
        real t_put_end;
        real stall_time;
        int occupancy_before;

        hit = (line.valid && line.tag == tag && line.state != Invalid);

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
                if (line.state == Shared) begin
                    bus_req = new(BusUpd, req.address, cache_id);
                    occupancy_before = to_bus.num();

                    if (occupancy_before >= BUS_MBX_DEPTH) begin
                        bus_stall_count++;
                        $display(
                            "@%0t [Cache %0d][STALL] waiting_bus type=%0d addr=%h occ=%0d/%0d",
                            $realtime,
                            cache_id,
                            bus_req.req_type,
                            bus_req.address,
                            occupancy_before,
                            BUS_MBX_DEPTH
                        );
                    end

                    t_put_start = $realtime;
                    to_bus.put(bus_req);
                    t_put_end = $realtime;
                    stall_time = t_put_end - t_put_start;
                    total_bus_stall_time += stall_time;
                     $display(
                        "@%0t [Cache %0d][PUT] type=%0d addr=%h stall=%0f ns occ_after=%0d",
                        $realtime,
                        cache_id,
                        bus_req.req_type,
                        bus_req.address,
                        stall_time,
                        to_bus.num()
                    );

                    // Permanece en estado Shared (Firefly)
                end
            end
        end

        // MISS
        else begin
            if (req.req_type == PrRd) begin
                $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRd, req.address, cache_id);
                occupancy_before = to_bus.num();

                if (occupancy_before >= BUS_MBX_DEPTH) begin
                    bus_stall_count++;
                    $display(
                        "@%0t [Cache %0d][STALL] waiting_bus type=%0d addr=%h occ=%0d/%0d",
                        $realtime,
                        cache_id,
                        bus_req.req_type,
                        bus_req.address,
                        occupancy_before,
                        BUS_MBX_DEPTH
                    );
                end

                t_put_start = $realtime;
                to_bus.put(bus_req);
                t_put_end = $realtime;
                stall_time = t_put_end - t_put_start;
                total_bus_stall_time += stall_time;
                 $display(
                    "@%0t [Cache %0d][PUT] type=%0d addr=%h stall=%0f ns occ_after=%0d",
                    $realtime,
                    cache_id,
                    bus_req.req_type,
                    bus_req.address,
                    stall_time,
                    to_bus.num()
                );
                from_mem.get(mem_resp);

                line.tag   = tag;
                line.valid = 1;
                line.state = Shared;
            end
            else begin // PrWr
                $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                    $realtime, cache_id, req.address);

                bus_req = new(BusRdX, req.address, cache_id);
                occupancy_before = to_bus.num();

                if (occupancy_before >= BUS_MBX_DEPTH) begin
                    bus_stall_count++;
                    $display(
                        "@%0t [Cache %0d][STALL] waiting_bus type=%0d addr=%h occ=%0d/%0d",
                        $realtime,
                        cache_id,
                        bus_req.req_type,
                        bus_req.address,
                        occupancy_before,
                        BUS_MBX_DEPTH
                    );
                end

                t_put_start = $realtime;
                to_bus.put(bus_req);
                t_put_end = $realtime;
                stall_time = t_put_end - t_put_start;
                total_bus_stall_time += stall_time;
                 $display(
                    "@%0t [Cache %0d][PUT] type=%0d addr=%h stall=%0f ns occ_after=%0d",
                    $realtime,
                    cache_id,
                    bus_req.req_type,
                    bus_req.address,
                    stall_time,
                    to_bus.num()
                );
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
                if (line.state == Modified) begin
                    $display("@%0t [Cache %0d] SNOOP BusRd -> Modified->Shared (WB)",
                        $realtime, cache_id);
                    line.state = Shared;
                end
            end

            // BusRdX
            BusRdX: begin
                if (line.state == Shared || line.state == Modified) begin
                    $display("@%0t [Cache %0d] SNOOP BusRdX -> -> Invalid",
                        $realtime, cache_id);
                    line.state = Invalid;
                    line.valid = 0;
                end
            end

            // BusUpd
            BusUpd: begin
                if (line.state == Shared) begin
                    $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece Shared",
                        $realtime, cache_id);
                end
            end
        endcase

    endtask

endclass
