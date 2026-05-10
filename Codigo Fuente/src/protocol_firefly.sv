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
        ref real max_bus_stall_time,
        input int BUS_MBX_DEPTH,
        input EventMonitor transition_monitor
    );
        BusRequest bus_req;
        MemResponse mem_resp;
        bit hit;


        /*        * NOTA DE IMPLEMENTACIÓN:
         *   - La lógica de medición de stalls de bus se ha integrado directamente en el método send_bus_request.
         *   - Esto permite que cada protocolo (MSI, Firefly) mida de manera consistente el tiempo de espera en el bus sin necesidad de modificar la interfaz del método handle_core_request.
         *   - La variable max_bus_stall_time se actualiza dentro de send_bus_request si el stall actual supera el máximo registrado.
         */
         /* Por qué se añade esta lógica aquí? Para permitir que la lógica de protocolo mida stalls específicos de cada solicitud sin necesidad de modificar la interfaz del método. */
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

                // Escritura sobre línea compartida: update por BusUpd
                if (line.state == Shared) begin
                    bus_req = new(BusUpd, req.address, cache_id);
                    
                    
                    
                    stall_start = $realtime;

                    send_bus_request(cache_id, bus_req, to_bus, bus_stall_count, total_bus_stall_time, BUS_MBX_DEPTH);

                    stall_end = $realtime;
                    stall_time = stall_end - stall_start;

                    bus_stall_count++;
                    total_bus_stall_time += stall_time;

                    if (stall_time > max_bus_stall_time)
                        max_bus_stall_time = stall_time;


                        
                    // Permanece en estado Shared (Firefly)
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
            else begin // PrWr MISS
                        state_e old_state;

                        write_misses++;
                        $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRd + BusUpd",
                            $realtime, cache_id, req.address);

                        old_state = line.state;

                        stall_start = $realtime;

                        // 1. Primero se trae el bloque con BusRd
                        bus_req = new(BusRd, req.address, cache_id);

                        send_bus_request(
                            cache_id,
                            bus_req,
                            to_bus,
                            bus_stall_count,
                            total_bus_stall_time,
                            BUS_MBX_DEPTH
                        );

                        from_mem.get(mem_resp);

                        // 2. Luego se emite BusUpd para difundir la escritura
                        bus_req = new(BusUpd, req.address, cache_id);

                        send_bus_request(
                            cache_id,
                            bus_req,
                            to_bus,
                            bus_stall_count,
                            total_bus_stall_time,
                            BUS_MBX_DEPTH
                        );

                        stall_end = $realtime;
                        stall_time = stall_end - stall_start;

                        bus_stall_count++;
                        total_bus_stall_time += stall_time;

                        if (stall_time > max_bus_stall_time)
                            max_bus_stall_time = stall_time;

                        line.tag   = tag;
                        line.valid = 1;

                        // En este modelo Firefly simplificado se deja Shared porque la escritura
                        // se propaga por BusUpd y la memoria también queda actualizada.
                        line.state = Shared;

                        if (transition_monitor != null) begin
                            transition_monitor.record_transition(
                                $rtoi($realtime),
                                cache_id,
                                req.address,
                                index,
                                old_state,
                                line.state,
                                "PrWr MISS -> BusRd + BusUpd"
                            );
                        end
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
