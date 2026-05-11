/*
 * ============================================
 * ARCHIVO: protocol_msi.sv
 * DESCRIPCIÓN GENERAL:
 *   Implementación concreta del protocolo MSI (write-invalidate).
 *   Encapsula la lógica de coherencia para solicitudes del core y snooping.
 *
 * POLIMORFISMO:
 *   - Extiende ProtocolBase.
 *   - Cache delega en esta clase cuando se configura Cache::MSI.
 * ============================================
 */

/**
 * ============================================
 * CLASE: ProtocolMSI
 * DESCRIPCIÓN:
 *   Implementa exactamente la semántica MSI previamente embebida en Cache.
 *
 * RESPONSABILIDAD:
 *   - Resolver hit/miss de PrRd y PrWr.
 *   - Emitir BusRd/BusRdX según corresponda.
 *   - Atender snoop BusRd, BusRdX y BusUpd manteniendo compatibilidad.
 * ============================================
 */
class ProtocolMSI extends ProtocolBase;

    /**
     * @brief Lógica MSI para solicitudes del core.
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
        ref real max_bus_stall_time,
        input int BUS_MBX_DEPTH,
        input EventMonitor transition_monitor
    );
        BusRequest bus_req;
        MemResponse mem_resp;
        bit hit;

        // Variables locales para medir stalls de bus
        // Estas variables se pueden usar para medir el tiempo de espera en el bus durante esta solicitud.
        /* Por qué se añaden aquí? Para permitir que la lógica de protocolo mida stalls específicos de cada solicitud sin necesidad de modificar la interfaz del método. */
        real stall_start;
        real stall_end;
        real stall_time;

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

                // Escritura sobre línea compartida: invalidate por BusRdX
                if (line.state == Shared) begin
                    state_e old_state;

                    old_state = line.state;

                    bus_req = new(BusRdX, req.address, cache_id);
                    
                    
                    
                    stall_start = $realtime;

                    send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);
                    from_mem.get(mem_resp);

                    stall_end = $realtime;
                    stall_time = stall_end - stall_start;

                    bus_stall_count++;
                    total_bus_stall_time += stall_time;

                    if (stall_time > max_bus_stall_time)
                        max_bus_stall_time = stall_time;

                    line.state = Modified;
                    if (transition_monitor != null) begin
                        transition_monitor.record_transition($rtoi($realtime), cache_id, req.address, index, old_state, line.state, "PrWr HIT Shared -> BusRdX");
                    end
                end
            end
        end

        // MISS
        else begin
            if (req.req_type == PrRd) begin
                state_e old_state;

                read_misses++;
                $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                    $realtime, cache_id, req.address);

                old_state = line.state;
                bus_req = new(BusRd, req.address, cache_id);
                
                
                
                stall_start = $realtime;

                send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);
                from_mem.get(mem_resp);

                stall_end = $realtime;
                stall_time = stall_end - stall_start;

                bus_stall_count++;
                total_bus_stall_time += stall_time;

                if (stall_time > max_bus_stall_time)
                    max_bus_stall_time = stall_time;



                line.tag   = tag;
                line.valid = 1;
                line.state = Shared;
                if (transition_monitor != null) begin
                    transition_monitor.record_transition($rtoi($realtime), cache_id, req.address, index, old_state, line.state, "PrRd MISS -> BusRd");
                end
            end
            else begin // PrWr
                state_e old_state;

                write_misses++;
                $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                    $realtime, cache_id, req.address);

                old_state = line.state;
                bus_req = new(BusRdX, req.address, cache_id);
                
                
                
                stall_start = $realtime;

                send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);
                from_mem.get(mem_resp);

                stall_end = $realtime;
                stall_time = stall_end - stall_start;

                bus_stall_count++;
                total_bus_stall_time += stall_time;

                if (stall_time > max_bus_stall_time)
                    max_bus_stall_time = stall_time;




                line.tag   = tag;
                line.valid = 1;
                line.state = Modified;
                if (transition_monitor != null) begin
                    transition_monitor.record_transition($rtoi($realtime), cache_id, req.address, index, old_state, line.state, "PrWr MISS -> BusRdX");
                end
            end
        end
    endtask


    /**
     * @brief Lógica MSI para eventos de snoop.
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

        ref int writebacks,
        input EventMonitor transition_monitor
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
                    state_e old_state;

                    old_state = line.state;
                    $display("@%0t [Cache %0d] SNOOP BusRd -> Modified -> Shared (WB)",
                        $realtime, cache_id);
                    writebacks++;
                    line.state = Shared;
                    if (transition_monitor != null) begin
                        transition_monitor.record_transition($rtoi($realtime), cache_id, evt.address, index, old_state, line.state, "Snoop BusRd");
                    end
                end
            end

            // BusRdX
            BusRdX: begin
                snoop_busrdx++;
                if (line.state == Shared || line.state == Modified) begin
                    state_e old_state;

                    old_state = line.state;
                    $display("@%0t [Cache %0d] SNOOP BusRdX -> Invalid",
                        $realtime, cache_id);
                    invalidations_received++;
                    line.state = Invalid;
                    line.valid = 0;
                    if (transition_monitor != null) begin
                        transition_monitor.record_transition($rtoi($realtime), cache_id, evt.address, index, old_state, line.state, "Snoop BusRdX");
                    end
                end
            end

            // BusUpd (mantener compatibilidad de trazas)
            BusUpd: begin
                snoop_busupd++;
                if (line.state == Shared) begin
                    $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece Shared",
                        $realtime, cache_id);
                end
            end
        endcase

    endtask

endclass
